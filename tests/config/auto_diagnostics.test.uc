let t=require("t");let fs=require("fs");let tmp=require("stub").tmpdir();
let diag=require("config.auto_diagnostics");
diag.paths.state=tmp+"/diag.json";diag.paths.error=tmp+"/diag.error";
let row={id:"grant",owner:"auto-routing",source_id:"source",source:"META",ip:"203.0.113.8",domain:"",ip_only:true,target:"WARP",status:"applied",persistent_ip:true,all_devices:true,all_ports:true};
let original={id:"failure",source_id:"source",message:"splice read: connection timed out",at:"2026-11-24T12:00:00Z"};
t.test("original failure and labels survive a compact route snapshot and reread",()=>{
 diag.remember([{...row,failure:original,domains:["observed.example"]}]);
 let restored=diag.enrich({...row,failure:{source_id:"source"}});
 t.eq(restored.original_failure,original);t.eq(restored.domains,["observed.example"]);
 t.eq(restored.domain,"");t.eq(restored.ip_only,true);
});
t.test("later target error does not overwrite the original source failure",()=>{
 let latest={...original,id:"new",message:"new alternative timeout"};
 diag.remember([{...row,original_failure:original,failure:latest,new_error:true}]);
 let restored=diag.enrich(row);
 t.eq(restored.original_failure,original);t.eq(restored.failure,latest);t.eq(restored.new_error,true);
});
t.test("reapplying the same IP carries observed labels without changing route identity",()=>{
 let next={...row,id:"replacement",failure:{...original,id:"next"}};
 diag.remember([next]);let restored=diag.enrich(next);
 t.eq(restored.domains,["observed.example"]);t.eq(restored.original_failure.id,"next");
 t.eq(diag.enrich({...next,source_id:"foreign"}).original_failure,null);
 t.eq(diag.enrich({...row,id:"replacement",target:"direct-out"}).original_failure,null);
});
t.test("memory pressure keeps old diagnostics and reports failure without losing routes",()=>{
 let before=fs.readfile(diag.paths.state);let limit=diag.io.limit;diag.io.limit=()=>1;
 t.eq(diag.remember([{...row,id:"overflow",failure:original}]),false);
 t.eq(fs.readfile(diag.paths.state),before);t.ok(diag.error()!="");diag.io.limit=limit;
});
t.test("one view snapshot reads diagnostics once instead of once per row",()=>{
 let original_read=fs.readfile;let reads=0;
 fs.readfile=(path)=>{if(path==diag.paths.state)reads++;return original_read(path);};
 let enrich=diag.enricher();for(let i=0;i<1000;i++)enrich({...row,id:"replacement"});
 fs.readfile=original_read;t.eq(reads,1);
});
t.test("bypass attribution survives restore and a later target error replaces it",()=>{
 diag.remember([{...row,failure:original,new_error:true,reason:"applied_route_bypassed"}]);
 t.eq(diag.enrich(row).reason,"applied_route_bypassed");
 let target={...original,id:"target",message:"target timeout"};
 diag.remember([{...row,failure:target,new_error:true,reason:"applied_target_failed"}]);
 t.eq(diag.enrich(row).reason,"applied_target_failed");
 t.eq(diag.enrich(row).failure.id,"target");
});

t.done();
