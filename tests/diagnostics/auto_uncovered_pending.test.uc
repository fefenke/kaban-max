let t=require("t");
let view=require("diagnostics.auto_records");
let base={source_id:"zap",source:"META",ip:"203.0.113.42",domain:"one.test",source_ip:"192.0.2.1",inbound:"tproxy-in",port:443,domain_known:true};
let lease={...base,id:"applied",status:"applied",target:"WARP",all_ports:true,persistent_ip:true};
function event(device,id){return {...base,id,source_ip:device,status:"proposed",created:"2026-11-24T10:00:00Z",failure:{id,source_id:"zap",message:"synthetic timeout"}};}
function snapshot(events){return {registry_version:3,manual_apply_supported:true,sources:[{id:"zap",outbound:"META",mode:"web",warp:"WARP"}],candidates:events,decisions:[],leases:[lease]};}
let query={source_section:"zap",status:"pending"};
t.test("an applied IP on another device must not hide a pending failure",()=>{
 let s=snapshot([event("192.0.2.2","new-device")]);
 let pending=view.select(s,[],query);
 t.eq(pending.total,1);t.eq(pending.rows[0].source_ip,"192.0.2.2");t.eq(pending.selection[0].eligible,true);
 let applied=view.select(s,[],{...query,status:"applied"});
 t.eq(applied.total,1);t.eq(applied.rows[0].uncovered_connections,1);
});
t.test("already covered flows stay hidden and are not included in another device apply",()=>{
 let s=snapshot([event("192.0.2.1","covered"),event("192.0.2.2","uncovered")]);
 let p=view.select(s,[],query);t.eq(p.total,1);
 t.eq(map(p.rows[0].members,(r)=>r.source_ip),["192.0.2.2"]);
 t.eq(view.select(snapshot([event("192.0.2.1","covered")]),[],query).total,0);
});
t.test("a section-wide grant covers every device without the uncovered status",()=>{
 let s=snapshot([event("192.0.2.2","other-device")]);
 s.leases=[{...lease,all_devices:true}];
 t.eq(view.select(s,[],query).total,0);
 let applied=view.select(s,[],{...query,status:"applied"});
 t.eq(applied.rows[0].uncovered_connections,0);
 t.eq(applied.rows[0].all_devices,true);
});
t.done();
