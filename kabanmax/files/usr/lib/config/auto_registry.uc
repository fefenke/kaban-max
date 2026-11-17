// Routing intent is staged in RAM and checkpointed to flash every 15 minutes.
// The core validates ownership, scope and current policy before routing.
let common=require("core.common");let model=require("config.auto_routing");let fs=require("fs");
let paths={applied:"/etc/kabanmax/auto-routing-applied.json",budget:"/var/run/kabanmax/auto-registry-write-budget.json",pending:"/var/run/kabanmax/auto-registry-pending.json",flushed:"/var/run/kabanmax/auto-registry-flushed.json"};
let io={now:()=>common.now_seconds(),monotonic:()=>int(common.monotonic_ms()/1000)};
function pending(kind) {
 if(paths.pending==null)return null;
 let raw=fs.readfile(paths.pending);if(raw==null)return null;
 let document=common.parse_json(raw);
 if(type(document)!="object" || document.version!=1)die("Pending registry is corrupt");
 return document[kind];
}
function key(row) { return sprintf("%J",[row.source_id,row.ip,row.domain ?? "",row.source_ip,row.inbound,row.port]); }
function identity(row) {return (row.domain_known==true && type(row.domain)=="string" && row.domain!="") || (row.ip_only==true && row.domain=="");}
function load() {
 let staged=pending("applied");let raw=staged!=null ? sprintf("%J",{version:1,entries:staged}) : fs.readfile(paths.applied);if(raw==null)return {version:1,entries:[]};
 let value=common.parse_json(raw);
 if(type(value)!="object" || value.version!=1 || type(value.entries)!="array" || length(value.entries)>64)die("Applied registry is corrupt or exceeds 64 records");
 let seen={};for(let entry in value.entries) {
  if(entry?.owner!="auto-routing" || !model.valid_scope(entry.scope) || type(entry.record)!="object" || entry.scope!=key(entry.record) || entry.record.owner!="auto-routing" || !identity(entry.record) || type(entry.record.target)!="string" || seen[entry.scope])die("Applied registry ownership or scope is corrupt");
  seen[entry.scope]=true;
 }
 return value;
}
function reserve() {
 let now=io.now();let raw=fs.readfile(paths.budget);let budget=raw==null ? {start:now,count:0} : common.parse_json(raw);
 if(type(budget)!="object" || type(budget.start)!="int" || type(budget.count)!="int")die("Registry write budget is corrupt");
 if(now<budget.start || now-budget.start>=60)budget={start:now,count:0};
 if(budget.count>=12)die("Registry flash write limit reached; retry after one minute");
 budget.count++;
 if(!common.write_file_atomic(paths.budget,sprintf("%J",budget)))die("Cannot reserve registry write budget");
}
function save(kind,entries) {
 if(index(["applied","excluded"],kind)<0 || type(entries)!="array")die("Invalid registry store");
 let previous=kind=="applied" ? load() : model.suppression();
 if(length(entries)>64 && length(entries)>=length(previous.entries))die("Registry is full (64 records); remove entries explicitly");
 let seen={};for(let entry in entries) {
  if(entry?.owner!="auto-routing" || !model.valid_scope(entry.scope) || seen[entry.scope])die("Invalid registry owner or duplicate scope");
  if(kind=="applied" && (entry.scope!=key(entry.record) || entry.record.owner!="auto-routing" || !identity(entry.record)))die("Invalid applied intent");
  seen[entry.scope]=true;
 }
 if(sprintf("%J",entries)==sprintf("%J",previous.entries))return false;
 if(paths.pending!=null) {
  if(fs.readfile(paths.flushed)==null && !common.write_file_atomic(paths.flushed,sprintf("%J",{at:io.monotonic()})))die("Cannot start registry flush clock");
  let document=common.read_json_file(paths.pending) ?? {version:1};document[kind]=entries;
  if(!common.write_file_atomic(paths.pending,sprintf("%J\n",document)))die("Registry RAM write failed");
  fs.chmod(paths.pending,0600);return true;
 }
 reserve();let path=kind=="applied" ? paths.applied : model.paths.suppression;
 if(!common.write_file_atomic(path,sprintf("%J\n",{version:1,entries})))die("Registry atomic write failed");
 fs.chmod(path,0600);
 return true;
}
function remember(leases) {
 let document=load();let entries=[...document.entries];
 for(let row in leases ?? []) {
  if(row.owner!="auto-routing" || row.status!="applied" || !identity(row) || !model.valid_scope(key(row)))continue;
  let scope=key(row);let index=-1;
  for(let i=0;i<length(entries);i++)if(entries[i].scope==scope)index=i;
  // Error timestamps, counters and newly seen domain labels belong in RAM.
  // Only routing intent changes need another flash checkpoint.
  if(index>=0 && entries[index].record.persistent_ip==true && row.persistent_ip==true && entries[index].record.all_ports==row.all_ports && entries[index].record.target==row.target && entries[index].record.id==row.id) {
   entries[index]={...entries[index],record:{...entries[index].record,domains:uniq([...(entries[index].record.domains ?? []),...(row.domains ?? [])]),new_error:row.new_error==true,...(row.new_error==true ? {failure:row.failure,error_port:row.error_port} : {})}};
   continue;
  }
  let entry={owner:"auto-routing",scope,record:row};
  if(index>=0)entries[index]=entry;else {if(length(entries)>=64)die("Applied registry is full (64 records)");push(entries,entry);}
 }
 save("applied",entries);return entries;
}
function intent(kind,entries) {
 return map(entries,(entry)=>{
  let copy={...entry};delete copy.domains;
  if(kind=="applied") {
   let record={...copy.record};delete record.domains;delete record.new_error;delete record.error_port;
   if(record.persistent_ip==true)delete record.reason;
   if(record.failure!=null)record.failure={source_id:record.failure.source_id};else delete record.failure;copy.record=record;
  }
  return copy;
 });
}
function flush() {
 if(paths.pending==null || fs.readfile(paths.pending)==null)return false;
 let now=io.monotonic();let last=common.read_json_file(paths.flushed)?.at;
 if(last==null) {
  if(!common.write_file_atomic(paths.flushed,sprintf("%J",{at:now})))die("Cannot start registry flush clock");
  return false;
 }
 if(now>=last && now-last<900)return false;
 let document=common.read_json_file(paths.pending);if(document?.version!=1)die("Pending registry is corrupt");
 // Denies reach disk first. At most one write per changed file per 15 minutes.
 for(let kind in ["excluded","applied"])if(document[kind]!=null) {
  let path=kind=="applied" ? paths.applied : model.paths.suppression;
  let text=sprintf("%J\n",{version:1,entries:document[kind]});
  let old=common.read_json_file(path);
  if(old?.version!=1 || sprintf("%J",intent(kind,old.entries ?? []))!=sprintf("%J",intent(kind,document[kind]))) {
   if(!common.write_file_atomic(path,text))die("Registry flash checkpoint failed");fs.chmod(path,0600);
  }
 }
 if(!common.write_file_atomic(paths.flushed,sprintf("%J",{at:now})))die("Cannot record registry flush clock");
 // Keep the RAM working copy: volatile labels/errors survive process reloads
 // without making the next flash checkpoint dirty.
 return true;
}
function saved(source) {
 let excluded={};for(let entry in model.suppression().entries)excluded[entry.scope]=true;
 return map(filter(load().entries,(entry)=>common.parse_json(entry.scope)[0]==source && !excluded[entry.scope] && !excluded[key({...entry.record,domain:""})]),(entry)=>entry.record);
}
return {paths,io,key,load,save,remember,saved,pending,flush};
