package autoroute

import (
 "context"
 "errors"
 "testing"
 "net/netip"
)

func TestAppliedIPRoutesOtherPortsAndReportsTheirFailures(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage);e:=manualEvent(m)
 if _,err:=manualAPI(m,"s1",e.ID,"direct-out");err!=nil{t.Fatal(err)}
 for _,network:=range []string{"tcp","udp"}{
  other:=q;other.Port=5222;meta:=metadata(other);meta.Network=network
  event:=m.Observe(&meta,q.Source)
  if got:=m.SelectForEvent(context.Background(),q.Source,&meta,event);got!="direct-out"{t.Fatalf("%s 5222 bypassed applied IP: %s",network,got)}
  m.Failed(event,errors.New("failure of applied route on5222"))
  for _,l:=range m.leases{if !l.NewError{t.Fatal("other-port error hidden")}}
  meta.Source.Port++
  meta.Source.Addr=netip.MustParseAddr("192.0.2.99")
  if got:=m.SelectForEvent(context.Background(),q.Source,&meta,nil);got!="direct-out"{t.Fatal("section-wide IP missed another device")}
 }
}

func TestUnknownNativeProtocolIsNotTreatedAsHTTPS(t *testing.T){
 m,q,_,direct:=webManager(t,200,normalPage)
 for _,e:=range m.events{e.originalMetadata.Protocol="";e.originalMetadata.SniffedALPN=nil}
 answer,err:=m.Probe(context.Background(),q);if err!=nil{t.Fatal(err)}
 d:=answer.(Decision)
 if d.Status=="proposed"||d.Reason!="protocol_unconfirmed"||direct.calls.Load()!=0{t.Fatal("unknown protocol was checked as HTTPS",d)}
}

func TestIPExclusionCoversOtherPortsWithoutCrossingDeviceScope(t *testing.T){
 m,q,_,_:=webManager(t,200,normalPage);blank:=q;blank.Domain="";m.suppressed[m.key(blank)]=true
 q.Port=5222
 if !m.deniedScope(q){t.Fatal("IP exclusion missed another port")}
 q.SourceIP="192.0.2.99";if m.deniedScope(q){t.Fatal("IP exclusion crossed device boundary")}
}
