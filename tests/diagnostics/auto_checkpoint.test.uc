let t=require("t");let fs=require("fs");let tmp=require("stub").tmpdir();
let auto=require("diagnostics.auto_routing");
let store=require("config.auto_registry");
store.paths.applied=tmp+"/checkpoint-applied.json";
store.paths.budget=tmp+"/checkpoint-budget.json";
store.paths.pending=null;
auto.paths.pending=tmp+"/private-checkpoint.json";
auto.paths.lock=tmp+"/checkpoint.lock";

t.test("real request decoder accepts private arrays and rejects wrong response shapes",()=>{
 let api=require("singbox.clash_api");let exchange=api.exchange;let controller=api.controller;
 let response=[{id:"kept",original_metadata:{Protocol:"tls"}}];
 api.controller=()=>({});api.exchange=()=>({status:200,body:sprintf("%J",response)});
  t.eq(auto.io.request("checkpoint",{}),response);
  t.throws(()=>auto.io.request("state",{}));
  response={candidates:[]};t.throws(()=>auto.io.request("checkpoint",{}));
 api.exchange=exchange;api.controller=controller;
});

t.test("temporary checkpoint failure preserves original private metadata",()=>{
 let before='[{"id":"kept","original_metadata":{"Protocol":"tls"}}]';fs.writefile(auto.paths.pending,before);
 auto.io.request=(op)=>{if(op=="checkpoint")die("API timeout");return {registry_version:3,candidates:[{id:"kept"}]};};
 t.throws(()=>auto.checkpoint([]));
 t.eq(fs.readfile(auto.paths.pending),before);
});
t.test("only a genuinely old core uses public checkpoint compatibility",()=>{
 auto.io.request=(op)=>{if(op=="checkpoint")die("unknown operation");return {registry_version:3,candidates:[{id:"legacy"}]};};
 t.ok(auto.checkpoint([]));t.eq(json(fs.readfile(auto.paths.pending)),[{id:"legacy"}]);
});
t.test("private checkpoint timeout does not revoke a newly remembered route",()=>{
 let calls=[];let remember=store.remember;
 store.remember=()=>true;
 auto.io.request=(op)=>{push(calls,op);if(op=="state")return {registry_version:3,leases:[{id:"new",source_id:"zap",target:"direct-out"}]};die("API timeout");};
 t.eq(auto.capture(),false);
 t.eq(calls,["state","checkpoint"]);
 store.remember=remember;
});
t.done();
