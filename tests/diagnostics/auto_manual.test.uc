let t=require("t");let view=require("diagnostics.auto_records");let batch=require("diagnostics.auto_registry");let store=require("config.auto_registry");let model=require("config.auto_routing");let fs=require("fs");let tmp=require("stub").tmpdir();
store.paths.applied=tmp+"/manual-applied.json";store.paths.budget=tmp+"/manual-budget.json";model.paths.suppression=tmp+"/manual-excluded.json";
store.paths.pending=null;
let row={id:"failed-flow",source_id:"zap",source:"zap-out",ip:"203.0.113.8",domain:"",observed_domain:"observed.example",source_ip:"192.0.2.8",inbound:"tproxy-in",port:443,ip_only:true,status:"inconclusive",failure:{id:"failure",source_id:"zap",message:"synthetic timeout"}};
let snapshot={registry_version:3,manual_apply_supported:true,sources:[{id:"zap",outbound:"zap-out",direct:true,warp:"warp-out",warp_section:"warp"}],warp_sections:[{id:"warp",name:"Configured WARP"}],candidates:[row],decisions:[],leases:[]};
let calls=[];let mismatch=false;
batch.io.state=()=>snapshot;
batch.io.request=(op,payload)=>{push(calls,{op,payload});return {...row,owner:"auto-routing",status:"applied",target:mismatch ? "foreign-out" : payload.target};};
function run(targets) {return batch.run(sprintf("%J",{action:"apply",source_section:"zap",status:"pending",ids:[row.id],targets}));}
t.test("manual page advertises configured targets and searchable observed domain",()=>{
 let page=view.select(snapshot,[],{source_section:"zap",status:"pending",search:"observed.example"});
 t.eq(page.total,1);t.eq(page.rows[0].domain,"");t.eq(page.rows[0].observed_domain,"observed.example");t.ok(page.manual_apply_supported);t.ok(page.selection[0].eligible);
 t.eq(page.available_targets,[{tag:"direct-out",name:"Direct"},{tag:"warp-out",name:"Configured WARP"}]);
 t.eq(view.select({...snapshot,manual_apply_supported:false},[],{source_section:"zap"}).selection[0].eligible,false);
});
t.test("explicit manual choice applies inconclusive logged row and persists exact scope",()=>{
 calls=[];let result=run({"failed-flow":"warp-out"});t.eq(result.done,1);t.eq(calls[0],{op:"manual_apply",payload:{source_id:"zap",id:row.id,target:"warp-out"}});t.eq(store.load().entries[0].record.target,"warp-out");
});
t.test("unknown targets and unsupported cores never grant; legacy apply stays verified",()=>{
 calls=[];t.eq(run({"failed-flow":"foreign-out"}).skipped,1);t.eq(run(null).skipped,1);t.eq(calls,[]);
 snapshot.manual_apply_supported=false;t.throws(()=>run({"failed-flow":"direct-out"}));snapshot.manual_apply_supported=true;t.eq(calls,[]);
});
t.test("mismatched grant is withdrawn and never persisted",()=>{
 fs.unlink(store.paths.applied);
 calls=[];mismatch=true;t.eq(run({"failed-flow":"direct-out"}).failed,1);mismatch=false;t.eq(map(calls,(v)=>v.op),["manual_apply","registry_withdraw"]);t.eq(store.load().entries,[]);
});
t.test("durable storage failure withdraws manual grant",()=>{
 calls=[];fs.writefile(store.paths.budget,'{"start":0,"count":0}');let old=store.paths.applied;store.paths.applied="/proc/kabanmax-manual-test-denied.json";
 t.throws(()=>run({"failed-flow":"direct-out"}));store.paths.applied=old;t.eq(map(calls,(v)=>v.op),["manual_apply","registry_withdraw"]);
});
t.test("invalid scope or contradictory source cannot be manually applied",()=>{
 calls=[];let original=snapshot.candidates;snapshot.candidates=[{...row,inbound:"invalid"}];t.eq(run({"failed-flow":"direct-out"}).skipped,1);snapshot.candidates=[{...row,source_id:"foreign"}];t.eq(run({"failed-flow":"direct-out"}).skipped,1);snapshot.candidates=original;t.eq(calls,[]);
});
t.test("one IP keeps all domains and uses the latest live event for single apply",()=>{
 let first={...row,id:"old-decision",domain:"first.example",observed_domain:"first.example",created:"2026-11-17T00:00:00Z"};
 let second={...row,id:"latest-event",domain:"second.example",observed_domain:"second.example",created:"2026-11-17T00:01:00Z"};
 let page=view.select({...snapshot,decisions:[first],candidates:[second]},[],{source_section:"zap",status:"pending"});
 t.eq(page.total,1);t.eq(page.rows[0].id,"latest-event");t.eq(sort(page.rows[0].domains),["first.example","second.example"]);
});
t.test("single apply of a proposed live event tolerates newer domain/error on the same IP scope",()=>{
 fs.unlink(store.paths.applied);fs.unlink(store.paths.budget);
 let old=snapshot.candidates;let old_request=batch.io.request;
 let current={...row,id:"stable-ip",status:"proposed",failure:{...row.failure,id:"stable-ip"}};snapshot.candidates=[current];
 batch.io.request=(op,payload)=>({...current,domain:"new.example",domain_known:true,ip_only:false,persistent_ip:true,owner:"auto-routing",status:"applied",target:payload.target,failure:{...current.failure,message:"newer timeout"}});
 let result=batch.run(sprintf("%J",{action:"apply",source_section:"zap",status:"pending",ids:[current.id],targets:{"stable-ip":"warp-out"}}));
 t.eq(result.done,1);t.eq(store.load().entries[0].record.domain,"new.example");
 snapshot.candidates=old;batch.io.request=old_request;
});
t.test("inconclusive historical decision is not applied or dismissed twice with its live IP record",()=>{
 let old=snapshot.candidates;let old_decisions=snapshot.decisions;let old_request=batch.io.request;
 let current={...row,id:"stable-ip",domain:"current.example",domain_known:true,ip_only:false,failure:{...row.failure,id:"stable-ip"}};
 snapshot.candidates=[current];snapshot.decisions=[{...current,id:"old-decision",domain:"old.example",status:"inconclusive"}];
 for(let action in ["apply","dismiss"]) {
  fs.unlink(store.paths.applied);
  let ids=[];
  batch.io.request=(op,payload)=>{push(ids,payload.id);if(payload.id!="stable-ip")die("source_or_record_not_found");return {...current,persistent_ip:true,owner:"auto-routing",status:"applied",target:payload.target};};
  let result=batch.run(sprintf("%J",{action,source_section:"zap",status:"pending",ids:["stable-ip"],...(action=="apply" ? {targets:{"stable-ip":"warp-out"}} : {})}));
  t.eq(result.failed,0);t.eq(result.done,1);t.eq(ids,["stable-ip"]);
 }
 snapshot.candidates=old;snapshot.decisions=old_decisions;batch.io.request=old_request;
});

