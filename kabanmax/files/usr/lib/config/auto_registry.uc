// Durable approvals are untrusted restore intents, not active leases.
let common=require("core.common");let model=require("config.auto_routing");let fs=require("fs");
let paths={applied:"/etc/kabanmax/auto-routing-applied.json",budget:"/var/run/kabanmax/auto-registry-write-budget.json"};
let io={now:()=>common.now_seconds()};
function key(row) { return sprintf("%J",[row.source_id,row.ip,row.domain ?? "",row.source_ip,row.inbound,row.port]); }
function load() {
 let raw=fs.readfile(paths.applied);if(raw==null)return {version:1,entries:[]};
 let value=common.parse_json(raw);
 if(type(value)!="object" || value.version!=1 || type(value.entries)!="array" || length(value.entries)>64)die("Applied registry is corrupt or exceeds 64 records");
 let seen={};for(let entry in value.entries) {
  if(entry?.owner!="auto-routing" || !model.valid_scope(entry.scope) || type(entry.record)!="object" || entry.scope!=key(entry.record) || entry.record.owner!="auto-routing" || !entry.record.domain_known || entry.record.domain=="" || type(entry.record.target)!="string" || seen[entry.scope])die("Applied registry ownership or scope is corrupt");
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
  if(kind=="applied" && (entry.scope!=key(entry.record) || entry.record.owner!="auto-routing" || !entry.record.domain_known || entry.record.domain==""))die("Invalid applied intent");
  seen[entry.scope]=true;
 }
 if(sprintf("%J",entries)==sprintf("%J",previous.entries))return false;
 reserve();let path=kind=="applied" ? paths.applied : model.paths.suppression;
 if(!common.write_file_atomic(path,sprintf("%J\n",{version:1,entries})))die("Registry atomic write failed");
 fs.chmod(path,0600);
 return true;
}
function remember(leases) {
 let document=load();let entries=[...document.entries];
 for(let row in leases ?? []) {
  if(row.owner!="auto-routing" || row.status!="applied" || !row.domain_known || !model.valid_scope(key(row)))continue;
  let scope=key(row);let index=-1;
  for(let i=0;i<length(entries);i++)if(entries[i].scope==scope)index=i;
  let entry={owner:"auto-routing",scope,record:row};
  if(index>=0)entries[index]=entry;else {if(length(entries)>=64)die("Applied registry is full (64 records)");push(entries,entry);}
 }
 save("applied",entries);return entries;
}
function saved(source) {
 let excluded={};for(let entry in model.suppression().entries)excluded[entry.scope]=true;
 return map(filter(load().entries,(entry)=>common.parse_json(entry.scope)[0]==source && !excluded[entry.scope]),(entry)=>entry.record);
}
return {paths,io,key,load,save,remember,saved};
