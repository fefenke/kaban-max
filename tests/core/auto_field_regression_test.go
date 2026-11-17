package autoroute

import (
 "context"
 "errors"
 "encoding/json"
 "github.com/sagernet/sing-box/option"
 "github.com/sagernet/sing-box/adapter"
  "net/http"
 "sync"
 "testing"
 "time"
 "crypto/tls"
 "net/http/httptest"
 "net/netip"
 M "github.com/sagernet/sing/common/metadata"
)

func TestOrdinaryHTTPS204AutoApplies(t *testing.T) {
 m,q,_,_:=webManager(t,204,"")
 s:=m.sources[q.Source];s.AutoApply=true;m.sources[q.Source]=s
 answer,err:=m.Probe(context.Background(),q)
 if err!=nil {t.Fatal(err)}
 d,ok:=answer.(Decision)
 if !ok || d.Status!="applied" || len(m.leases)!=1 {t.Fatalf("valid HTTPS 204 did not auto apply: %+v",answer)}
 for _,a:=range d.Attempts {if !a.TLSVerified || a.HTTPStatus!=204 {t.Fatalf("missing HTTPS evidence: %+v",a)}}
}

func TestCompletedAlternativeSurvivesNewOriginalFailure(t *testing.T) {
 m,q,_,direct:=webManager(t,200,normalPage)
 answer,err:=m.Probe(context.Background(),q);if err!=nil||answer.(Decision).Status!="proposed"{t.Fatal(answer,err)}
 next:=q;next.Domain="another.example";next.SourcePort++
 meta:=metadata(next);event:=m.Observe(&meta,q.Source);m.Failed(event,errors.New("new original timeout"))
 for _,e:=range m.events{if e.Status!="proposed"||!e.attempted{t.Fatal("ready alternative reset to endless search",e)}}
 calls:=direct.calls.Load();m.Sweep(context.Background());if direct.calls.Load()!=calls{t.Fatal("rechecked a completed pending proposal")}
}

func TestProbeCompletionFollowsIPWhenDomainChanges(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage)
 m.stage(q,"checking","checking:direct-out")
 next:=q;next.Domain="another.example";next.SourcePort++
 meta:=metadata(next);event:=m.Observe(&meta,q.Source);m.Failed(event,errors.New("concurrent original timeout"))
 m.stage(q,"proposed","repeated_transport_failure_alternative_reachable")
 for _,e:=range m.events{if e.Status!="proposed"||!e.attempted{t.Fatal("completion missed changed domain of same IP",e)}}
}

func TestSweepFinalizesUnstagedProbeErrors(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage)
 s:=m.sources[q.Source];s.Status=0;s.Prefix="";s.Mode="strict";m.sources[q.Source]=s
 m.Sweep(context.Background())
 for _,e:=range m.events{if e.Status=="checking"||e.Status=="detected"||e.Reason=="connection_error"{t.Fatal("finished error still displayed as active search",e)}}
}

func TestProbeRetainsFailureWhenAnotherConnectionReplacesQuery(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage)
 s:=m.sources[q.Source];s.AutoApply=true;m.sources[q.Source]=s
 var once sync.Once
 originalMatch:=m.Match
 m.Match=func(ctx context.Context,meta *adapter.InboundContext)(string,error){
  once.Do(func(){other:=q;other.SourcePort=54321;updated:=metadata(other);event:=m.Observe(&updated,q.Source);m.Failed(event,errors.New("new connection timeout"))})
  return originalMatch(ctx,meta)
 }
 answer,err:=m.Probe(context.Background(),q)
 if err!=nil {t.Fatal(err)}
 d,ok:=answer.(Decision)
 if !ok || d.Status!="applied" || d.Failure==nil {t.Fatalf("concurrent failure destroyed active check: %+v",answer)}
}

func TestManualUDPRecordAppliesAndRoutes(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage)
 m.events=map[string]*Event{}
 meta:=metadata(q);meta.Network="udp"
 event:=m.Observe(&meta,q.Source);m.Failed(event,errors.New("UDP timeout"))
 if _,err:=manualAPI(m,"s1",event.ID,"direct-out");err!=nil {t.Fatal("UDP record shown as applicable but API refused it",err)}
 if got:=m.SelectForEvent(context.Background(),q.Source,&meta,event);got!="direct-out" {t.Fatal("manual UDP rule did not route packets",got)}
}

func TestLegacyConflictingFakeIPRecordIsNotRestoredAsEvidence(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage)
 event:=manualEvent(m)
 event.originalMetadata.FakeIP=true
 event.originalMetadata.Domain="different.example"
 s:=m.sources[q.Source]
 for _,e:=range m.checkpoint(){raw,_:=json.Marshal(e);s.Pending=append(s.Pending,raw)}
 restored:=New(context.Background(),[]option.KabanmaxAutoSource{s});defer restored.Close()
 if len(restored.events)!=0 {t.Fatal("restored invalid IP/domain evidence after FakeIP conflict repair")}
}

