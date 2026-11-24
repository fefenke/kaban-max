let common=require("core.common");let uci=require("core.uci");
let io={settings:()=>uci.get_all("kabanmax","settings") ?? {}};
function settings() {
 let value=io.settings();
 let save=common.duration_to_seconds(common.option(value,"auto_routing_save_interval","1d"));
 // Internal housekeeping for transient counters/history; pending records do not expire.
 let cleanup=3600;
 let mib=common.option(value,"auto_routing_memory_mib","4");
 if(save==null || save<900 || save>2592000)die("Automatic routing save interval must be between 15m and 30d");
 if(!match(common.as_string(mib),/^[0-9]+$/) || int(mib)<1 || int(mib)>32)die("Automatic routing memory budget must be between 1 and 32 MiB");
 let memory=int(mib)*1048576;
 // Reserve headroom for core objects, JSON parsing and response copies.
 return {save_seconds:save,cleanup_seconds:cleanup,memory_bytes:memory,data_bytes:int(memory/4)};
}
function compact(row) {
 let copy={};
 for(let name in ["id","owner","source_id","source","ip","domain","domain_known","ip_only","source_ip","inbound","port","target","target_section","status","persistent_ip","all_ports","all_devices","created","expires","evidence","decision_id"])
  if(row[name]!=null)copy[name]=row[name];
 if(row.failure!=null)copy.failure={source_id:row.failure.source_id};
 return copy;
}
function entries(kind,rows) {
 return map(rows,(entry)=>kind=="applied" ? {owner:entry.owner,scope:entry.scope,record:compact(entry.record)} : {owner:entry.owner,scope:entry.scope,created:entry.created});
}
function bytes(value) {return length(sprintf("%J",value));}
return {settings,compact,entries,bytes,io};
