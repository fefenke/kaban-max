package autoroute

import (
 "context"
 "errors"
 "crypto/ecdsa"
 "crypto/elliptic"
 "crypto/rand"
 "crypto/tls"
 "crypto/x509"
 "math/big"
 "net"
 "net/http"
 "net/http/httptest"
 "github.com/sagernet/sing-box/adapter"
 "github.com/sagernet/sing/service"
 "testing"
 "time"
)

func TestHealthyAndStalledObservationsAreNotLoggedFailures(t *testing.T) {
 m,q,_,_:=testManager(t,"fail:")
 m.events=map[string]*Event{}
 meta:=metadata(q)
 if m.Observe(&meta,"warp")!=nil {t.Fatal("foreign WARP attributed to Zapret")}
 event:=m.Observe(&meta,q.Source)
 event.Upload=10;event.progress=time.Now().Add(-time.Minute)
 state:=m.State().(map[string]any)
 if len(state["candidates"].([]Event))!=0 {t.Fatal("healthy/stalled flow shown without a logged error")}
 m.Sweep(context.Background())
 if len(m.decisions)!=0 || len(m.leases)!=0 {t.Fatal("stall triggered routing checks without a logged error")}
}

func TestWebAutomaticApplyNeedsLoggedMemberFailureAndExplicitPreference(t *testing.T){
 m,q,z,d:=webManager(t,200,normalPage)
 s:=m.sources[q.Source];s.AutoApply=true;m.sources[q.Source]=s
 result,err:=m.Probe(context.Background(),q)
 if err!=nil{t.Fatal(err)}
 decision:=result.(Decision)
 if decision.Status!="applied" || decision.Failure==nil || z.calls.Load()!=0 || d.calls.Load()!=2 || len(m.leases)!=1 {t.Fatal(decision)}
 meta:=metadata(q)
 if m.Select(context.Background(),"warp",&meta)!="warp" {t.Fatal("lease stole WARP-owned traffic")}
 missing,q2,z2,d2:=webManager(t,200,normalPage)
 missing.events=map[string]*Event{}
 result,err=missing.Probe(context.Background(),q2)
 if err!=nil || result.(map[string]any)["reason"]!="logged_source_failure_required" || z2.calls.Load()!=0 || d2.calls.Load()!=0{t.Fatal("unlogged connection probed",result,err)}
}

func ipCertificateManager(t *testing.T,valid bool)(*Manager,Query){
 t.Helper();m,q,z,d:=webManager(t,200,normalPage);q.Domain=""
 key,err:=ecdsa.GenerateKey(elliptic.P256(),rand.Reader);if err!=nil{t.Fatal(err)}
 cert:=&x509.Certificate{SerialNumber:big.NewInt(1),NotBefore:time.Now().Add(-time.Hour),NotAfter:time.Now().Add(time.Hour),KeyUsage:x509.KeyUsageDigitalSignature,ExtKeyUsage:[]x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
 if valid{cert.IPAddresses=[]net.IP{net.ParseIP(q.IP)}}else{cert.DNSNames=[]string{"example.com"}}
 der,err:=x509.CreateCertificate(rand.Reader,cert,cert,&key.PublicKey,key);if err!=nil{t.Fatal(err)}
 server:=httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){w.Header().Set("Content-Type","text/html");w.Write([]byte(normalPage))}))
 server.TLS=&tls.Config{Certificates:[]tls.Certificate{{Certificate:[][]byte{der},PrivateKey:key}}};server.StartTLS();t.Cleanup(server.Close)
 pool:=x509.NewCertPool();parsed,err:=x509.ParseCertificate(der);if err!=nil{t.Fatal(err)};pool.AddCert(parsed)
 m.ctx=service.ContextWith[adapter.CertificateStore](m.ctx,&testRoots{pool:pool})
 s:=m.sources[q.Source];s.AutoApply=true;s.AllowIPOnly=true;m.sources[q.Source]=s
 z.address="127.0.0.1:1";d.address=server.Listener.Addr().String()
 meta:=metadata(q);event:=m.Observe(&meta,q.Source);m.Failed(event,errors.New("synthetic IP timeout"))
 return m,q
}

func TestIPOnlyAppliesOnlyWithExplicitOptInAndIPCertificate(t *testing.T){
 m,q:=ipCertificateManager(t,true)
 result,err:=m.Probe(context.Background(),q);if err!=nil{t.Fatal(err)}
 decision:=result.(Decision)
 if decision.Status!="applied" || !decision.IPOnly || decision.DomainKnown || decision.Failure==nil{t.Fatal(decision)}
 meta:=metadata(q)
 if m.Select(context.Background(),q.Source,&meta)!="direct-out"{t.Fatal("verified IP route not used")}
 other:=meta;other.Source=metadata(Query{SourceIP:"192.0.2.99"}).Source
 if m.Select(context.Background(),q.Source,&other)!="direct-out"{t.Fatal("approved section-wide IP missed another device")}
 invalid,badQ:=ipCertificateManager(t,false)
 badResult,err:=invalid.Probe(context.Background(),badQ);if err!=nil{t.Fatal(err)}
 if badResult.(Decision).ApplyAllowed || len(invalid.leases)!=0{t.Fatal("TCP-only or invalid certificate authorized IP route")}
}

func TestOnlyRealLoggedOriginalErrorsAreAdmitted(t *testing.T){
 m,q,_,_:=testManager(t,"fail:");m.events=map[string]*Event{}
 meta:=metadata(q);event:=m.Observe(&meta,q.Source)
 calls:=0;m.LogFailure=func(e Event,err error)bool{calls++;return false}
 m.Failed(event,errors.New("synthetic refused"))
 if len(m.State().(map[string]any)["candidates"].([]Event))!=0 {t.Fatal("unlogged failure admitted")}
 m.LogFailure=func(e Event,err error)bool{calls++;return true}
 m.Failed(event,context.Canceled)
 if calls!=1{t.Fatal("normal cancellation logged as failure")}
 m.Failed(event,errors.New("synthetic refused"))
 rows:=m.State().(map[string]any)["candidates"].([]Event)
 if len(rows)!=1 || rows[0].Failure==nil || rows[0].Failure.ID!=event.ID || rows[0].Failure.SourceID!="s1"{t.Fatal(rows)}
}

func TestDismissDropsOnlySelectedErrorAndDoesNotSuppress(t *testing.T){
 m,q,_,_:=testManager(t,"fail:")
 var event *Event;for _,e:=range m.events{event=e;break}
 if _,err:=m.registryDismiss("foreign",event.ID);err==nil{t.Fatal("foreign delete allowed")}
 if _,err:=m.registryDismiss("s1",event.ID);err!=nil{t.Fatal(err)}
 if len(m.events)!=0 || len(m.suppressed)!=0 || len(m.leases)!=0{t.Fatal("delete changed permissions or retained error")}
 m.Sweep(context.Background())
 if len(m.decisions)!=0{t.Fatal("deleted error was checked again")}
 meta:=metadata(q);next:=m.Observe(&meta,q.Source);m.Failed(next,errors.New("synthetic next failure"))
 if len(m.events)!=1{t.Fatal("deletion permanently hid a fresh failure")}
}
