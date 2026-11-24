// Routing intent is staged in RAM; only changed compact intent reaches flash.
// The core validates ownership, scope and current policy before routing.
let common=require("core.common");let model=require("config.auto_routing");let fs=require("fs");
let storage=require("config.auto_storage");
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
 if(type(value)!="object" || value.version!=1 || type(value.entries)!="array")die("Applied registry is corrupt");
 let seen={};for(let entry in value.entries) {
  if(entry?.owner!="auto-routing" || !model.valid_scope(entry.scope) || type(entry.record)!="object" || entry.scope!=key(entry.record) || entry.record.owner!="auto-routing" || !identity(entry.record) || type(entry.record.target)!="string" || seen[entry.scope])die("Applied registry ownership or scope is corrupt");
  seen[entry.scope]=true;
 }
 return {version:1,entries:storage.entries("applied",value.entries)};
}
function reserve() {
 let now=io.now();let raw=fs.readfile(paths.budget);let budget=raw==null ? {start:now,count:0} : common.parse_json(raw);
 if(type(budget)!="object" || type(budget.start)!="int" || type(budget.count)!="int")die("Registry write budget is corrupt");
 if(now<budget.start || now-budget.start>=60)budget={start:now,count:0};
 if(budget.count>=12)die("Registry flash write limit reached; retry after one minute");
 budget.count++;
 if(!common.write_file_atomic(paths.budget,sprintf("%J",budget)))die("Cannot reserve registry write budget");
}
function check_capacity(kind,entries,headroom) {
 let previous=kind=="applied" ? load() : model.suppression();
 entries=storage.entries(kind,entries);
 let other_kind=kind=="applied" ? "excluded" : "applied";
 let other=other_kind=="applied" ? load().entries : model.suppression().entries;
 if(storage.bytes(entries)+storage.bytes(other)+(headroom ?? 0)>storage.settings().data_bytes && storage.bytes(entries)>=storage.bytes(previous.entries))die("registry_memory_budget: remove entries or increase the automatic routing memory budget");
 return true;
}
function save(kind,entries) {
 if(index(["applied","excluded"],kind)<0 || type(entries)!="array")die("Invalid registry store");
 let previous=kind=="applied" ? load() : model.suppression();
 let diagnostic_rows=kind=="applied" ? map(entries,(entry)=>entry.record) : null;
 entries=storage.entries(kind,entries);check_capacity(kind,entries);
 let seen={};for(let entry in entries) {
  if(entry?.owner!="auto-routing" || !model.valid_scope(entry.scope) || seen[entry.scope])die("Invalid registry owner or duplicate scope");
  if(kind=="applied" && (entry.scope!=key(entry.record) || entry.record.owner!="auto-routing" || !identity(entry.record)))die("Invalid applied intent");
  seen[entry.scope]=true;
 }
 if(sprintf("%J",entries)==sprintf("%J",previous.entries)) {if(diagnostic_rows!=null)require("config.auto_diagnostics").remember(diagnostic_rows);return false;}
 if(paths.pending!=null) {
  if(fs.readfile(paths.flushed)==null && !common.write_file_atomic(paths.flushed,sprintf("%J",{at:io.monotonic()})))die("Cannot start registry flush clock");
  let document=common.read_json_file(paths.pending) ?? {version:1};document[kind]=entries;
  if(!common.write_file_atomic(paths.pending,sprintf("%J\n",document)))die("Registry RAM write failed");
  fs.chmod(paths.pending,0600);if(diagnostic_rows!=null)require("config.auto_diagnostics").remember(diagnostic_rows);return true;
 }
 reserve();let path=kind=="applied" ? paths.applied : model.paths.suppression;
 if(!common.write_file_atomic(path,sprintf("%J\n",{version:1,entries})))die("Registry atomic write failed");
 fs.chmod(path,0600);
 if(diagnostic_rows!=null)require("config.auto_diagnostics").remember(diagnostic_rows);
 return true;
}
function remember(leases) {
 let document=load();let entries=[...document.entries];
 for(let row in leases ?? []) {
  if(row.owner!="auto-routing" || row.status!="applied" || !identity(row) || !model.valid_scope(key(row)))continue;
  if(row.all_devices==true)entries=filter(entries,(entry)=>entry.scope==key(row) || entry.record.source_id!=row.source_id || entry.record.ip!=row.ip || entry.record.persistent_ip!=true);
  let scope=key(row);let index=-1;
  for(let i=0;i<length(entries);i++)if(entries[i].scope==scope)index=i;
  // Error timestamps, counters and newly seen domain labels belong in RAM.
  // Only routing intent changes need another flash checkpoint.
  let entry={owner:"auto-routing",scope,record:row};
  if(index>=0)entries[index]=entry;else push(entries,entry);
 }
 save("applied",entries);return entries;
}
function dirty_bytes(kind,entries,old) {
 let previous={};for(let entry in old)previous[entry.scope]=sprintf("%J",entry);
 let bytes=0;let seen={};
 for(let entry in entries) {seen[entry.scope]=true;if(previous[entry.scope]!=sprintf("%J",entry))bytes+=storage.bytes(entry);}
 for(let entry in old)if(!seen[entry.scope])bytes+=storage.bytes(entry);
 return bytes;
}
function flush(pressure) {
 if(paths.pending==null || fs.readfile(paths.pending)==null)return false;
 let now=io.monotonic();let last=common.read_json_file(paths.flushed)?.at;
 if(last==null) {
  if(!common.write_file_atomic(paths.flushed,sprintf("%J",{at:now})))die("Cannot start registry flush clock");
  return false;
 }
 let document=common.read_json_file(paths.pending);if(document?.version!=1)die("Pending registry is corrupt");
 let limits=storage.settings();let dirty=0;
 for(let kind in ["excluded","applied"])if(document[kind]!=null) {
  let path=kind=="applied" ? paths.applied : model.paths.suppression;
  let raw=fs.readfile(path);let old=raw==null ? null : common.parse_json(raw);
  if(raw!=null && (old==null || old.version!=1 || type(old.entries)!="array"))die("Registry flash checkpoint is corrupt");
  dirty+=dirty_bytes(kind,storage.entries(kind,document[kind]),storage.entries(kind,old?.entries ?? []));
 }
 if(dirty==0)return false;
 let elapsed=now>=last ? now-last : 0;
 if(elapsed<limits.save_seconds && !((pressure==true || dirty>=int(limits.data_bytes*0.75)) && elapsed>=900))return false;
 // Denies reach disk first; pressure never bypasses the 15 minute write floor.
 for(let kind in ["excluded","applied"])if(document[kind]!=null) {
  let path=kind=="applied" ? paths.applied : model.paths.suppression;
  let entries=storage.entries(kind,document[kind]);
  let text=sprintf("%J\n",{version:1,entries});
  let old=common.read_json_file(path);
  if(old?.version!=1 || sprintf("%J",storage.entries(kind,old.entries ?? []))!=sprintf("%J",entries)) {
   if(!common.write_file_atomic(path,text))die("Registry flash checkpoint failed");fs.chmod(path,0600);
  }
 }
 if(!common.write_file_atomic(paths.flushed,sprintf("%J",{at:now})))die("Cannot record registry flush clock");
 // Keep the compact RAM working copy; diagnostics belong to the core snapshot.
 return true;
}
function saved(source) {
 let excluded={};for(let entry in model.suppression().entries)excluded[entry.scope]=true;
 return map(filter(load().entries,(entry)=>common.parse_json(entry.scope)[0]==source && !excluded[entry.scope] && !excluded[key({...entry.record,domain:""})]),(entry)=>entry.record);
}
return {paths,io,key,load,save,remember,saved,pending,flush,check_capacity};
