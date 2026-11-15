let common = require("core.common");
let uci = require("core.uci");
let lock = require("service.lock");
let model = require("config.auto_routing");
let detect = require("diagnostics.auto_detect");
let paths = { lock: "/var/run/kabanmax.reload.lock" };
let tracked = {};
let observations = {};
function observation_key(event) {
    return sprintf("%J", [event.ip, event.port, event.network, event.source_ip ?? "", event.inbound ?? "", event.domain ?? ""]);
}

function request(op, payload) {
    let api = require("singbox.clash_api");
    let reply = api.exchange(api.controller(), op == "state" ? "GET" : "POST", "/kabanmax/auto",
        { seconds: op == "probe" ? 65 : 10, body: op == "state" ? "" : sprintf("%J", { op, ...payload }) });
    if (reply?.status != 200) die("Auto-routing API unavailable or rejected request: " + common.as_string(common.parse_json(reply?.body)?.reason));
    let value = common.parse_json(reply.body);
    if (type(value) != "object") die("Invalid auto-routing API reply");
    return value;
}
let io = { request, logs: () => require("diagnostics.runtime").logs(),
    connections: () => {
        let reply = require("singbox.clash_api").request("GET", "/connections", "");
        return common.parse_json(reply?.body)?.connections ?? [];
    } };

function state() {
    let answer;
    try { answer = io.request("state", {}); }
    catch (e) { answer = { version: 0, reason: e.message, candidates: [], leases: [], decisions: [], history: [] }; }
    let unknown = {};
    for (let line in slice(split(io.logs(), "\n"), -200)) {
        let event = detect.log_candidate(line, common.now_seconds());
        if (event == null) continue;
        let key = observation_key(event);
        if (unknown[key] != null) unknown[key].count++; else unknown[key] = event;
    }
    try {
        let snapshot = detect.stalled(tracked, io.connections(), common.now_seconds());
        tracked = snapshot.tracked;
        for (let event in snapshot.events) unknown[observation_key(event)] = event;
    } catch (e) { }
    for (let key, event in unknown) observations[key] = event;
    for (let key, event in observations) if (common.now_seconds() - event.timestamp > 3600) delete observations[key];
    while (length(keys(observations)) > 128) {
        let oldest = sort(keys(observations), (left, right) => observations[left].timestamp - observations[right].timestamp)[0];
        delete observations[oldest];
    }
    answer.unattributed = values(observations);
    let settings = uci.get_all("kabanmax", "settings") ?? {};
    let config = common.read_json_file(require("singbox.constants").config_path(settings));
    answer.sources = map(config?.route?.kabanmax_auto ?? [], (s) => ({ id: s.id, outbound: s.outbound, domain: s.domain, auto_apply: s.auto_apply, warp: s.warp }));
    answer.warp_profiles = map(filter(config?.endpoints ?? [], (e) => e.type == "warp" && (e.detour == null || e.detour == "direct-out")), (e) => e.tag);
    answer.suppressed_counts = {};
    try {
        let entries = model.suppression().entries;
        answer.suppressed_count = length(entries);
        for (let entry in entries) { let id = common.parse_json(entry.scope)[0]; answer.suppressed_counts[id] = (answer.suppressed_counts[id] ?? 0) + 1; }
    } catch (e) { answer.suppression_error = e.message; }
    return answer;
}

function persist(op, source, keys) {
    let document = model.suppression();
    if (type(document.entries) != "array") die("Suppression store is corrupt; refusing to overwrite it");
    if (op == "reset") document.entries = filter(document.entries, (entry) => common.parse_json(entry.scope)?.[0] != source);
    else for (let key in keys) {
        if (!model.valid_scope(key)) die("Invalid backend suppression scope");
        if (length(filter(document.entries, (entry) => entry.scope == key)) == 0)
            push(document.entries, { owner: "auto-routing", scope: key, created: common.now_seconds() });
    }
    if (length(document.entries) > 1024) die("Suppression store is full");
    if (!common.ensure_dir(common.parent_dir(model.paths.suppression)) || !common.write_file_atomic(model.paths.suppression, sprintf("%J\n", document)))
        die("Runtime rule withdrawn, but persistent suppression could not be saved");
}

function action(op, id, session) {
    if (index(["probe", "apply", "delete", "clear", "reset", "disable"], op) < 0 || type(id) != "string" || length(id) > 200) die("Invalid automatic routing action");
    // The generic read/exec CLI permission must not become a write-RPC bypass.
    let bus = require("ubus").connect();
    if (session == null || session == "" || bus?.call("session", "access", { ubus_rpc_session: session, scope: "ubus", object: "kabanmax", function: "auto_action" })?.access !== true)
        die("Auto-routing write permission denied");
    let owner = common.own_pid();
    if (!lock.acquire(paths.lock, owner)) die("Configuration apply is busy");
    let response;
    try {
        let result;
        if (op == "probe") {
            let candidates = io.request("state", {}).candidates ?? [];
            let event = filter(candidates, (entry) => entry.id == id)[0];
            if (event == null || event.network != "tcp") die("No attributed TCP candidate with this ID");
            result = io.request("probe", { query: { ip: event.ip, domain: event.domain, source_ip: event.source_ip, source_port: event.source_port ?? 0, inbound: event.inbound, port: event.port, source: event.source } });
        }
        else result = io.request(op, { id });
        if (op == "delete" || op == "clear" || op == "reset") persist(op, result.source_id ?? id, result.suppressed ?? []);
        response = { success: true, result };
    }
    catch (e) { lock.release(paths.lock, owner); die(e.message); }
    lock.release(paths.lock, owner);
    return response;
}
return { state, action, persist, paths, io };
