let common = require("core.common");
let uci = require("core.uci");
let lock = require("service.lock");
let model = require("config.auto_routing");
let paths = { lock: "/var/run/kabanmax.reload.lock",pending:"/var/run/kabanmax/auto-routing-events.json" };
let capture_error = "";
let pressure=false;

function request(op, payload) {
    let api = require("singbox.clash_api");
    let reply = api.exchange(api.controller(), op == "state" ? "GET" : "POST", "/kabanmax/auto",
        { seconds: op == "probe" ? 65 : index(["state","checkpoint"],op)>=0 ? 2 : 10, body: op == "state" ? "" : sprintf("%J", { op, ...payload }) });
    if (reply?.status != 200) die("Auto-routing API unavailable or rejected request: " + common.as_string(common.parse_json(reply?.body)?.reason));
    let value = common.parse_json(reply.body);
    if (type(value) != (op=="checkpoint" ? "array" : "object")) die("Invalid auto-routing API reply");
    return value;
}
let io = { request };
function checkpoint(leases, remembered) {
    if(leases==null)leases=io.request("state",{}).leases ?? [];
    if(remembered!=true)require("config.auto_registry").remember(leases);
    let rows;
    try { rows=io.request("checkpoint",{}); }
    catch(e) {
        // A timeout or transient API error must not replace private connection
        // metadata with the reduced public State representation.
        if(index(e.message,"unknown operation")<0)die(e.message);
        // Upgrade from r15: its public events remain usable where the current
        // matcher can prove scope without the new private metadata extension.
        let old=io.request("state",{});if(old.registry_version!=3)die(e.message);
        rows=old.candidates ?? [];
    }
    if(type(rows)!="array")die("Invalid private registry checkpoint");
    let text=sprintf("%J",rows);if(length(text)>int(require("config.auto_storage").settings().memory_bytes/2))die("Private registry checkpoint exceeds RAM limit");
    if(!common.write_file_atomic(paths.pending,text))die("Cannot save pending registry in RAM");
    require("fs").chmod(paths.pending,0600);
    return true;
}

function state() {
    let answer;
    try { answer = io.request("state", {}); }
    catch (e) { answer = { version: 0, reason: e.message, candidates: [], leases: [], decisions: [], history: [] }; }
    // Only error events attributed by the winning core route belong here.
    // Generic logs and connection counters cannot establish section ownership.
    answer.unattributed = [];
    answer.registry_error = capture_error;
    let diagnostics=require("config.auto_diagnostics");
    answer.leases=map(answer.leases ?? [],diagnostics.enricher());
    answer.diagnostics_error=diagnostics.error();
    let settings = uci.get_all("kabanmax", "settings") ?? {};
    let config = common.read_json_file(require("singbox.constants").config_path(settings));
    answer.sources = map(config?.route?.kabanmax_auto ?? [], (s) => ({ id: s.id, outbound: s.outbound, domain: s.domain, mode: s.mode, auto_apply: s.auto_apply, direct: s.direct, warp: s.warp, warp_section: s.warp_section }));
    answer.warp_profiles = map(filter(config?.endpoints ?? [], (e) => e.type == "warp" && (e.detour == null || e.detour == "direct-out")), (e) => e.tag);
    answer.warp_sections=model.warp_sections(config ?? {},uci.section_objects("kabanmax","section"),(id)=>require("singbox.constants").outbound_tag(require("config.connections").section_display_name(id)));
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
    require("config.auto_registry").save("excluded",document.entries);
}

function action(op, id, session) {
    if (index(["records", "probe", "apply", "delete", "clear", "reset", "disable"], op) < 0 || type(id) != "string" || length(id) > (op=="records" ? 16384 : 200)) die("Invalid automatic routing action");
    // The generic read/exec CLI permission must not become a write-RPC bypass.
    let bus = require("ubus").connect();
    if (session == null || session == "" || bus?.call("session", "access", { ubus_rpc_session: session, scope: "ubus", object: "kabanmax", function: "auto_action" })?.access !== true)
        die("Auto-routing write permission denied");
    let owner = common.own_pid();
    if (!lock.acquire(paths.lock, owner)) die("Configuration apply is busy");
    if(op=="records") {
        try {let reply=require("diagnostics.auto_registry").run(id);require("diagnostics.auto_records").invalidate();lock.release(paths.lock,owner);return reply;}
        catch(e){require("diagnostics.auto_records").invalidate();lock.release(paths.lock,owner);die(e.message);}
    }
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
    catch (e) { require("diagnostics.auto_records").invalidate(); lock.release(paths.lock, owner); die(e.message); }
    require("diagnostics.auto_records").invalidate();
    lock.release(paths.lock, owner);
    return response;
}
function capture() {
    pressure=false;
    let owner=common.own_pid();if(!lock.acquire(paths.lock,owner))return false;
    let answer;let grants_saved=false;
    try {
        answer=io.request("state",{});
        pressure=answer.memory_pressure==true;
        if(answer.registry_version==2)require("config.auto_registry").remember(answer.leases);
        if(answer.registry_version==3) {
            require("config.auto_registry").remember(answer.leases ?? []);
            grants_saved=true;
            checkpoint(answer.leases ?? [],true);
        }
        // Use the same lifecycle lock as mutations: a checkpoint must never
        // race with a newer applied/excluded RAM snapshot from another worker.
        require("config.auto_registry").flush(pressure);
        capture_error="";
    } catch(e) {
        capture_error=e.message;
        // If durable capture fails, withdraw only grants absent from the saved
        // registry. Never silently advertise an unpersisted automatic approval.
        let entries;try {entries=require("config.auto_registry").load().entries;}catch(_){entries=[];}
        // Private flow metadata is recoverable on the next sweep. Its failure
        // must not withdraw approvals already recorded in the intent store.
        for(let row in grants_saved ? [] : answer?.leases ?? []) {
            let key=require("config.auto_registry").key(row);
            if(length(filter(entries,(entry)=>entry.scope==key && entry.record.target==row.target))>0)continue;
            try{io.request("registry_withdraw",{source_id:row.source_id,id:row.id});}catch(_){try{io.request("disable",{id:row.source_id});}catch(__){}}
        }
        lock.release(paths.lock,owner);return false;
    }
    require("diagnostics.auto_records").invalidate();lock.release(paths.lock,owner);return true;
}
return { state, action, persist, capture, checkpoint, paths, io, memory_pressure:()=>pressure };
