let common=require("core.common");let model=require("config.auto_routing");let store=require("config.auto_registry");
let io={state:()=>require("diagnostics.auto_routing").state(),request:(op,payload)=>require("diagnostics.auto_routing").io.request(op,payload)};
function eligible(row) {return row.status=="proposed" && row.apply_allowed==true && ((row.domain_known==true && row.domain!="") || row.ip_only==true);}
function run(payload) {
 let request=common.parse_json(payload);
 if(type(request)!="object" || index(["apply","exclude","remove","recheck","forget","dismiss"],request.action)<0 || type(request.ids)!="array" || length(request.ids)<1 || length(request.ids)>8)die("Invalid registry batch (maximum 8 IDs)");
 if(request.action=="recheck" && length(request.ids)!=1)die("Verification accepts one flow per request");
 if((request.action=="remove" && request.status!="excluded") || (index(["apply","dismiss"],request.action)>=0 && request.status!="pending"))die("Action does not match registry tab");
 let runtime={io};let snapshot=io.state();
 if(snapshot.registry_version!=2 && snapshot.registry_version!=3)die("Registry actions require the r13 core API");
 if(request.action=="dismiss" && snapshot.registry_version!=3)die("Registry actions require the r13 core API");
 let query={source_section:request.source_section,status:request.status,search:request.search ?? "",sort:request.sort ?? "newest",page:1,page_size:100};
 let excluded=model.suppression().entries;let applied=store.load().entries;
 let page=require("diagnostics.auto_records").select(snapshot,excluded,query,applied);
 let available={};for(let row in page.rows)if(row.id!=null)available[row.id]=row;
 let source=filter(snapshot.sources ?? [],(s)=>s.id==request.source_section)[0];
 if(source==null)die("Active original Zapret2 source is unavailable");
 let picked=[];let results=[];let seen={};
 for(let id in request.ids) {
  if(type(id)!="string" || length(id)>1200)die("Invalid registry ID");
  let row=available[id];
  if(seen[id] || row==null || (request.action=="apply" && !eligible(row))) {push(results,{id,status:"skipped",reason:"stale_or_ineligible"});continue;}
  seen[id]=true;
  if(row.source_id!=request.source_section && row.source!=source.outbound){push(results,{id,status:"skipped",reason:"source_not_attested"});continue;}
  let key=store.key({...row,source_id:request.source_section});
  if(!model.valid_scope(key)) {push(results,{id,status:"skipped",reason:"unattested_scope"});continue;}
  push(picked,{row,scope:key});
 }
 // Capacity and storage checks precede any permission-granting core mutation.
 let next_applied=[...applied];let next_excluded=[...excluded];
 if(request.action=="exclude") {
  for(let item in picked)if(length(filter(next_excluded,(e)=>e.scope==item.scope))==0)push(next_excluded,{owner:"auto-routing",scope:item.scope,created:common.now_seconds()});
  store.save("excluded",next_excluded); // Durable deny intent first; never lose it on crash.
 }
 if(request.action=="apply") {
  let wanted={};for(let entry in applied)wanted[entry.scope]=true;for(let item in picked)wanted[item.scope]=true;
  if(length(keys(wanted))>64)die("Applied registry is full (64 records)");
 }
 let grants=[];
 for(let item in picked) {
  let row=item.row;let scope=item.scope;
  try {
   if(request.action=="exclude") {
    try {runtime.io.request("registry_suppress",{source_id:request.source_section,scope});}
    catch(e) {runtime.io.request("disable",{id:request.source_section});die("Scope exclusion failed; source stopped fail-closed: "+e.message);}
    next_applied=filter(next_applied,(entry)=>entry.scope!=scope);
   }
   else if(request.action=="remove") {
    runtime.io.request("registry_reset",{source_id:request.source_section,scope});
    next_excluded=filter(next_excluded,(entry)=>entry.scope!=scope);
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
    let lease=runtime.io.request("apply",{id:row.id});
    if(lease.status!="applied" || lease.source_id!=request.source_section || store.key(lease)!=scope)die("Core returned a mismatched lease");
    push(grants,lease);next_applied=filter(next_applied,(entry)=>entry.scope!=scope);push(next_applied,{owner:"auto-routing",scope,record:lease});
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
