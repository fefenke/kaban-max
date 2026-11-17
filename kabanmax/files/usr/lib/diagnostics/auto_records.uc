// UI view only. The core's bounded read snapshot is not a complete event history.
let common = require("core.common");
let ip = require("core.ip");
let model = require("config.auto_routing");
let store = require("config.auto_registry");
let cached = null;
let cached_at = 0;
function invalidate() { cached=null; }
function select(snapshot, exclusions, query, saved) {
    let source = query.source_section;
    let status = query.status ?? "pending";
    let size = query.page_size ?? 25;
    let page = query.page ?? 1;
    let search = lc(query.search ?? "");
    let order = query.sort ?? "newest";
    if (type(source) != "string" || length(source) > 128 || source == "" ||
        index(["pending","applied","excluded"],status)<0 || index([25,50,100],size)<0 ||
        type(page)!="int" || page<1 || page>10000 || length(search)>253 ||
        index(["newest","oldest","ip","ip_desc"],order)<0) die("Invalid automatic routing page query");
    let configured = filter(snapshot.sources ?? [],(s)=>s.id==source)[0];
    let tag = configured?.outbound;
    let manual = snapshot.registry_version==3 && snapshot.manual_apply_supported==true;
    let available_targets=[];
    if(configured?.direct==true)push(available_targets,{tag:"direct-out",name:"Direct"});
    if(type(configured?.warp)=="string" && configured.warp!="")push(available_targets,{tag:configured.warp,name:filter(snapshot.warp_sections ?? [],(s)=>s.id==configured.warp_section)[0]?.name ?? configured.warp});
    function owned(row) {
        // A known foreign section must never be overwritten by an outbound
        // fallback, much less by the number of opted-in sections.
        if (row.source_id != null && row.source_id != "")
            return row.source_id == source && (row.source == null || row.source == "" || row.source == tag);
        return tag != null && row.source == tag;
    }
    function failed_here(row) {
        return owned(row) && type(row.failure)=="object" && row.failure.source_id==source &&
            type(row.failure.id)=="string" && row.failure.id!="" &&
            type(row.failure.message)=="string" && row.failure.message!="";
    }
    let seen={};
    let denied={};for(let entry in exclusions)denied[entry.scope]=true;
    function scope(row) { return row.ip; }
    function domains(row) { return uniq(filter([...(row.domains ?? []),row.domain ?? "",row.observed_domain ?? ""],(name)=>name!="")); }
    let grouped={};
    // Prefer a live event to a decision whose failure event has been evicted.
    let live={};for(let row in snapshot.candidates ?? [])live[row.id]=true;
    for(let row in [...(snapshot.decisions ?? []),...(snapshot.candidates ?? [])]) {
        if(!failed_here(row) || row.status=="applied" || row.status=="suppressed")continue;
        let old=grouped[row.ip];let names=uniq([...(old?.domains ?? []),...domains(row)]);
        let members=[...(old?.members ?? []),row];
        if(old==null || (live[row.id] && (!live[old.id] || common.as_string(row.updated ?? row.created)>common.as_string(old.updated ?? old.created))) || (!live[row.id] && !live[old.id] && common.as_string(row.updated ?? row.created)>common.as_string(old.updated ?? old.created)))grouped[row.ip]={...row,domains:names,members};
        else {old.domains=names;old.members=members;}
    }
    if(manual)for(let row in snapshot.candidates ?? [])if(failed_here(row)) {
        let current=grouped[row.ip];if(current?.id!=row.id)continue;
        let decisions=filter(snapshot.decisions ?? [],(d)=>failed_here(d) && d.failure?.id==row.id && d.ip==row.ip && d.source_ip==row.source_ip && d.inbound==row.inbound && d.port==row.port && (configured?.mode=="web" || (d.failure?.at==row.failure.at && d.failure?.message==row.failure.message && d.domain==row.domain)) && (d.status!="proposed" || length(filter(available_targets,(target)=>target.tag==d.target))>0));
        sort(decisions,(a,b)=>common.as_string(a.created)>common.as_string(b.created) ? -1 : 1);
        let decision=decisions[0];
        if(decision!=null && row.status!="checking")grouped[row.ip]={...decision,...current,status:decision.status,reason:decision.reason,target:decision.target,target_section:decision.target_section,attempts:decision.attempts,id:row.id,domains:current.domains};
    }
    for (let row in snapshot.leases ?? []) if (owned(row)) seen[scope(row)]=true;
    let pending=[];
    for (let row in values(grouped)) {
        if (!failed_here(row) || row.status=="applied" || row.status=="suppressed") continue;
        let id=scope(row);
        if (seen[id]) continue;
        seen[id]=true;push(pending,row);
    }
    let applied=filter(snapshot.leases ?? [],owned);
    let active={};for(let row in applied)active[store.key(row)]=true;
    for(let entry in saved ?? [])if(common.parse_json(entry.scope)[0]==source && !denied[entry.scope] && !active[entry.scope])push(applied,{...entry.record,id:"saved:"+entry.scope,status:"saved",apply_allowed:false});
    let applied_by_ip={};for(let row in applied) {
        let old=applied_by_ip[row.ip];let names=uniq([...(old?.domains ?? []),...domains(row),...(grouped[row.ip]?.domains ?? [])]);
        let members=[...(old?.members ?? []),row];
        if(old==null || (old.status=="saved" && row.status!="saved"))applied_by_ip[row.ip]={...row,domains:names,members,new_error:row.new_error==true || old?.new_error==true};else {old.domains=names;old.members=members;old.new_error=old.new_error==true || row.new_error==true;}
    }
    applied=values(applied_by_ip);
    let applied_ips={};for(let row in applied)applied_ips[row.ip]=true;
    pending=filter(pending,(row)=>!applied_ips[row.ip]);
    sort(pending,(a,b)=>{let left=common.as_string(a.updated ?? a.created);let right=common.as_string(b.updated ?? b.created);return left==right ? (common.as_string(a.id)<common.as_string(b.id) ? -1 : 1) : left>right ? -1 : 1;});
    pending=slice(pending,0,64);
    let excluded=[];
    for (let entry in exclusions) {
        let key=common.parse_json(entry.scope);
        if (key?.[0] == source) push(excluded,{id:entry.scope,source_id:source,ip:key[1],domain:key[2],domains:uniq([...(entry.domains ?? []),...(grouped[key[1]]?.domains ?? [])]),source_ip:key[3],inbound:key[4],port:key[5],status:"excluded",created:entry.created});
    }
    let excluded_by_ip={};for(let row in excluded) {
        let old=excluded_by_ip[row.ip];let names=uniq([...(old?.domains ?? []),...domains(row)]);
        excluded_by_ip[row.ip]={...row,domains:names,members:[...(old?.members ?? []),row]};
    }
    excluded=values(excluded_by_ip);
    let excluded_ips={};for(let row in excluded)excluded_ips[row.ip]=true;
    pending=filter(pending,(row)=>!excluded_ips[row.ip]);applied=filter(applied,(row)=>!excluded_ips[row.ip]);
    let lists={pending,applied,excluded};
    let rows=filter(lists[status],(row)=>search=="" || index(lc((row.ip ?? "")+" "+join(" ",domains(row))),search)>=0);
    sort(rows,(a,b)=>{
        let cmp=0;
        if(index(["ip","ip_desc"],order)>=0) {
            let left=ip.valid_ip(a.ip) ? iptoarr(a.ip) : [];
            let right=ip.valid_ip(b.ip) ? iptoarr(b.ip) : [];
            cmp=length(left)-length(right);
            for(let i=0;cmp==0 && i<length(left);i++)cmp=left[i]-right[i];
        } else {
            let left=common.as_string(a.created ?? "");
            let right=common.as_string(b.created ?? "");
            cmp=left<right ? -1 : left>right ? 1 : 0;
        }
        if(order=="newest" || order=="ip_desc")cmp=-cmp;
        return cmp || (common.as_string(a.id)<common.as_string(b.id) ? -1 : 1);
    });
    rows=map(rows,(row)=>({...row,target_name:filter(snapshot.warp_sections ?? [],(s)=>s.id==row.target_section)[0]?.name ?? row.target}));
    let total=length(rows);
    page=min(page,max(1,int((total+size-1)/size)));
    return {rows:slice(rows,(page-1)*size,page*size),total,page,page_size:size,
        counts:{pending:length(pending),applied:length(applied),excluded:length(excluded)},
        snapshot_limited:snapshot.registry_version!=2 && snapshot.registry_version!=3,version:snapshot.version ?? 0,reason:snapshot.reason ?? "",warning:snapshot.registry_error ?? "",registry_overflow:length(filter(snapshot.candidates ?? [],(row)=>row.status!="applied" && row.status!="suppressed"))>=64 ? snapshot.registry_overflow ?? 0 : 0,
        bulk_supported:snapshot.registry_version==2 || snapshot.registry_version==3,individual_reset_supported:snapshot.registry_version==2 || snapshot.registry_version==3,
        manual_apply_supported:manual,available_targets,
        legacy_overflow:length(rows)>64,selection:map(slice(rows,0,64),(row)=>({id:row.id,eligible:status=="pending" && (manual ? length(available_targets)>0 && failed_here(row) && model.valid_scope(store.key({...row,source_id:source})) : row.status=="proposed" && row.apply_allowed==true && (row.domain_known==true || row.ip_only==true))}))};
}
function page(query) {
    // Reject invalid queries before querying the core. Share a two-second read
    // snapshot across page/filter requests rather than polling once per caller.
    select({},[],query);
    let now=common.now_seconds();
    if(cached==null || now-cached_at>=2 || now<cached_at) {
        cached={snapshot:require("diagnostics.auto_routing").state(),exclusions:require("config.auto_routing").suppression().entries,saved:require("config.auto_registry").load().entries};
        cached_at=now;
    }
    return select(cached.snapshot,cached.exclusions,query,cached.saved);
}
return {select,page,invalidate};
