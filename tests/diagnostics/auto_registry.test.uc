let t=require("t");let fs=require("fs");let stub=require("stub");let model=require("config.auto_routing");
let registry=require("config.auto_registry");
registry.paths.applied=stub.tmpdir()+"/applied.json";registry.paths.budget=stub.tmpdir()+"/write-budget.json";model.paths.suppression=stub.tmpdir()+"/excluded.json";
let now=1000;registry.io.now=()=>now;
function record(i) {return {id:"l"+i,owner:"auto-routing",source_id:"zap",source:"zap",ip:"203.0.113."+i,domain:"one.test",domain_known:true,source_ip:"192.0.2.8",inbound:"tproxy-in",port:443,target:"direct-out",created:"2026-11-16T00:00:00Z",expires:"2026-11-16T00:01:00Z",status:"applied"};}
t.test("saved leases reload as intents, never as active runtime state; limit preserves existing entries",()=>{
 let rows=[];for(let i=1;i<=64;i++)push(rows,{owner:"auto-routing",scope:registry.key(record(i)),record:record(i)});
 registry.save("applied",rows);t.eq(length(registry.load().entries),64);
 let before=fs.readfile(registry.paths.applied);push(rows,{owner:"auto-routing",scope:registry.key(record(65)),record:record(65)});
 t.throws(()=>registry.save("applied",rows));t.eq(fs.readfile(registry.paths.applied),before);
 t.eq(registry.load().entries[0].record.id,"l1");
});
t.test("atomic persistent exclusions and write budget reject growth without erasing data",()=>{
 let row={owner:"auto-routing",scope:registry.key(record(1)),created:now};registry.save("excluded",[row]);
 t.eq(model.suppression().entries[0].scope,row.scope);
 for(let i=0;i<10;i++){row={...row,created:++now};registry.save("excluded",[row]);}
 let before=fs.readfile(model.paths.suppression);t.throws(()=>registry.save("excluded",[{...row,created:++now}]));t.eq(fs.readfile(model.paths.suppression),before);
 now+=61;registry.save("excluded",[]);t.eq(model.suppression().entries,[]);
 fs.writefile(registry.paths.applied,"corrupt");t.throws(()=>registry.load());t.throws(()=>registry.save("applied",[]));t.eq(fs.readfile(registry.paths.applied),"corrupt");
});
t.test("bulk is source-scoped, eligible-only and idempotent; exact exclusion removal preserves neighbours",()=>{
 fs.unlink(registry.paths.applied);fs.unlink(registry.paths.budget);fs.unlink(model.paths.suppression);
 let actions=require("diagnostics.auto_registry");let first={...record(1),status:"proposed",apply_allowed:true};let second={...record(2),status:"inconclusive",apply_allowed:false};
 let snapshot={registry_version:2,version:1,sources:[{id:"zap",outbound:"zap"}],candidates:[],decisions:[first,second,{...first,id:"foreign",source_id:"other",source:"other"}],leases:[],unattributed:[]};
 let calls=[];actions.io.state=()=>snapshot;
 actions.io.request=(op,payload)=>{push(calls,{op,...payload});if(op=="apply"){snapshot.decisions=filter(snapshot.decisions,(r)=>r.id!=payload.id);let lease={...first,status:"applied"};snapshot.leases=[lease];return lease;}return {};};
 function batch(action,status,ids){return actions.run(sprintf("%J",{source_section:"zap",status,search:"",sort:"newest",action,ids}));}
 let result=batch("apply","pending",["l1","l2","foreign","l1"]);t.eq(result.done,1);t.eq(result.skipped,3);t.eq(length(calls),1);t.eq(length(registry.load().entries),1);
 t.eq(batch("apply","pending",["l1"]).skipped,1);
 t.eq(batch("exclude","applied",["l1"]).done,1);t.eq(length(registry.load().entries),0);t.eq(length(model.suppression().entries),1);
 let other=registry.key({...record(3),source_ip:"192.0.2.9",port:8443});registry.save("excluded",[...model.suppression().entries,{owner:"auto-routing",scope:other,created:now}]);
 t.eq(batch("remove","excluded",[registry.key(record(1))]).done,1);t.eq(model.suppression().entries[0].scope,other);
 t.ok(length(filter(calls,(c)=>c.op=="registry_reset" && c.scope==registry.key(record(1))))==1);
});
t.test("failed durable approval withdraws the runtime grant instead of leaving an unrecorded active route",()=>{
 fs.unlink(registry.paths.applied);fs.writefile(registry.paths.budget,sprintf("%J",{start:now,count:12}));
 let actions=require("diagnostics.auto_registry");let row={...record(10),status:"proposed",apply_allowed:true};let active=[];
 actions.io.state=()=>({registry_version:2,version:1,sources:[{id:"zap",outbound:"zap"}],decisions:[row],candidates:[],leases:active,unattributed:[]});
 actions.io.request=(op,payload)=>{if(op=="apply"){let lease={...row,status:"applied"};active=[lease];return lease;}if(op=="registry_withdraw"){t.eq(payload.source_id,"zap");t.eq(payload.id,"l10");active=[];return {};}die("Unexpected operation");};
 t.throws(()=>actions.run(sprintf("%J",{source_section:"zap",status:"pending",action:"apply",ids:["l10"]})));
 t.eq(active,[]);t.eq(registry.load().entries,[]);
});
t.done();
