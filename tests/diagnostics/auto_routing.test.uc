let t = require("t");
let detect = require("diagnostics.auto_detect");
let model = require("config.auto_routing");
let fixture = require("fixture");
let generator = require("singbox.generator");
let registry = require("config.auto_registry");
registry.paths.budget = require("stub").tmpdir() + "/auto-routing-write-budget.json";
registry.paths.applied = require("stub").tmpdir() + "/auto-routing-applied.json";
registry.paths.pending = null;
model.paths.suppression = require("stub").tmpdir() + "/auto-routing-initial-suppression.json";

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

t.test("write ACL is checked before mutation; generic logs cannot add section candidates", () => {
    let runtime = require("diagnostics.auto_routing");
    let ubus = require("ubus");
    let calls = [];
    runtime.paths.lock = require("stub").tmpdir() + "/lock";
    model.paths.suppression = require("stub").tmpdir() + "/suppression.json";
    runtime.io.request = (op, payload) => { push(calls, op); return { version: 1, candidates: [], leases: [], decisions: [], history: [], suppressed: [] }; };
    runtime.io.logs = () => die("Generic log scanning must not run");
    runtime.io.connections = () => die("Live connection scanning must not run");
    t.throws(() => runtime.action("delete", "id", ""));
    ubus.__on("session.access", { access: false });
    t.throws(() => runtime.action("delete", "id", "denied"));
    t.eq(calls, []);
    let snapshot = runtime.state();
    t.eq(snapshot.unattributed,[]);
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
    for(let i=0;i<64;i++)push(candidates,{id:sprintf("c%05d",i),source_id:"zap",ip:sprintf("203.0.113.%d",i),domain:i==63 ? "last.test" : "",status:"identity_unknown",failure:{id:"error"+i,source_id:"zap",message:"synthetic connection timeout"}});
    push(candidates,{id:"foreign",source_id:"other",ip:"203.0.113.1",domain:"last.test"});
    let snapshot={registry_version:2,sources:[{id:"zap",outbound:"zap"}],candidates,leases:[],decisions:[],unattributed:[]};
    let page=view.select(snapshot,[],{source_section:"zap",status:"pending",page:2,page_size:25});
    t.eq(length(page.rows),25);t.eq(page.total,64);t.eq(length(page.selection),64);t.eq(page.rows[0].id,"c00025");
    t.eq(view.select(snapshot,[],{source_section:"zap",status:"pending",search:"last.test",page:1,page_size:25}).total,1);
    snapshot.registry_overflow=1;t.eq(view.select(snapshot,[],{source_section:"zap"}).registry_overflow,1);
    snapshot.candidates=slice(snapshot.candidates,0,63);t.eq(view.select(snapshot,[],{source_section:"zap"}).registry_overflow,0);
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
t.test("single opted-in Zapret never adopts WARP stalls or unattributed logs",()=>{
 let view=require("diagnostics.auto_records");
 let failure={id:"error-zap",source_id:"zap",message:"synthetic dial timeout",at:123};
 let own={id:"own",source_id:"zap",source:"zap-out",ip:"203.0.113.8",domain:"member.test",status:"detected",failure};
 let snapshot={registry_version:3,sources:[{id:"zap",outbound:"zap-out"}],candidates:[own,{...own,id:"healthy",ip:"203.0.113.9",failure:null,status:"observing"},{...own,id:"foreign",ip:"203.0.113.10",source_id:"warp",source:"warp-out"},{...own,id:"contradictory",ip:"203.0.113.11",source_id:"warp",source:"zap-out"}],decisions:[],leases:[],unattributed:[{id:"video",ip:"2001:db8::8",domain:"video.test",status:"unattributed",reason:"no_progress_without_trusted_first_match"}]};
 let page=view.select(snapshot,[],{source_section:"zap",status:"pending"});
 t.eq(map(page.rows,(row)=>row.id),["own"]);
 t.eq(page.counts.pending,1);t.eq(length(page.selection),1);
});

t.test("selected alternative is a section output, including its configured fallback, without target list matching",()=>{
 let config={experimental:{clash_api:{secret:"synthetic"}},outbounds:[{tag:"WARP",type:"fallback",outbounds:["WARP/one","WARP/two"]}],endpoints:[{tag:"WARP/one",type:"warp"},{tag:"WARP/two",type:"warp"}],dns:{servers:[]}};
 let source={".name":"zap",action:"zapret2",auto_routing_enabled:"1",auto_routing_use_warp:"1",auto_routing_warp_section:"warp"};
 let target={".name":"warp",name:"WARP",action:"vpn",enabled:"1",destinations:"unrelated.example"};
 let result=model.sources(config,[source,target],(id)=>id=="warp" ? "WARP" : id);
 t.eq(result[0].warp,"WARP");t.eq(result[0].warp_section,"warp");
 t.eq(target.destinations,"unrelated.example");
 config.outbounds[0].outbounds=["WARP/one","not-warp"];
 t.throws(()=>model.sources(config,[source,target],(id)=>id=="warp" ? "WARP" : id));
});

t.test("WARP registration detour is independent of its traffic transport",()=>{
 let config={outbounds:[{tag:"WARP",type:"selector",outbounds:["WARP/one"]},{tag:"infrastructure-direct-out",type:"direct"}],endpoints:[{tag:"WARP/one",type:"warp",profile:{detour:"registration-vpn"}}]};
 t.eq(model.warp_output(config,"WARP"),true,"profile registration does not carry user traffic");
 config.endpoints[0].detour="registration-vpn";
 t.eq(model.warp_output(config,"WARP"),false,"actual VPN transport remains forbidden");
 config.endpoints[0].detour="infrastructure-direct-out";
 t.eq(model.warp_output(config,"WARP"),true,"managed direct bootstrap transport is direct");
 config.outbounds[1].detour="registration-vpn";
 t.eq(model.warp_output(config,"WARP"),false,"direct wrapper cannot hide a VPN detour");
});

t.test("column IP sorting applies to the entire filtered registry in both directions",()=>{
 let records=require("diagnostics.auto_records");
 let snapshot={sources:[{id:"zap",outbound:"META"}],candidates:map(["2001:db8::10","203.0.113.10","2001:db8::2","203.0.113.2"],(ip)=>({id:ip,ip,source:"META",source_id:"zap",status:"detected",failure:{id:ip,source_id:"zap",message:"synthetic timeout"}}))};
 let query={source_section:"zap",status:"pending",sort:"ip",page:1,page_size:25};
 t.eq(map(records.select(snapshot,[],query).rows,(row)=>row.ip),["203.0.113.2","203.0.113.10","2001:db8::2","2001:db8::10"]);
 query.sort="ip_desc";
 t.eq(map(records.select(snapshot,[],query).rows,(row)=>row.ip),["2001:db8::10","2001:db8::2","203.0.113.10","203.0.113.2"]);
});

t.done();