t.test("manual web page keeps a verified alternative after another original failure of the same IP",()=>{
 let current={...row,id:"stable-ip",domain:"current.example",updated:"2026-11-17T00:02:00Z",failure:{...row.failure,id:"stable-ip",at:"2026-11-17T00:02:00Z",message:"new original timeout"},status:"detected"};
 let decision={...current,id:"verified-decision",domain:"previous.example",created:"2026-11-17T00:01:00Z",status:"proposed",target:"warp-out",reason:"verified_alternative",failure:{...current.failure,at:"2026-11-17T00:00:00Z",message:"old original timeout"},attempts:[{outbound:"warp-out",status:"verified"}]};
 let source={...snapshot.sources[0],mode:"web",auto_apply:false};
 let page=view.select({...snapshot,sources:[source],candidates:[current],decisions:[decision]},[],{source_section:"zap",status:"pending"});
 t.eq(page.rows[0].id,"stable-ip");t.eq(page.rows[0].status,"proposed");t.eq(page.rows[0].target,"warp-out");t.eq(page.rows[0].failure.message,"new original timeout");t.eq(length(page.rows[0].attempts),1);
 page=view.select({...snapshot,sources:[source],candidates:[{...current,source_ip:"192.0.2.99"}],decisions:[decision]},[],{source_section:"zap",status:"pending"});
 t.eq(page.rows[0].status,"detected","another device must not inherit the result");
});

t.done();
