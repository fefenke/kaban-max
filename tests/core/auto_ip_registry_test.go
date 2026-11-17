package autoroute

import (
 "context"
 "encoding/json"
 "errors"
 "net/netip"
 "testing"
 "time"
 "github.com/sagernet/sing-box/option"
 "github.com/sagernet/sing-box/adapter"
)

func TestRepeatedIPFailureKeepsRecordAndDomains(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage)
 m.events=map[string]*Event{}
 meta:=metadata(q); first:=m.Observe(&meta,q.Source); m.Failed(first,errors.New("timeout"))
 for i:=0;i<80;i++ { meta:=metadata(q); meta.Destination.Fqdn="another.example"; e:=m.Observe(&meta,q.Source); m.Failed(e,errors.New("timeout")) }
 if len(m.events)!=1 || m.events[first.ID]==nil {t.Fatalf("record replaced by duplicate failures: %d",len(m.events))}
 if _,err:=manualAPI(m,"s1",first.ID,"direct-out");err!=nil {t.Fatal("single apply lost record",err)}
}

func TestDisabledCollectionKeepsCheckpointedManualActions(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage)
 event:=manualEvent(m);source:=m.sources[q.Source];source.CollectDisabled=true
 for _,saved:=range m.checkpoint() {raw,_:=json.Marshal(saved);source.Pending=append(source.Pending,raw)}
 restored:=New(context.Background(),[]option.KabanmaxAutoSource{source});defer restored.Close()
 restored.Outbound=m.Outbound;restored.Lookup=m.Lookup;restored.Match=m.Match;restored.LogFailure=m.LogFailure
 meta:=metadata(q)
 observation:=restored.Observe(&meta,q.Source)
 if observation==nil {t.Fatal("manual routing still needs ephemeral dial context with collection disabled")}
 restored.Failed(observation,errors.New("ignored disabled failure"));if len(restored.events)!=1 {t.Fatal("disabled collection admitted a new record")}
 restored.Sweep(context.Background());if len(restored.decisions)!=0 {t.Fatal("disabled collection ran checks")}
 if _,err:=manualAPI(restored,"s1",event.ID,"direct-out");err!=nil {t.Fatal("disabled collection blocked single manual apply",err)}
}

func TestPersistentIPRestoresAndReportsNewAlternativeError(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage)
 answer,err:=manualAPI(m,"s1",manualEvent(m).ID,"direct-out");if err!=nil {t.Fatal(err)}
 d:=answer.(Decision);raw,_:=json.Marshal(d.Lease);source:=m.sources[q.Source];source.Saved=[]json.RawMessage{raw}
 restored:=New(context.Background(),[]option.KabanmaxAutoSource{source});defer restored.Close()
 restored.Outbound=m.Outbound;restored.Lookup=m.Lookup;restored.Match=m.Match;restored.LogFailure=m.LogFailure
 meta:=metadata(q);event:=restored.Observe(&meta,q.Source)
 if restored.SelectForEvent(context.Background(),q.Source,&meta,event)!="direct-out" {t.Fatal("saved applied IP was not restored")}
 restored.Failed(event,errors.New("new alternative timeout"))
 lease:=restored.leases[d.ID]
 if !lease.NewError || lease.Status!="applied" || len(restored.events)!=0 {t.Fatalf("alternative failure became a pending Zapret event: %+v",lease)}
}

func TestRegistryOverflowDoesNotInvalidateShownIDs(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage);first:=manualEvent(m).ID
 for i:=0;i<64;i++ {meta:=metadata(q);meta.Source.Addr=netip.AddrFrom4([4]byte{192,0,2,byte(i+20)});event:=m.Observe(&meta,q.Source);m.Failed(event,errors.New("unique device timeout"))}
 if len(m.events)!=64 || m.events[first]==nil || m.RegistryOverflow!=1 {t.Fatal("full registry evicted a shown ID",len(m.events),m.RegistryOverflow)}
 if _,err:=manualAPI(m,"s1",first,"direct-out");err!=nil {t.Fatal(err)}
}

func TestLoggedFailureChecksAlternativeEvenWhenOriginalNowResponds(t *testing.T) {
 m,q,z,d:=webManager(t,200,normalPage); z.address=d.address
 result,err:=m.Probe(context.Background(),q)
 if err!=nil {t.Fatal(err)}
 if result.(Decision).Status!="proposed" || d.calls.Load()!=2 {t.Fatalf("logged failure never tested alternative: %+v",result)}
}

