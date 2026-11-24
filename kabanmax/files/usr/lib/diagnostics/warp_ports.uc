// Flash hints are changed at most once per explicit native profile per router boot.
// The private cursor never commits pending LuCI changes from /tmp/.uci.
let common = require("core.common");
let fs = require("fs");
let lock = require("service.lock");
let paths = { state: "/var/run/kabanmax/warp-port-hints.json", lock: "/var/run/kabanmax.reload.lock", delta: "/var/run/kabanmax/warp-hint-uci" };
let io = {
    now: () => int(common.monotonic_ms() / 1000),
    wall: () => common.now_seconds(),
    config: () => common.read_json_file(require("singbox.constants").config_path(require("core.uci").get_all("kabanmax", "settings") ?? {})),
    request: function() {
        let api = require("singbox.clash_api");
        let reply = api.exchange(api.controller(), "GET", "/kabanmax/warp-paths", { seconds: 2, body: "" });
        let value = reply?.status == 200 ? common.parse_json(reply.body) : null;
        if (type(value?.endpoints) != "array") die("WARP path status unavailable");
        return value;
    }
};

function same_profile(tunnel, profile) {
    if (type(profile) != "object" || !tunnel.warp_profile_id) return false;
    for (let key in [ "id", "auth_token", "private_key", "license_key" ])
        if (common.as_string(tunnel["warp_profile_" + key]) != common.as_string(profile[key])) return false;
    return true;
}

function capture() {
    let owner = common.own_pid();
    if (!lock.acquire(paths.lock, owner)) return false;
    let state = { saved: {}, pending: {} };
    try {
        if (fs.stat(paths.state)) {
            state = common.read_json_file(paths.state);
            if (type(state?.saved) != "object" || type(state?.pending) != "object") die("Invalid WARP boot checkpoint");
        }
        let response = io.request();
        let runtime = io.config();
        let now = io.now();
        let wall = io.wall();
        if (!common.ensure_dir(paths.delta)) die("Cannot create private WARP UCI delta directory");
        let cursor = require("uci").cursor("/etc/config", paths.delta);
        if (cursor.load("kabanmax") == false) die("Cannot load WARP configuration");
        let next = {};
        let updates = [];
        cursor.foreach("kabanmax", "tunnel", function(tunnel) {
            if (tunnel.kind != "warp" || !tunnel.warp_profile_id || !tunnel.warp_profile_auth_token || !tunnel.warp_profile_private_key) return;
            // Ambiguous duplicated credentials are not sufficient ownership evidence.
            let endpoints = filter(runtime?.endpoints ?? [], (e) => e.type == "warp" && same_profile(tunnel, e.profile));
            if (length(endpoints) != 1 || endpoints[0].listen_port > 0 || endpoints[0].profile?.recreate) return;
            let endpoint = endpoints[0];
            let rows = filter(response.endpoints, (r) => r.tag == endpoint.tag);
            if (length(rows) != 1) return;
            let row = rows[0];
            let key = tunnel[".name"] + ":" + tunnel.warp_profile_id;
            let port = int(row.port);
            let saved_port = tunnel.warp_local_port_profile == tunnel.warp_profile_id ? int(tunnel.warp_local_port_hint) : 0;
            if (state.saved[key] || row.profile_id != tunnel.warp_profile_id || port < 1 || port > 65535 || !row.instance ||
                row.data_at <= 0 || row.handshake_at <= 0 || wall < row.handshake_at || wall - row.handshake_at > 180) return;
            let before = state.pending[key];
            let since = before?.port == port && before?.instance == row.instance && now >= before.seen && now - before.seen <= 120 ? before.since : now;
            next[key] = { port, instance: row.instance, since, seen: now };
            if (now - since >= 600) {
                // A successful boot using the durable port also closes the boot window,
                // without a UCI write. Later route changes remain RAM-only.
                if (port == saved_port) { state.saved[key] = true; delete next[key]; }
                else push(updates, { section: tunnel[".name"], key, port, profile: tunnel.warp_profile_id });
            }
        });
        state.pending = next;
        // Reserve the allowance in RAM before any commit, including an ambiguous I/O failure.
        for (let update in updates) { state.saved[update.key] = true; delete state.pending[update.key]; }
        if (!common.write_file_atomic(paths.state, sprintf("%J", state))) die("Cannot reserve WARP boot allowance");
        if (length(updates) > 0) {
            for (let update in updates) {
                if (cursor.set("kabanmax", update.section, "warp_local_port_hint", "" + update.port) == false ||
                    cursor.set("kabanmax", update.section, "warp_local_port_profile", update.profile) == false) die("Cannot stage WARP port hint");
            }
            if (cursor.commit("kabanmax") == false) die("Cannot commit WARP port hint");
            require("core.uci").reset();
        }
        lock.release(paths.lock, owner);
        return true;
    }
    catch (e) {
        // A gap cannot count towards ten continuous healthy minutes. Never clear saved quotas.
        if (type(state?.saved) == "object") common.write_file_atomic(paths.state, sprintf("%J", { saved: state.saved, pending: {} }));
        lock.release(paths.lock, owner);
        return false;
    }
}

return { paths, io, capture };