func TestOrdinaryAPIJSONErrorIsValidApplicationTransport(t *testing.T){
 for _,status:=range []int{http.StatusBadRequest,http.StatusUnauthorized,http.StatusNotFound,http.StatusMethodNotAllowed}{
  m,q,_,_:=webManager(t,status,`{"error":{"message":"This API method requires valid credentials","code":100}}`,map[string]string{"Content-Type":"application/json"})
  answer,err:=m.Probe(context.Background(),q);if err!=nil{t.Fatal(err)}
  if answer.(Decision).Status!="proposed"{t.Fatalf("API %d rejected despite valid TLS/application JSON: %+v",status,answer)}
 }
}

func TestLegacyCoreOwnedFailureAllowsExplicitChoiceWithoutInventingProbeMetadata(t *testing.T){
 m,q,_,_:=webManager(t,200,normalPage)
 event:=manualEvent(m);event.originalMetadata=nil
 m.Match=func(context.Context,*adapter.InboundContext)(string,error){return "",errors.New("probe_scope_requires_connection_metadata")}
 if _,err:=manualAPI(m,"s1",event.ID,"direct-out");err!=nil{t.Fatal("manual choice unnecessarily required missing replay metadata",err)}
 m.leases=map[string]Lease{}
 answer,err:=m.Probe(context.Background(),q);if err!=nil{t.Fatal(err)}
 if len(m.leases)!=0{t.Fatal("manual exception escaped into automatic probing",answer)}
}

func TestLiteralIPUsesOnlySameFlowSniffedTLSName(t *testing.T){
 m,q,_,_:=webManager(t,204,"")
 m.events=map[string]*Event{}
 meta:=metadata(q);meta.Destination=M.Socksaddr{Addr:netip.MustParseAddr(q.IP),Port:q.Port};meta.Domain=q.Domain;meta.Protocol="tls"
 event:=m.Observe(&meta,q.Source);m.Failed(event,errors.New("logged literal IP TLS timeout"))
 if event.Domain!="" || event.ObservedDomain!=q.Domain{t.Fatal("lost sniffed SNI or invented DNS ownership",event)}
 s:=m.sources[q.Source];s.AutoApply=true;s.AllowIPOnly=true;m.sources[q.Source]=s
 answer,err:=m.Probe(context.Background(),event.Query);if err!=nil{t.Fatal(err)}
 if answer.(Decision).Status!="applied"{t.Fatalf("literal IP TLS check lost actual SNI: %+v",answer)}
 meta.Protocol="";event=m.Observe(&meta,q.Source)
 if event.ObservedDomain!=""{t.Fatal("reverse mapping was promoted to sniffed identity")}
}

func TestPrivateCheckpointRestoresSniffedNameForLegacyLiteralIP(t *testing.T){
 m,q,_,_:=webManager(t,200,normalPage)
 m.events=map[string]*Event{}
 meta:=metadata(q);meta.Destination=M.Socksaddr{Addr:netip.MustParseAddr(q.IP),Port:q.Port};meta.Domain=q.Domain;meta.Protocol="tls"
 event:=m.Observe(&meta,q.Source);m.Failed(event,errors.New("literal timeout"));event.ObservedDomain=""
 source:=m.sources[q.Source]
 for _,saved:=range m.checkpoint(){raw,_:=json.Marshal(saved);source.Pending=append(source.Pending,raw)}
 restored:=New(context.Background(),[]option.KabanmaxAutoSource{source});defer restored.Close()
 if restored.events[event.ID]==nil || restored.events[event.ID].ObservedDomain!=q.Domain{t.Fatal("private checkpoint lost same-flow TLS identity")}
}

func TestInterruptedCheckReturnsToQueueWithoutNewFailure(t *testing.T){
 m,q,_,_:=webManager(t,204,"")
 s:=m.sources[q.Source];s.AutoApply=true;m.sources[q.Source]=s
 var once sync.Once;match:=m.Match
 m.Match=func(ctx context.Context,meta *adapter.InboundContext)(string,error){once.Do(func(){m.mu.Lock();m.generation++;m.mu.Unlock()});return match(ctx,meta)}
 m.Sweep(context.Background())
 if len(m.leases)!=0{t.Fatal("cancelled generation granted a route")}
 for _,e:=range m.events{if e.attempted || !e.lastJob.IsZero(){t.Fatal("cancelled check left the automatic queue",e)}}
 m.Sweep(context.Background())
 if len(m.leases)!=1{t.Fatal("no automatic retry without another logged failure",m.State())}
}