func TestManualIPRouteSurvivesMinuteAndOtherDomain(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage)
 answer,err:=manualAPI(m,"s1",manualEvent(m).ID,"direct-out");if err!=nil {t.Fatal(err)}
 d:=answer.(Decision); l:=m.leases[d.ID];l.Deadline=time.Now().Add(-time.Second);m.leases[d.ID]=l
 meta:=metadata(q);meta.Destination.Fqdn="another.example"
 if got:=m.Select(context.Background(),q.Source,&meta);got!="direct-out" {t.Fatal("applied IP fell back",got)}
 found:=false;for _,name:=range m.leases[d.ID].Domains {if name=="another.example" {found=true}};if !found {t.Fatal("applied IP did not collect the new observed domain")}
 meta.DestinationAddresses=[]netip.Addr{netip.MustParseAddr("203.0.113.99")}
 if got:=m.Select(context.Background(),q.Source,&meta);got!=q.Source {t.Fatal("different IP escaped",got)}
}

func TestDNSRotationRetainsLoggedTLSName(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage)
 m.Lookup=func(context.Context,string)([]netip.Addr,uint32,error){return []netip.Addr{netip.MustParseAddr("203.0.113.99")},60,nil}
 result,err:=m.Probe(context.Background(),q);if err!=nil {t.Fatal(err)}
 if result.(Decision).Status!="proposed" {t.Fatalf("lost SNI after DNS rotation: %+v",result)}
}

func TestExplicitManualChoiceDoesNotExpireRecordedIP(t *testing.T) {
 m,_,_,_:=webManager(t,200,normalPage);event:=manualEvent(m);event.Failure.At=time.Now().Add(-24*time.Hour)
 if _,err:=manualAPI(m,"s1",event.ID,"direct-out");err!=nil {t.Fatal("manual IP choice incorrectly requires a fresh check",err)}
}

func TestIPExclusionCoversNewDomainsAndKeepsOtherDevices(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage);denied:=q;denied.Domain="";key:=m.key(denied)
 if _,err:=m.registrySuppress("s1",key);err!=nil {t.Fatal(err)}
 meta:=metadata(q);meta.Destination.Fqdn="other.example";event:=m.Observe(&meta,q.Source);m.Failed(event,errors.New("another domain timeout"))
 if _,err:=manualAPI(m,"s1",event.ID,"direct-out");err==nil {t.Fatal("new domain escaped IP exclusion")}
 neighbour:=q;neighbour.SourceIP="192.0.2.99";meta=metadata(neighbour);event=m.Observe(&meta,q.Source);m.Failed(event,errors.New("other device timeout"))
 if _,err:=manualAPI(m,"s1",event.ID,"direct-out");err!=nil {t.Fatal("IP exclusion captured another device",err)}
 if _,err:=m.registryReset("s1",key);err!=nil {t.Fatal(err)}
}

func TestLegacyExplicitManualRouteMigratesWithoutAnotherCheck(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage);answer,err:=manualAPI(m,"s1",manualEvent(m).ID,"direct-out");if err!=nil {t.Fatal(err)}
 saved:=answer.(Decision).Lease;saved.PersistentIP=false;saved.Expires=time.Now().Add(-time.Minute)
 raw,_:=json.Marshal(saved);source:=m.sources[q.Source];source.Saved=[]json.RawMessage{raw}
 restored:=New(context.Background(),[]option.KabanmaxAutoSource{source});defer restored.Close();restored.Outbound=m.Outbound;restored.Lookup=m.Lookup;restored.Match=m.Match
 meta:=metadata(q);if restored.Select(context.Background(),q.Source,&meta)!="direct-out" {t.Fatal("previous explicit manual IP choice was lost during upgrade")}
}

func TestManualApplyPinsContextWhileNewFailuresArrive(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage);source:=m.sources[q.Source];source.Protected=[]string{"infra.example"};m.sources[q.Source]=source
 first:=manualEvent(m);changed:=false
 m.Lookup=func(_ context.Context,name string)([]netip.Addr,uint32,error){
  if name=="infra.example" && !changed {changed=true;meta:=metadata(q);meta.Source.Port=50001;meta.Destination.Fqdn="new.example";event:=m.Observe(&meta,q.Source);m.Failed(event,errors.New("concurrent timeout"))}
  return []netip.Addr{netip.MustParseAddr("203.0.113.99")},60,nil
 }
 m.Match=func(ctx context.Context,_ *adapter.InboundContext)(string,error){if !HasOriginalMetadata(ctx){return "",errors.New("missing pinned original context")};return q.Source,nil}
 if _,err:=manualAPI(m,"s1",first.ID,"direct-out");err!=nil {t.Fatal("incoming failures invalidated the manual operation",err)}
}

func TestNewDomainOnSameIPDoesNotResetProbeBudget(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage)
 if _,err:=m.Probe(context.Background(),q);err!=nil {t.Fatal(err)}
 meta:=metadata(q);meta.Destination.Fqdn="another.example";event:=m.Observe(&meta,q.Source);m.Failed(event,errors.New("same IP new domain timeout"))
 if _,err:=m.Probe(context.Background(),event.Query);err==nil || err.Error()!="cooldown" {t.Fatal("new domain bypassed IP cooldown",err)}
}
