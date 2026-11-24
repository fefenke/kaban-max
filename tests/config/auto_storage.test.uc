let t=require("t");let fs=require("fs");let tmp=require("stub").tmpdir();
let storage=require("config.auto_storage");let registry=require("config.auto_registry");let model=require("config.auto_routing");
let settings={};storage.io.settings=()=>settings;
registry.paths.applied=tmp+"/storage-applied.json";registry.paths.pending=tmp+"/storage-pending.json";registry.paths.flushed=tmp+"/storage-flushed.json";model.paths.suppression=tmp+"/storage-excluded.json";
let now=1000;registry.io.monotonic=()=>now;
function row(i) {return {id:"r"+i,owner:"auto-routing",source_id:"zap",source:"META",ip:sprintf("203.0.%d.%d",int(i/256),i%256),domain:"",ip_only:true,source_ip:"192.0.2.8",inbound:"tproxy-in",port:443,target:"direct-out",status:"applied",persistent_ip:true,all_ports:true,created:"2026-11-23T00:00:00Z",failure:{id:"e"+i,source_id:"zap",message:"temporary details"}};}
t.test("daily default, configurable twelve hours and invalid settings",()=>{
 t.eq(storage.settings().save_seconds,86400);t.eq(storage.settings().memory_bytes,4194304);
 settings={auto_routing_save_interval:"12h"};t.eq(storage.settings().save_seconds,43200);
 settings={auto_routing_memory_mib:"0"};t.throws(()=>storage.settings());settings={};
 settings={auto_routing_cleanup_interval:"1s"};t.eq(storage.settings().cleanup_seconds,3600);settings={};
});
t.test("hundreds of compact routes survive staging and only essentials reach flash",()=>{
 let rows=[];for(let i=0;i<300;i++){let r=row(i);push(rows,{owner:"auto-routing",scope:registry.key(r),record:r});}
 registry.save("applied",rows);t.eq(length(registry.load().entries),300);
 t.eq(registry.flush(),false);now+=86399;t.eq(registry.flush(),false);now++;t.eq(registry.flush(),true);
 let saved=json(fs.readfile(registry.paths.applied));t.eq(length(saved.entries),300);
 t.eq(saved.entries[0].record.failure.message,null);t.eq(saved.entries[0].record.target,"direct-out");
 let before=fs.readfile(registry.paths.applied);now+=86400;t.eq(registry.flush(),false);t.eq(fs.readfile(registry.paths.applied),before);
});
t.test("diagnostic updates neither dirty intent nor rewrite flash",()=>{
 let r=row(0);registry.remember([{...r,new_error:true,domains:["label.example"],failure:{...r.failure,message:"changed details"}}]);
 let before=fs.readfile(registry.paths.applied);now+=86400;t.eq(registry.flush(),false);t.eq(fs.readfile(registry.paths.applied),before);
});
t.test("pressure checkpoint only flushes dirty data and is rate limited",()=>{
 registry.save("excluded",[{owner:"auto-routing",scope:registry.key(row(999)),created:1}]);
 t.eq(registry.flush(true),true);let before=fs.readfile(model.paths.suppression);
 t.eq(registry.flush(true),false);t.eq(fs.readfile(model.paths.suppression),before);
 registry.save("excluded",[]);t.eq(registry.flush(true),false);now+=900;t.eq(registry.flush(true),true);
});
t.test("actions can remove a saved approval beyond the first hundred rows",()=>{
 let actions=require("diagnostics.auto_registry");let calls=[];
 actions.io.state=()=>({registry_version:3,sources:[{id:"zap",outbound:"META"}],leases:[],candidates:[],decisions:[]});
 actions.io.request=(op)=>{push(calls,op);return {};};
 let wanted=registry.key(row(299));
 let result=actions.run(sprintf("%J",{source_section:"zap",status:"applied",sort:"oldest",action:"forget",ids:["saved:"+wanted]}));
 t.eq(result.done,1);t.eq(length(registry.load().entries),299);
 t.eq(length(filter(registry.load().entries,(e)=>e.scope==wanted)),0);
});
t.test("memory admission rejects oversized growth and preserves previously saved intent",()=>{
 settings={auto_routing_memory_mib:"1"};let before=fs.readfile(registry.paths.pending);
 let rows=[];for(let i=0;i<1500;i++){let r=row(i);push(rows,{owner:"auto-routing",scope:registry.key(r),record:r});}
 t.throws(()=>registry.save("applied",rows));t.eq(fs.readfile(registry.paths.pending),before);settings={};
});
t.test("a corrupt flash file is never overwritten by a pending snapshot",()=>{
 fs.writefile(registry.paths.applied,"broken");now+=86400;t.throws(()=>registry.flush());t.eq(fs.readfile(registry.paths.applied),"broken");
});
t.done();
