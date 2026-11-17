package autoroute

import (
	"context"
	"encoding/json"
	"fmt"
 "net/netip"
	"github.com/sagernet/sing-box/option"
	"testing"
	"time"
)

func TestRegistryExactCandidateExcludeReset(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	meta := metadata(q)
	event := m.Observe(&meta, q.Source)
	m.Failed(event,fmt.Errorf("synthetic logged failure"))
	otherQuery := q
	otherQuery.SourceIP = "192.0.2.55"
	otherKey := m.key(otherQuery)
	m.decisions["other-proof"] = Decision{Lease: Lease{Source: q.Source, SourceID: "s1", SourceIP: otherQuery.SourceIP, IP: q.IP, Domain: q.Domain, Inbound: q.Inbound, Port: q.Port}, Scope: otherKey, Generation: m.generation, ApplyAllowed: true}
	call := func(op, source, id, scope string) error {
		raw, _ := json.Marshal(map[string]any{"op": op, "source_id": source, "id": id, "scope": scope})
		_, err := m.API(context.Background(), raw)
		return err
	}
	if call("registry_exclude", "other", event.ID, "") == nil {
		t.Fatal("foreign source accepted")
	}
	if err := call("registry_exclude", "s1", event.ID, ""); err != nil {
		t.Fatal(err)
	}
	if !m.suppressed[m.key(q)] {
		t.Fatal("exact candidate scope not suppressed")
	}
	if d := m.decisions["other-proof"]; d.Generation != m.generation || !d.ApplyAllowed {
		t.Fatal("exclusion invalidated a different device scope")
	}
	other := q
	other.SourceIP = "192.0.2.9"
	other.Port = 8443
	m.suppressed[m.key(other)] = true
	if call("registry_reset", "other", "", m.key(q)) == nil {
		t.Fatal("foreign reset accepted")
	}
	if err := call("registry_reset", "s1", "", m.key(q)); err != nil {
		t.Fatal(err)
	}
	if m.suppressed[m.key(q)] || !m.suppressed[m.key(other)] || len(m.leases) != 0 {
		t.Fatal("reset crossed scope or installed a lease")
	}
}

func TestRegistryExpiredAndOrdinarySavedIntentsDoNotAuthorize(t *testing.T) {
	for _, ordinary := range []bool{false, true} {
		m, q, _, _ := testManager(t, "fail:")
		if ordinary {
			m, q, _, _ = webManager(t, 200, normalPage)
		}
		source := m.sources[q.Source]
		source.AutoApply = false
		saved := Lease{Owner: "auto-routing", Source: q.Source, SourceID: "s1", IP: q.IP, Domain: q.Domain, DomainKnown: true, SourceIP: q.SourceIP, Inbound: q.Inbound, Port: q.Port, Target: "direct-out", Created: time.Now().Add(-time.Minute), Expires: time.Now().Add(-time.Second)}
		if ordinary {
			saved.Expires = time.Now().Add(time.Minute)
		}
		raw, _ := json.Marshal(map[string]any{"saved": []Lease{saved}})
		_ = json.Unmarshal(raw, &source)
		n := New(m.ctx, []option.KabanmaxAutoSource{source})
		n.Match = m.Match
		n.Lookup = m.Lookup
		n.Outbound = m.Outbound
		meta := metadata(q)
		event := n.Observe(&meta, q.Source)
		event.Status = "detected"
		n.Sweep(context.Background())
		if len(n.leases) != 0 {
			t.Fatal("expired or ordinary approval was automatically restored")
		}
	}
}

func TestRegistryReservedCapacityRejectsWithoutEviction(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	for i := 0; i < 64; i++ {
		m.reserved[fmt.Sprint(i)] = true
	}
	result, err := m.Probe(context.Background(), q)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = m.Apply(context.Background(), result.(Decision).ID); err == nil {
		t.Fatal("persistent capacity bypassed")
	}
	if len(m.reserved) != 64 || len(m.leases) != 0 {
		t.Fatal("capacity failure evicted or installed data")
	}
	for i := 0; i < 70; i++ {
		meta := metadata(q)
		meta.Source.Port = uint16(1000 + i)
 meta.Source.Addr=netip.MustParseAddr(fmt.Sprintf("192.0.2.%d",i+10))
		event:=m.Observe(&meta, q.Source)
		m.Failed(event,fmt.Errorf("synthetic capacity-test connection failure"))
	}
	if len(m.events) != 64 {
		t.Fatal("observation RAM limit not enforced")
	}
}

func TestRegistrySuppressionLimitDoesNotEvict(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	meta := metadata(q)
	event := m.Observe(&meta, q.Source)
	for i := 0; i < 64; i++ {
		m.suppressed[time.Unix(int64(i), 0).String()] = true
	}
	raw, _ := json.Marshal(map[string]any{"op": "registry_exclude", "source_id": "s1", "id": event.ID})
	if _, err := m.API(context.Background(), raw); err == nil {
		t.Fatal("limit not enforced")
	}
	if len(m.suppressed) != 64 || m.suppressed[m.key(q)] {
		t.Fatal("limit silently evicted or inserted")
	}
}

func TestRegistrySavedStrictLeaseRequiresFreshVerification(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	saved := Lease{Owner: "auto-routing", Source: q.Source, SourceID: "s1", IP: q.IP, Domain: q.Domain, DomainKnown: true, SourceIP: q.SourceIP, Inbound: q.Inbound, Port: q.Port, Target: "direct-out", Created: time.Now().Add(-time.Second), Expires: time.Now().Add(30 * time.Second)}
	source := m.sources[q.Source]
	raw, _ := json.Marshal(map[string]any{"saved": []Lease{saved}})
	if err := json.Unmarshal(raw, &source); err != nil {
		t.Fatal(err)
	}
	restored := New(m.ctx, []option.KabanmaxAutoSource{source})
	restored.Match = m.Match
	restored.Lookup = m.Lookup
	restored.Outbound = m.Outbound
	restored.LogFailure=m.LogFailure
	if len(restored.leases) != 0 {
		t.Fatal("saved data activated without verification")
	}
	restored.Sweep(context.Background())
	if len(restored.leases) != 0 {
		t.Fatal("restored without a fresh flow")
	}
	meta := metadata(q)
	event := restored.Observe(&meta, q.Source)
	restored.Failed(event,fmt.Errorf("synthetic fresh logged failure"))
	restored.Sweep(context.Background())
	if len(restored.leases) != 1 {
		t.Fatal("verified strict saved intent was not restored")
	}
	for _, lease := range restored.leases {
		if lease.Expires.After(saved.Expires) {
			t.Fatal("restore extended original TTL")
		}
	}
}
