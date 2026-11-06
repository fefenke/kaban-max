let fs = require("fs");
let exec = require("core.exec");
let model = require("zapret2.model");
const INIT = "/etc/init.d/kabanmax-zapret2";
const SIGNATURE = "/var/run/kabanmax-zapret2.signature";

function queues() {
    return map(filter(split(fs.readfile("/proc/net/netfilter/nfnetlink_queue") ?? "", "\n"), (line) => trim(line) != ""),
        (line) => int(split(trim(line), /\s+/)[0]));
}

function ready() {
    let expected = model.instances();
    if (!length(expected)) return true;
    let service = exec.output([ "ubus", "call", "service", "list", '{"name":"kabanmax-zapret2"}' ]);
    let instances = service == null ? {} : (json(service)["kabanmax-zapret2"]?.instances ?? {});
    let bindings = {};
    for (let line in split(fs.readfile("/proc/net/netfilter/nfnetlink_queue") ?? "", "\n")) {
        let fields = split(trim(line), /\s+/);
        if (length(fields) >= 2) bindings[int(fields[0])] = int(fields[1]);
    }
    for (let item in expected) {
        let process = instances[item.name];
        if (!process?.running || bindings[item.queue] != int(process.pid)) return false;
    }
    return true;
}

function validate() {
    let instances = model.instances();
    if (!length(instances)) return;
    if (!fs.access(model.BIN, "x")) die("Zapret2 is not installed. Install it from Components");
    for (let name in [ "zapret-lib.lua", "zapret-antidpi.lua", "zapret-auto.lua" ])
        if (!fs.access(model.LUA + name, "r")) die("Zapret2 Lua file is missing: " + name);
    model.persist_slots();
    for (let instance in instances) {
        let checked = exec.combined([ ...instance.argv, "--dry-run" ]);
        if (checked.status != 0) die("Invalid Zapret2 strategy for '" + instance.name + "': " + checked.output);
    }
    // A standalone service would own its own interception policy. KabanMax must be the sole owner.
    let service = exec.output([ "ubus", "call", "service", "list", '{"name":"zapret2"}' ]);
    if (service != null) {
        let state = json(service);
        for (let key, instance in state.zapret2?.instances ?? {})
            if (instance.running) die("Stop the standalone zapret2 service before using KabanMax Zapret2 sections");
    }
    let rules = exec.output([ "nft", "list", "ruleset" ]) ?? "";
    for (let line in split(rules, "\n")) {
        let q = match(line, /queue[ \t]+num[ \t]+([0-9]+)(-([0-9]+))?/);
        if (q != null && int(q[1]) <= 4555 && int(q[3] ?? q[1]) >= 4300 && index(line, "kabanmax-zapret2") < 0)
            die("Another nftables rule uses KabanMax Zapret2 queues 4300-4555");
    }
}

function stop() {
    if (fs.access(INIT, "x") && !exec.ok([ INIT, "stop" ])) die("Could not stop KabanMax Zapret2 instances");
    fs.unlink(SIGNATURE);
}

function start() {
    if (!length(model.sections())) {
        if (fs.stat(SIGNATURE) != null) stop();
        return;
    }
    validate();
    require("zapret2.kernel").load();
    let signature = sprintf("%J", model.instances());
    if (fs.readfile(SIGNATURE) == signature && ready()) return;
    // procd compares named instances and retains an unchanged worker and its flow state.
    if (!exec.ok([ INIT, "reload" ])) die("Could not start KabanMax Zapret2 instances");
    for (let attempt = 0; attempt < 8; attempt++) {
        if (ready()) {
            if (fs.writefile(SIGNATURE, signature) == null) die("Could not record Zapret2 configuration");
            return;
        }
        sleep(1000);
    }
    stop();
    die("Zapret2 did not bind its NFQUEUE queues; inspect logread -e kabanmax-zapret2");
}

return { validate, start, stop, queues, ready };
