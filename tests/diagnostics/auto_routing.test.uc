let t = require("t");
let detect = require("diagnostics.auto_detect");
let model = require("config.auto_routing");
let fixture = require("fixture");
let generator = require("singbox.generator");

t.test("IP-first logs retain IPv4 IPv6 and unknown attribution without hostname", () => {
    for (let pair in [["dial tcp 203.0.113.7:443: timeout", "203.0.113.7"], ["dial tcp [2001:db8::7]:443: connection refused", "2001:db8::7"]]) {
        let event = detect.log_candidate(pair[0], 123);
        t.eq(event.ip, pair[1]); t.eq(event.domain, ""); t.eq(event.status, "unattributed");
        t.eq(event.port, 443); t.eq(event.network, "tcp");
    }
    t.eq(detect.log_candidate("not a connection error", 123), null);
});

t.test("no-progress does not require host and plain Direct is not Zapret", () => {
    let conn = { id: "c1", metadata: { destinationIP: "203.0.113.7", destinationPort: "443", sourceIP: "192.168.1.8", network: "tcp", host: "" }, upload: 10, download: 0, chains: ["direct-out"] };
    let first = detect.stalled({}, [conn], 100);
    let second = detect.stalled(first.tracked, [conn], 120);
    t.eq(second.events[0].ip, "203.0.113.7");t.eq(second.events[0].domain, "");t.eq(second.events[0].status, "unattributed");
    conn.metadata.host = "other.test";
    let changed = detect.stalled(second.tracked, [conn], 140);
    t.eq(length(changed.events), 0, "metadata changes start a new correlation interval");
});

t.test("opt-in contract is isolated from manual destinations and default JSON remains r10 compatible", () => {
    fixture.seed({settings:{},section:[{".name":"zap",enabled:"1",action:"zapret2",destinations:"one.test"}]});
    t.eq(generator.build({service_address:"192.168.1.1"}).route.kabanmax_auto,null);
    fixture.seed({settings:{yacd_secret_key:"synthetic"},section:[{".name":"zap",enabled:"1",action:"zapret2",destinations:"one.test",auto_routing_enabled:"1",auto_routing_direct:"1",auto_routing_contract:'{"domain":"one.test","path":"/health","port":443,"status":200,"prefix":"ok:","failure_status":451,"failure_prefix":"fail:"}'}]});
    let config=generator.build({service_address:"192.168.1.1"});
    t.eq(config.route.kabanmax_auto[0].id,"zap");t.eq(config.route.kabanmax_auto[0].outbound,"zap");t.eq(config.route.kabanmax_auto[0].direct,true);
    t.eq(config.route.kabanmax_auto[0].domain,"one.test");
    t.eq(require("core.uci").get("kabanmax.zap.destinations"),"one.test");
});

t.test("malformed contract and enabled non-Zapret sources are rejected", () => {
    t.throws(() => model.contract({auto_routing_contract:'{"domain":"one.test","path":"//bad.test","port":443,"status":200,"prefix":"ok:"}'}));
    t.throws(() => model.contract({auto_routing_contract:'{}'}));
});

t.test("persistent suppression is independent of manual UCI and corrupt state fails closed", () => {
    let runtime = require("diagnostics.auto_routing");
    let fs = require("fs");
    model.paths.suppression = require("stub").tmpdir() + "/suppression.json";
    let key='["zap","203.0.113.7","one.test","192.168.1.8","tproxy-in",443]';
    runtime.persist("delete", "entry", [key]);
    t.eq(model.suppression().entries[0].scope,key);
    runtime.persist("reset", "zap", []);
    t.eq(model.suppression().entries,[]);
    fs.writefile(model.paths.suppression,"not-json");
    t.throws(() => model.suppression());
    t.throws(() => runtime.persist("delete","entry",[key]));
    t.eq(fs.readfile(model.paths.suppression),"not-json");
    fs.writefile(model.paths.suppression,'{"version":1,"entries":[{"owner":"wrong-owner","scope":"[]"}]}');
    t.throws(() => model.suppression());
});

t.test("write ACL is checked before backend mutation; IP-only candidates remain visible", () => {
    let runtime = require("diagnostics.auto_routing");
    let ubus = require("ubus");
    let calls = [];
    runtime.paths.lock = require("stub").tmpdir() + "/lock";
    model.paths.suppression = require("stub").tmpdir() + "/suppression.json";
    runtime.io.request = (op, payload) => { push(calls, op); return { version: 1, candidates: [], leases: [], decisions: [], history: [], suppressed: [] }; };
    runtime.io.logs = () => "dial tcp 203.0.113.7:443: timeout";
    runtime.io.connections = () => [];
    t.throws(() => runtime.action("delete", "id", ""));
    ubus.__on("session.access", { access: false });
    t.throws(() => runtime.action("delete", "id", "denied"));
    t.eq(calls, []);
    let snapshot = runtime.state();
    t.eq(snapshot.unattributed[0].ip,"203.0.113.7");
    t.eq(snapshot.unattributed[0].domain,"");
    ubus.__on("session.access", { access: true });
    t.ok(runtime.action("delete", "id", "allowed").success);
});
t.test("ordinary web mode needs no nonce endpoint and strict contracts remain explicit", () => {
    let ordinary=model.contract({});
    t.eq(ordinary.mode,"web");t.eq(ordinary.domain,"");t.eq(ordinary.path,"/");t.eq(ordinary.port,443);
    let strict=model.contract({auto_routing_contract:'{"domain":"one.test","path":"/health","port":443,"status":200,"prefix":"ok:"}'});
    t.eq(strict.mode,"strict");t.eq(strict.prefix,"ok:");
    t.throws(()=>model.contract({auto_routing_contract:'{"mode":"web","path":"/","port":443,"status":200,"failure_status":451}'}));
});

t.done();
