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
    let other='["other","203.0.113.7","other.test","192.168.1.9","tproxy-in",8443]';
    runtime.persist("delete", "other", [other]);
    runtime.persist("reset", "zap", []);
    t.eq(length(model.suppression().entries),1);
    t.eq(model.suppression().entries[0].scope,other,"reset preserves other source/domain/device/port scopes");
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

t.test("bounded registry pages cover all 64 records and exclude foreign sources", () => {
    let view=require("diagnostics.auto_records");let candidates=[];
    for(let i=0;i<64;i++)push(candidates,{id:sprintf("c%05d",i),source_id:"zap",ip:sprintf("203.0.113.%d",i),domain:i==63 ? "last.test" : "",status:"identity_unknown"});
    push(candidates,{id:"foreign",source_id:"other",ip:"203.0.113.1",domain:"last.test"});
    let snapshot={registry_version:2,sources:[{id:"zap",outbound:"zap"}],candidates,leases:[],decisions:[],unattributed:[]};
    let page=view.select(snapshot,[],{source_section:"zap",status:"pending",page:2,page_size:25});
    t.eq(length(page.rows),25);t.eq(page.total,64);t.eq(length(page.selection),64);t.eq(page.rows[0].id,"c00025");
    t.eq(view.select(snapshot,[],{source_section:"zap",status:"pending",search:"last.test",page:1,page_size:25}).total,1);
    t.throws(()=>view.select(snapshot,[],{source_section:"zap",page_size:5000}));
});
t.test("WARP UI toggle preserves its stored profile and leaves baseline policy intact", () => {
    let config={experimental:{clash_api:{secret:"synthetic"}},outbounds:[],endpoints:[],dns:{servers:[]}};
    let source={".name":"zap",action:"zapret2",auto_routing_enabled:"1",auto_routing_warp:"saved-unavailable-profile",auto_routing_use_warp:"0"};
    model.paths.suppression=require("stub").tmpdir()+"/toggle-suppression.json";
    let result=model.sources(config,[source],(id)=>id);
    t.eq(result[0].warp,"");t.eq(result[0].probe_zapret,true);
    t.eq(source.auto_routing_warp,"saved-unavailable-profile");
});
t.done();
