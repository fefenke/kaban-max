let common=require("core.common");let model=require("config.auto_routing");let store=require("config.auto_registry");
let io={state:()=>require("diagnostics.auto_routing").state(),request:(op,payload)=>require("diagnostics.auto_routing").io.request(op,payload)};
function eligible(row) {return row.status=="proposed" && row.apply_allowed==true && ((row.domain_known==true && row.domain!="") || row.ip_only==true);}
function run(payload) {
 let request=common.parse_json(payload);
 if(type(request)!="object" || index(["apply","exclude","remove","recheck","forget","dismiss"],request.action)<0 || type(request.ids)!="array" || length(request.ids)<1 || length(request.ids)>8)die("Invalid registry batch (maximum 8 IDs)");
 if(request.action=="recheck" && length(request.ids)!=1)die("Verification accepts one flow per request");
 if((request.action=="remove" && request.status!="excluded") || (index(["apply","dismiss"],request.action)>=0 && request.status!="pending"))die("Action does not match registry tab");
 let manual=request.action=="apply" && request.targets!=null;
 if(manual && type(request.targets)!="object")die("Invalid manual targets");
 let runtime={io};let snapshot=io.state();
 if(manual && (snapshot.registry_version!=3 || snapshot.manual_apply_supported!=true))die("Manual routing requires core support");
 if(snapshot.registry_version!=2 && snapshot.registry_version!=3)die("Registry actions require the r13 core API");
 if(request.action=="dismiss" && snapshot.registry_version!=3)die("Registry actions require the r13 core API");
 let query={source_section:request.source_section,status:request.status,search:request.search ?? "",sort:request.sort ?? "newest",page:1,page_size:100};
 let excluded=model.suppression().entries;let applied=store.load().entries;
 let page=require("diagnostics.auto_records").select(snapshot,excluded,query,applied,request.ids);
 let available={};for(let row in page.rows)if(row.id!=null)available[row.id]=row;
 let source=filter(snapshot.sources ?? [],(s)=>s.id==request.source_section)[0];
 if(source==null)die("Active original Zapret2 source is unavailable");
 let picked=[];let results=[];let seen={};
 for(let id in request.ids) {
  if(type(id)!="string" || length(id)>1200)die("Invalid registry ID");
  let group=available[id];
  if(seen[id] || group==null) {push(results,{id,status:"skipped",reason:"stale_or_ineligible"});continue;}
  seen[id]=true;
  let scopes={};
  // A visible IP may contain several devices or historical domain scopes.
  // Execute against each core-owned member, never invent a wider permission.
  for(let row in group.members ?? [group]) {
  if(((request.action=="apply" && manual) || request.action=="dismiss") && row.id!=row.failure?.id && length(filter(snapshot.candidates ?? [],(e)=>e.id==row.failure?.id))>0)continue;
  if(request.action=="apply" && !manual && !eligible(row)){push(results,{id,status:"skipped",reason:"stale_or_ineligible"});continue;}
  if(row.source_id!=request.source_section && row.source!=source.outbound){push(results,{id,status:"skipped",reason:"source_not_attested"});continue;}
  let key=store.key({...row,source_id:request.source_section,...(request.action=="exclude" ? {domain:""} : {})});
  if(scopes[key])continue;scopes[key]=true;
  if(request.action!="dismiss" && !model.valid_scope(key)) {push(results,{id,status:"skipped",reason:"unattested_scope"});continue;}
  let target=manual ? request.targets[id] : null;
  if(manual && (type(target)!="string" || target=="" || !((source.direct==true && target=="direct-out") || (type(source.warp)=="string" && source.warp!="" && target==source.warp)))) {push(results,{id,status:"skipped",reason:"target_not_allowed"});continue;}
  push(picked,{row,scope:key,target});
  }
 }
 // Capacity and storage checks precede any permission-granting core mutation.
 let next_applied=[...applied];let next_excluded=[...excluded];
 if(request.action=="exclude") {
  for(let item in picked)if(length(filter(next_excluded,(e)=>e.scope==item.scope))==0)push(next_excluded,{owner:"auto-routing",scope:item.scope,created:common.now_seconds(),domains:uniq(filter([...(item.row.domains ?? []),item.row.domain ?? "",item.row.observed_domain ?? ""],(name)=>name!=""))});
  store.save("excluded",next_excluded); // Record deny intent before mutation; flash is batched.
 }
 if(request.action=="apply") {
  let projected=[...applied];
  for(let item in picked) {
   projected=filter(projected,(entry)=>entry.scope!=item.scope);
   push(projected,{owner:"auto-routing",scope:item.scope,record:{...item.row,status:"applied",owner:"auto-routing",target:item.target ?? item.row.target}});
  }
  store.check_capacity("applied",projected,length(picked)*512);
 }
 let grants=[];
 for(let item in picked) {
  let row=item.row;let scope=item.scope;
  try {
   if(request.action=="exclude") {
    try {runtime.io.request("registry_suppress",{source_id:request.source_section,scope});}
    catch(e) {runtime.io.request("disable",{id:request.source_section});die("Scope exclusion failed; source stopped fail-closed: "+e.message);}
    next_applied=filter(next_applied,(entry)=>entry.scope!=scope && !(entry.record.source_id==request.source_section && entry.record.ip==row.ip && entry.record.source_ip==row.source_ip && entry.record.inbound==row.inbound && entry.record.port==row.port));
   }
   else if(request.action=="remove") {
    runtime.io.request("registry_reset",{source_id:request.source_section,scope});
    next_excluded=filter(next_excluded,(entry)=>sprintf("%J",common.parse_json(entry.scope))!=scope);
   }
   else if(request.action=="dismiss") {
    runtime.io.request("registry_dismiss",{source_id:request.source_section,id:row.id});
   }
   else if(request.action=="forget") {
    if(row.status=="applied")runtime.io.request("registry_withdraw",{source_id:request.source_section,id:row.id});
    next_applied=filter(next_applied,(entry)=>entry.scope!=scope);
   }
   else if(request.action=="recheck") {
    let event=filter(snapshot.candidates ?? [],(entry)=>store.key({...entry,source_id:request.source_section})==scope && entry.network=="tcp")[0];
    if(event==null)die("A fresh matching flow is required");
    runtime.io.request("probe",{query:{source:event.source,ip:event.ip,domain:event.domain,source_ip:event.source_ip,source_port:event.source_port ?? 0,inbound:event.inbound,port:event.port}});
   }
   else {
    let lease=manual ? runtime.io.request("manual_apply",{source_id:request.source_section,id:row.id,target:item.target}) : runtime.io.request("apply",{id:row.id});
    let same_scope=store.key(lease)==scope || (manual && lease.persistent_ip==true && lease.source_id==request.source_section && lease.ip==row.ip && lease.source_ip==row.source_ip && lease.inbound==row.inbound && lease.port==row.port);
    if(lease.status!="applied" || lease.source_id!=request.source_section || !same_scope || (manual && (lease.source!=source.outbound || lease.target!=item.target || lease.failure?.id!=row.failure.id || lease.failure?.source_id!=row.failure.source_id))) {
     // Reject and withdraw a grant that cannot be durably bound to this row.
     if(lease.status=="applied")try{runtime.io.request("registry_withdraw",{source_id:request.source_section,id:lease.id});}catch(_){runtime.io.request("disable",{id:request.source_section});}
     die("Core returned a mismatched lease");
    }
    scope=store.key(lease);
    push(grants,lease);next_applied=filter(next_applied,(entry)=>entry.scope!=scope && !(lease.persistent_ip==true && entry.record.source_id==lease.source_id && entry.record.ip==lease.ip && (lease.all_devices==true || (entry.record.source_ip==lease.source_ip && entry.record.inbound==lease.inbound && entry.record.port==lease.port))));push(next_applied,{owner:"auto-routing",scope,record:lease});
   }
   push(results,{id:row.id,status:"done"});
  } catch(e) {push(results,{id:row.id,status:"failed",reason:e.message});}
 }
 try {
  if(request.action=="remove")store.save("excluded",next_excluded);
  if(index(["apply","exclude","forget"],request.action)>=0)store.save("applied",next_applied);
  if(index(["exclude","forget"],request.action)>=0)for(let item in picked)runtime.io.request("registry_release",{source_id:request.source_section,scope:item.scope});
 } catch(e) {
  // A failed durable approval must never leave an unrecorded active grant.
  for(let lease in grants)try{runtime.io.request("registry_withdraw",{source_id:request.source_section,id:lease.id});}catch(_){runtime.io.request("disable",{id:request.source_section});}
  if(request.action=="remove")for(let item in picked)try{runtime.io.request("registry_suppress",{source_id:request.source_section,scope:item.scope});}catch(_){runtime.io.request("disable",{id:request.source_section});}
  die(e.message);
 }
 return {success:true,done:length(filter(results,(r)=>r.status=="done")),skipped:length(filter(results,(r)=>r.status=="skipped")),failed:length(filter(results,(r)=>r.status=="failed")),results};
}
return {run,eligible,io};
