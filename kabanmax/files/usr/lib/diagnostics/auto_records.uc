// UI view only. The core's bounded read snapshot is not a complete event history.
let common = require("core.common");
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
        index(["newest","oldest","ip"],order)<0) die("Invalid automatic routing page query");
    let tag = filter(snapshot.sources ?? [],(s)=>s.id==source)[0]?.outbound;
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
    function scope(row) { return sprintf("%J",[row.ip,row.domain ?? "",row.source_ip ?? "",row.inbound ?? "",row.port ?? 443]); }
    for (let row in snapshot.leases ?? []) if (owned(row)) seen[scope(row)]=true;
    let pending=[];
    for (let row in [...(snapshot.decisions ?? []),...(snapshot.candidates ?? [])]) {
        if (!failed_here(row) || row.status=="applied" || row.status=="suppressed") continue;
        let id=scope(row);
        if (seen[id]) continue;
        seen[id]=true;push(pending,row);
    }
    let applied=filter(snapshot.leases ?? [],owned);
    let active={};for(let row in applied)active[scope(row)]=true;
    for(let entry in saved ?? [])if(common.parse_json(entry.scope)[0]==source && !denied[entry.scope] && !active[scope(entry.record)])push(applied,{...entry.record,id:"saved:"+entry.scope,status:"saved",apply_allowed:false});
    sort(pending,(a,b)=>{let left=common.as_string(a.updated ?? a.created);let right=common.as_string(b.updated ?? b.created);return left==right ? (common.as_string(a.id)<common.as_string(b.id) ? -1 : 1) : left>right ? -1 : 1;});
    pending=slice(pending,0,64);
    let excluded=[];
    for (let entry in exclusions) {
        let key=common.parse_json(entry.scope);
        if (key?.[0] == source) push(excluded,{id:entry.scope,source_id:source,ip:key[1],domain:key[2],source_ip:key[3],inbound:key[4],port:key[5],status:"excluded",created:entry.created});
    }
    let lists={pending,applied,excluded};
    let rows=filter(lists[status],(row)=>search=="" || index(lc((row.ip ?? "")+" "+(row.domain ?? "")),search)>=0);
    sort(rows,(a,b)=>{
        let left=order=="ip" ? a.ip : common.as_string(a.created ?? "");
        let right=order=="ip" ? b.ip : common.as_string(b.created ?? "");
        let cmp=left<right ? -1 : left>right ? 1 : 0;
        if(order=="newest")cmp=-cmp;
        return cmp || (common.as_string(a.id)<common.as_string(b.id) ? -1 : 1);
    });
    let total=length(rows);
    page=min(page,max(1,int((total+size-1)/size)));
    return {rows:slice(rows,(page-1)*size,page*size),total,page,page_size:size,
        counts:{pending:length(pending),applied:length(applied),excluded:length(excluded)},
        snapshot_limited:snapshot.registry_version!=2 && snapshot.registry_version!=3,version:snapshot.version ?? 0,reason:snapshot.reason ?? "",warning:snapshot.registry_error ?? "",
        bulk_supported:snapshot.registry_version==2 || snapshot.registry_version==3,individual_reset_supported:snapshot.registry_version==2 || snapshot.registry_version==3,
        legacy_overflow:length(rows)>64,selection:map(slice(rows,0,64),(row)=>({id:row.id,eligible:row.status=="proposed" && row.apply_allowed==true && (row.domain_known==true || row.ip_only==true)}))};
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
