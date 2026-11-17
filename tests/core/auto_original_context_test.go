package autoroute

import (
	"context"
	"errors"
	"net/netip"
	"testing"

	"github.com/sagernet/sing-box/adapter"
)

func TestIPScopeRetainsAttestedOriginalConnectionContext(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	m.events = map[string]*Event{}
	q.SourcePort = 49152
	meta := metadata(q)
	meta.Protocol = ""
	meta.SourceHostname = "synthetic-device"
	event := m.Observe(&meta, q.Source)
	m.Failed(event, errors.New("synthetic original timeout"))
	m.Lookup = func(context.Context, string) ([]netip.Addr, uint32, error) {
		return []netip.Addr{netip.MustParseAddr("203.0.113.99")}, 60, nil
	}
	bound := m.bindDomain(context.Background(), event.Query)
	m.Match = func(ctx context.Context, got *adapter.InboundContext) (string, error) {
		if got.Protocol != "" || got.Source.Port != 49152 || got.SourceHostname != "synthetic-device" || got.Destination.Fqdn != q.Domain {
			return "", errors.New("probe_scope_requires_connection_metadata")
		}
		return q.Source, nil
	}
	if _, err := m.guard(context.Background(), bound); err != nil {
		t.Fatalf("attested original metadata lost: %v", err)
	}
	if event.ObservedDomain != q.Domain {
		t.Fatal("logged domain not retained for display")
	}
	m.Match = func(context.Context, *adapter.InboundContext) (string, error) { return "direct-out", nil }
	if _, err := m.guard(context.Background(), bound); err == nil {
		t.Fatal("recorded metadata bypassed current first-match ownership")
	}
}

func TestReconstructedQueryCannotClaimOriginalMetadata(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	m.Match = func(ctx context.Context, _ *adapter.InboundContext) (string, error) {
		if HasOriginalMetadata(ctx) {
			return q.Source, nil
		}
		return "", errors.New("probe_scope_requires_connection_metadata")
	}
	m.mu.Lock()
	for _, event := range m.events {
		event.originalMetadata = nil
	}
	m.mu.Unlock()
	if _, err := m.guard(context.Background(), q); err == nil {
		t.Fatal("reconstructed query claimed unavailable original context")
	}
}

func TestOriginalSnapshotOwnsProcessPackageNames(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage)
 m.events=map[string]*Event{}
 meta:=metadata(q)
 meta.ProcessInfo=&adapter.ConnectionOwner{AndroidPackageNames:[]string{"synthetic.original"}}
 event:=m.Observe(&meta,q.Source)
 meta.ProcessInfo.AndroidPackageNames[0]="synthetic.changed"
 m.Failed(event,errors.New("synthetic failure"))
 snapshot:=m.originalForQuery(event.Query)
 if snapshot==nil || snapshot.ProcessInfo.AndroidPackageNames[0]!="synthetic.original"{t.Fatal("caller mutation changed original process context")}
}

func TestOriginalSnapshotKeepsProtectedDomainGuardAfterIPScope(t *testing.T) {
 m,q,_,_:=webManager(t,200,normalPage)
 m.events=map[string]*Event{}
 meta:=metadata(q);event:=m.Observe(&meta,q.Source)
 m.Failed(event,errors.New("synthetic failure"))
 m.Lookup=func(context.Context,string)([]netip.Addr,uint32,error){return []netip.Addr{netip.MustParseAddr("203.0.113.99")},60,nil}
 bound:=m.bindDomain(context.Background(),event.Query)
 s:=m.sources[q.Source];s.Protected=[]string{q.Domain};m.sources[q.Source]=s
 if _,err:=m.guard(context.Background(),bound);err==nil{t.Fatal("IP scope discarded protected observed domain")}
}
