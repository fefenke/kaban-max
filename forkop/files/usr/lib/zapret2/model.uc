// One allocation model for sing-box, nftables and procd. Indices count enabled Zapret2 only.
let common = require("core.common");
let uci = require("core.uci");
let fs = require("fs");
let paths = { slots: "/etc/forkop/zapret2-slots.json" };

const BASE = 0x02000000;
const QUEUE = 4300;
const LIMIT = 256;
const BIN = "/opt/forkop-zapret2/current/nfq2/nfqws2";
const LUA = "/opt/forkop-zapret2/current/lua/";
const DEFAULT = "--filter-tcp=80 --filter-l7=http --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2 --new --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tcp_seq=-10000 --lua-desync=multidisorder:pos=1,midsld --new --filter-udp=443 --filter-l7=quic --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6";

// Parse quoting, never evaluate shell syntax. Users may supply current upstream flags, but
// may not replace the queue, process ownership or the mark that prevents recapture.
function arguments(raw) {
    let result = [], token = "", quote = "", escaped = false, started = false;
    for (let i = 0; i < length(raw); i++) {
        let ch = substr(raw, i, 1);
        if (escaped) { token += ch; escaped = false; started = true; continue; }
        if (ch == "\\" && quote != "'") { escaped = true; started = true; continue; }
        if (quote != "") {
            if (ch == quote) quote = ""; else token += ch;
            continue;
        }
        if (ch == "'" || ch == '"') { quote = ch; started = true; continue; }
        if (match(ch, /\s/)) {
            if (started) push(result, token);
            token = ""; started = false;
        }
        else { token += ch; started = true; }
    }
    if (quote != "" || escaped) die("Zapret2 strategy has an unfinished quote or escape");
    if (started) push(result, token);
    if (length(result) == 0) die("Zapret2 strategy is empty");
    for (let arg in result) {
        if (substr(arg, 0, 2) != "--") die("Use --option=value syntax in the Zapret2 strategy: " + arg);
        let name = split(substr(arg, 2), "=")[0];
        for (let owned in [ "qnum", "daemon", "pidfile", "fwmark", "fwmark-postnat", "user", "uid", "version", "help", "dry-run", "intercept" ])
            if (name == "" || substr(owned, 0, length(name)) == name)
                die("Forkop owns the Zapret2 option --" + name);
        if (index(arg, "\x00") >= 0) die("Zapret2 arguments contain a NUL byte");
    }
    return result;
}

function allocations(input) {
    let saved = fs.readfile(paths.slots);
    let slots = saved == null ? {} : json(saved);
    if (type(slots) != "object") die("Invalid Zapret2 slot registry: " + paths.slots);
    let used = {};
    for (let name, value in slots) {
        let slot = int(value);
        if (slot < 1 || slot > LIMIT || used[slot]) die("Invalid or duplicate Zapret2 slot in " + paths.slots);
        used[slot] = true;
    }
    for (let section in input) {
        if (common.option(section, "action", "") != "zapret2" || !common.bool_option(section, "enabled", true)) continue;
        let name = section[".name"];
        if (slots[name] != null) continue;
        let slot = 1;
        while (used[slot] && slot <= LIMIT) slot++;
        if (slot > LIMIT) die("Zapret2's 256 persistent slots are exhausted; retire old connections before resetting the slot registry");
        slots[name] = slot; used[slot] = true;
    }
    return slots;
}

function persist_slots() {
    let slots = allocations(uci.section_objects("forkop", "section"));
    let encoded = sprintf("%J", slots);
    if (fs.readfile(paths.slots) == encoded) return;
    if (!common.ensure_dir(common.parent_dir(paths.slots)) ||
        fs.writefile(paths.slots + ".tmp", encoded) == null || !fs.rename(paths.slots + ".tmp", paths.slots))
        die("Could not persist Zapret2 section marks");
}

function sections(input) {
    input = input ?? uci.section_objects("forkop", "section");
    let slots = allocations(input);
    let result = [];
    for (let section in input) {
        if (common.option(section, "action", "") != "zapret2" || !common.bool_option(section, "enabled", true)) continue;
        if (length(result) >= LIMIT) die("At most 256 Zapret2 sections are supported");
        let index = int(slots[section[".name"]]);
        push(result, { section, mark: BASE + index, mark_hex: sprintf("0x%08x", BASE + index), queue: QUEUE + index - 1 });
    }
    return result;
}

function mark(name) {
    for (let entry in sections())
        if (entry.section[".name"] == name) return entry.mark;
    die("No enabled Zapret2 section: " + name);
}

function instances(with_default) {
    let entries = sections();
    if (with_default) push(entries, { section: { ".name": "default", nfqws2_opt: DEFAULT }, queue: QUEUE });
    return map(entries, (entry) => ({
        name: entry.section[".name"], queue: entry.queue,
        argv: [ BIN, "--qnum=" + entry.queue, "--fwmark=0x40000000",
            "--lua-init=@" + LUA + "zapret-lib.lua", "--lua-init=@" + LUA + "zapret-antidpi.lua",
            "--lua-init=@" + LUA + "zapret-auto.lua",
            ...map(arguments(common.option(entry.section, "nfqws2_opt", DEFAULT) || DEFAULT), (arg) =>
                replace(replace(arg, "/opt/zapret2/files/", "/opt/forkop-zapret2/current/files/"),
                    "/opt/zapret2/lua/", LUA)) ]
    }));
}

return { sections, mark, arguments, instances, persist_slots, paths, BIN, LUA, DEFAULT };
