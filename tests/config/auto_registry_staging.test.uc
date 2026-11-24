let t=require("t");let fs=require("fs");let tmp=require("stub").tmpdir();
let registry=require("config.auto_registry");let model=require("config.auto_routing");
registry.paths.applied=tmp+"/applied.json";registry.paths.pending=tmp+"/pending.json";registry.paths.flushed=tmp+"/flushed.json";model.paths.suppression=tmp+"/excluded.json";
let now=1000;registry.io.now=()=>now;registry.io.monotonic=()=>now;
let row={id:"route",owner:"auto-routing",source_id:"zap",source:"zap-out",ip:"203.0.113.8",domain:"one.example",domain_known:true,source_ip:"192.0.2.8",inbound:"tproxy-in",port:443,target:"direct-out",status:"applied",persistent_ip:true};
let entry={owner:"auto-routing",scope:registry.key(row),record:row};
t.test("many routing changes stay in RAM and flush only one final snapshot per interval",()=>{
 for(let i=0;i<100;i++)registry.save("applied",[{...entry,record:{...row,id:"route"+i}}]);
 t.eq(fs.readfile(registry.paths.applied),null);t.eq(registry.load().entries[0].record.id,"route99");
 t.eq(registry.flush(),false);now+=86399;t.eq(registry.flush(),false);t.eq(fs.readfile(registry.paths.applied),null);
 now++;t.eq(registry.flush(),true);t.eq(registry.load().entries[0].record.id,"route99");t.ok(fs.readfile(registry.paths.pending)!=null);
});
t.test("staged exclusions take effect before flash persistence and repeated diagnostics do not dirty routing intent",()=>{
 registry.save("excluded",[{owner:"auto-routing",scope:entry.scope,created:now}]);
 t.eq(model.suppression().entries[0].scope,entry.scope);t.eq(fs.readfile(model.paths.suppression),null);
 let before=fs.readfile(registry.paths.applied);
 registry.remember([{...registry.load().entries[0].record,new_error:true,domains:["another.example"]}]);
 t.eq(registry.load().entries[0].record.domains,null);
 now+=86400;t.eq(registry.flush(),true);t.ok(fs.readfile(model.paths.suppression)!=null);t.eq(fs.readfile(registry.paths.applied),before);
});
t.test("wall-clock changes cannot bypass the flash checkpoint interval",()=>{
 registry.io.now=()=>999999999;
 registry.save("applied",[{...entry,record:{...row,id:"changed-intent"}}]);
 t.eq(registry.flush(),false);t.eq(registry.load().entries[0].record.id,"changed-intent");
});
t.done();
