// RAM-only diagnostic context. Never grants permission and never reaches flash intent.
let common=require("core.common");let fs=require("fs");
let paths={state:"/var/run/kabanmax/auto-routing-applied-diagnostics.json",error:"/var/run/kabanmax/auto-routing-applied-diagnostics.error"};
let io={limit:()=>require("config.auto_storage").settings().data_bytes};
function valid_failure(f,source) {
 return type(f)=="object" && f.source_id==source && type(f.id)=="string" && f.id!="" &&
  type(f.message)=="string" && f.message!="" && type(f.at)=="string" && f.at!="" && substr(f.at,0,5)!="0001-";
}
function bounded(value,limit) {
 if(length(value)<=limit)return value;
 let end=limit-3;while(end>0 && (ord(value,end)&192)==128)end--;
 return substr(value,0,end)+"...";
}
function failure(f,source) {
 return valid_failure(f,source) ? {id:bounded(f.id,128),source_id:source,message:bounded(f.message,4096),at:bounded(f.at,64)} : null;
}
function labels(rows) {
 let result=[];let size=0;
 for(let value in rows) {
  if(type(value)!="string")continue;
  value=lc(trim(value));
  if(length(value)>253 || !match(value,/^[a-z0-9_-]+(\.[a-z0-9_-]+)+\.?$/) || index(result,value)>=0 || size+length(value)>1024 || length(result)>=32)continue;
  push(result,value);size+=length(value);
 }
 return result;
}
function bound(row) {
 return row?.owner=="auto-routing" && type(row.id)=="string" && row.id!="" && type(row.source_id)=="string" && row.source_id!="" && type(row.ip)=="string" && type(row.target)=="string";
}
function same(a,b) {return a.id==b.id && a.source_id==b.source_id && a.ip==b.ip && a.target==b.target;}
function binding(row) {return sprintf("%J",[row.id,row.source_id,row.ip,row.target]);}
function ip_binding(row) {return sprintf("%J",[row.source_id,row.ip]);}
function read() {
 let raw=fs.readfile(paths.state);if(raw==null)return [];
 if(length(raw)>io.limit())die("Applied diagnostics exceed RAM budget");
 let doc=common.parse_json(raw);
 if(doc?.version!=1 || type(doc.entries)!="array")die("Applied diagnostics checkpoint is corrupt");
 return filter(doc.entries,(r)=>bound(r));
}
function error() {return common.read_first_line(paths.error);}
function remember(rows) {
 try {
  let previous=read();let result=[];let by_id={};let by_ip={};
  for(let row in previous){by_id[binding(row)]=row;let key=ip_binding(row);by_ip[key]=labels([...(by_ip[key] ?? []),...(row.domains ?? [])]);}
  for(let row in rows ?? []) {
   if(!bound(row))continue;
   let old=by_id[binding(row)];
   let original=failure(row.original_failure,row.source_id) ?? (!row.new_error ? failure(row.failure,row.source_id) : null) ?? old?.original_failure;
   let latest=row.new_error ? failure(row.failure,row.source_id) ?? old?.failure : old?.failure;
   let names=by_ip[ip_binding(row)] ?? [];
   names=labels([...names,...(row.domains ?? []),row.domain ?? "",row.observed_domain ?? ""]);
   push(result,{owner:"auto-routing",id:row.id,source_id:row.source_id,ip:row.ip,target:row.target,
    domains:names,original_failure:original,failure:latest,error_port:row.error_port ?? old?.error_port,new_error:row.new_error==true || old?.new_error==true});
  }
  let text=sprintf("%J",{version:1,entries:result});
  if(length(text)>io.limit())die("Applied diagnostics RAM budget is full; previous details retained");
  if(text!=fs.readfile(paths.state)) {
   if(!common.write_file_atomic(paths.state,text))die("Cannot save Applied diagnostics in RAM");
   fs.chmod(paths.state,0600);
  }
  fs.unlink(paths.error);return true;
 }catch(e){common.write_file_atomic(paths.error,bounded(e.message,512)+"\n");return false;}
}
function enrich(row,stored) {
 let copy={...row};if(!bound(row))return copy;
 try {
  if(stored==null){stored={};for(let entry in read())stored[binding(entry)]=entry;}
  let found=stored[binding(row)];
  copy.domains=labels([...(found?.domains ?? []),...(row.domains ?? []),row.domain ?? "",row.observed_domain ?? ""]);
  copy.original_failure=failure(row.original_failure,row.source_id) ?? found?.original_failure ?? (!row.new_error ? failure(row.failure,row.source_id) : null);
  copy.new_error=row.new_error==true || found?.new_error==true;
  copy.error_port=row.error_port ?? found?.error_port;
  copy.failure=failure(row.failure,row.source_id) ?? (copy.new_error ? found?.failure : copy.original_failure);
  if(copy.new_error && found?.failure && !row.new_error)copy.failure=found.failure;
 }catch(e){}
 if(!valid_failure(copy.failure,row.source_id))delete copy.failure;
 if(!valid_failure(copy.original_failure,row.source_id))delete copy.original_failure;
 return copy;
}
function enricher() {
 let stored={};try{for(let row in read())stored[binding(row)]=row;}catch(e){}
 return (row)=>enrich(row,stored);
}
return {paths,io,remember,enrich,enricher,error,valid_failure};
