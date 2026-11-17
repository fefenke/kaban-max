let t=require("t");let view=require("diagnostics.auto_records");
let lease={id:"lease",owner:"auto-routing",source_id:"zap",source:"zap-out",ip:"203.0.113.8",domain:"example.com",source_ip:"192.0.2.8",inbound:"tproxy-in",port:443,status:"applied",all_ports:true,target:"warp-out",failure:{id:"old",source_id:"zap",message:"old error"}};
let event={...lease,id:"new",port:5222,status:"inconclusive",failure:{id:"new",source_id:"zap",message:"new error"}};
let snapshot={registry_version:3,manual_apply_supported:true,sources:[{id:"zap",outbound:"zap-out",direct:true,warp:"warp-out"}],leases:[lease],candidates:[event],decisions:[]};
t.test("one applied IP reports uncovered device scopes without claiming health",()=>{
 let page=view.select(snapshot,[],{source_section:"zap",status:"applied"});
 t.eq(page.rows[0].uncovered_connections,0);t.eq(page.rows[0].all_ports,true);
 event.source_ip="192.0.2.9";
 page=view.select(snapshot,[],{source_section:"zap",status:"applied"});t.eq(page.total,1);t.eq(page.rows[0].uncovered_connections,1);t.eq(page.rows[0].failure.id,"new");
});
t.test("other-port route failure is retained in the applied row",()=>{
 lease.new_error=true;lease.error_port=5222;lease.failure=event.failure;
 let page=view.select(snapshot,[],{source_section:"zap",status:"applied"});t.eq(page.rows[0].error_port,5222);t.eq(page.rows[0].new_error,true);
});
t.done();