func TestCooldownDoesNotRestartItsFiveMinuteWindow(t *testing.T){
 m,q,_,_:=webManager(t,204,"")
 original:=time.Now().Add(-4*time.Minute);m.cooldown[m.probeKey(q)]=original
 m.Sweep(context.Background())
 for _,e:=range m.events{if !e.lastJob.Equal(original) || e.attempted{t.Fatal("cooldown deadline moved forward on retry",e)}}
}
func TestDismissedRecordDoesNotKeepAnInvisibleCooldown(t *testing.T){
 m,q,_,_:=webManager(t,204,"")
 m.cooldown[m.probeKey(q)]=time.Now()
 var event *Event;for _,e:=range m.events{event=e}
 if _,err:=m.registryDismiss("s1",event.ID);err!=nil{t.Fatal(err)}
 meta:=metadata(q);next:=m.Observe(&meta,q.Source);m.Failed(next,errors.New("new logged failure after explicit clear"))
 m.Sweep(context.Background())
 if len(m.decisions)!=1{t.Fatal("new record inherited deleted record cooldown",m.State())}
}

func TestOrdinaryTransportAcceptsRealServerResponsesRegardlessOfApplicationStatus(t *testing.T){
 for _,status:=range []int{200,204,302,401,403,404,429,503}{
  m,q,_,_:=webManager(t,status,"response from the authenticated origin")
  answer,err:=m.Probe(context.Background(),q);if err!=nil{t.Fatal(err)}
  d:=answer.(Decision);if d.Status!="proposed"||d.Target!="direct-out"{t.Fatalf("real HTTP %d treated as broken routing: %+v",status,d)}
 }
}
func TestOrdinaryDirectIsCheckedBeforeWARP(t *testing.T){
 m,q,_,direct:=webManager(t,403,normalPage)
 source:=m.sources[q.Source];source.WARP="warp-test";m.sources[q.Source]=source
 warp:=&testOutbound{tag:"warp-test",kind:"warp",address:direct.address};original:=m.Outbound
 m.Outbound=func(tag string)(adapter.Outbound,bool){if tag=="warp-test"{return warp,true};return original(tag)}
 answer,err:=m.Probe(context.Background(),q);if err!=nil{t.Fatal(err)}
 if answer.(Decision).Target!="direct-out" || direct.calls.Load()!=2 || warp.calls.Load()!=0{t.Fatal("WARP bypassed the working Direct alternative",answer)}
}

func TestNativeTLSALPNDoesNotReceiveAnHTTPProbe(t *testing.T){
 m,q,_,direct:=webManager(t,200,normalPage)
 server:=httptest.NewUnstartedServer(http.HandlerFunc(func(http.ResponseWriter,*http.Request){t.Error("HTTP request sent to native TLS service")}))
 server.TLS=&tls.Config{NextProtos:[]string{"native-test-protocol"}};server.StartTLS();defer server.Close()
 adapter.RootPoolFromContext(m.ctx).AddCert(server.Certificate());direct.address=server.Listener.Addr().String()
 m.events=map[string]*Event{};meta:=metadata(q);meta.Protocol="tls";meta.SniffedALPN=[]string{"native-test-protocol"}
 event:=m.Observe(&meta,q.Source);m.Failed(event,errors.New("logged native TLS error"))
 answer,err:=m.Probe(context.Background(),event.Query);if err!=nil{t.Fatal(err)};d:=answer.(Decision)
 if d.Status!="proposed"||direct.calls.Load()!=2{t.Fatal("native TLS falsely rejected",d)}
 for _,a:=range d.Attempts{if a.Method!="TLS"||!a.TLSVerified||a.TransportBytes==0{t.Fatal("missing TLS data evidence",a)}}
}

func TestOrdinaryHTTPHeadersWithoutBodyAreNotTransportSuccess(t *testing.T){
 m,q,_,direct:=webManager(t,200,normalPage)
 stalled:=httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){
  w.Header().Set("Content-Length","128");w.WriteHeader(200);w.(http.Flusher).Flush();<-r.Context().Done()
 }));defer stalled.Close()
 adapter.RootPoolFromContext(m.ctx).AddCert(stalled.Certificate());direct.address=stalled.Listener.Addr().String()
 ctx,cancel:=context.WithTimeout(context.Background(),300*time.Millisecond);defer cancel()
 answer,err:=m.Probe(ctx,q);if err!=nil{t.Fatal(err)};d:=answer.(Decision)
 if d.Status=="proposed"||len(m.leases)!=0{t.Fatal("headers with a stalled body were accepted",d)}
 if len(d.Attempts)==0||!d.Attempts[0].TLSVerified||d.Attempts[0].Status=="verified"{t.Fatal("missing stalled-body control",d)}
}
