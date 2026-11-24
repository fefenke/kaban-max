package autoroute

import (
 "context"
 "errors"
 "testing"
)

func TestAppliedRouteKeepsOriginalFailureAfterTargetError(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage)
 answer,err:=manualAPI(m,"s1",manualEvent(m).ID,"direct-out");if err!=nil{t.Fatal(err)}
 grant:=answer.(Decision).Lease
 if grant.OriginalFailure==nil || grant.OriginalFailure.Message==""{t.Fatal("original failure missing at apply")}
 original:=*grant.OriginalFailure
 meta:=metadata(q);event:=m.Observe(&meta,q.Source)
 if m.SelectForEvent(context.Background(),q.Source,&meta,event)!="direct-out"{t.Fatal("grant not selected")}
 m.Failed(event,errors.New("later alternative failure"))
 current:=m.leases[grant.ID]
 if current.OriginalFailure==nil || *current.OriginalFailure!=original || current.Failure.Message==original.Message{t.Fatal("original failure overwritten")}
}

func TestReappliedIPKeepsObservedLabelsFromPreviousApproval(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage)
 answer,err:=manualAPI(m,"s1",manualEvent(m).ID,"direct-out");if err!=nil{t.Fatal(err)}
 old:=answer.(Decision).Lease;old.Domains=[]string{"observed.example"};m.leases[old.ID]=old
 next:=Decision{Lease:old};next.ID="replacement";next.Domain="";next.Domains=nil;next.SourceIP="192.0.2.99"
 m.mu.Lock();m.persistentIP(&next);m.mu.Unlock()
 found:=false;for _,name:=range next.Domains{if name=="observed.example"{found=true}}
 if !found{t.Fatal("reapplying IP lost observed labels")}
 if next.Source!=q.Source{t.Fatal("scope changed")}
}
