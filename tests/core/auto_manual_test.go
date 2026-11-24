package autoroute

import (
	"context"
	"encoding/json"
	"github.com/sagernet/sing-box/adapter"
	"net/netip"
	"testing"
	"time"
)

func manualEvent(m *Manager) *Event {
	for _, e := range m.events {
		return e
	}
	return nil
}
func manualAPI(m *Manager, source, record, target string) (any, error) {
	raw, _ := json.Marshal(map[string]string{"op": "manual_apply", "source_id": source, "id": record, "target": target})
	return m.API(context.Background(), raw)
}
func TestManualApplyInconclusive(t *testing.T) {
	m, q, z, d := testManager(t, "fail:")
	event := manualEvent(m)
	event.Status = "inconclusive"
	answer, err := manualAPI(m, "s1", event.ID, "direct-out")
	if err != nil {
		t.Fatal(err)
	}
	decision := answer.(Decision)
	if decision.Status != "applied" || decision.Target != "direct-out" || decision.Evidence != "manual_user_choice" || decision.AutoApplyEligible || decision.Failure.ID != event.ID {
		t.Fatalf("invalid manual result: %+v", decision)
	}
	if z.calls.Load() != 0 || d.calls.Load() != 0 {
		t.Fatal("manual choice probed network")
	}
	meta := metadata(q)
	if got := m.Select(context.Background(), q.Source, &meta); got != "direct-out" {
		t.Fatal(got)
	}
	for _, change := range []func(*Query){func(v *Query) { v.IP = "203.0.113.8" }, func(v *Query) { v.SourceIP = "192.0.2.9" }, func(v *Query) { v.Inbound = "system-in" }, func(v *Query) { v.Port = 444 }} {
		sibling := q
		change(&sibling)
		meta = metadata(sibling)
		if got := m.Select(context.Background(), q.Source, &meta); got != q.Source {
			t.Fatal("sibling escaped scope", sibling, got)
		}
	}
}
func TestManualApplyRejectsUnauthorizedRecords(t *testing.T) {
	for _, kind := range []string{"foreign", "missing", "future", "suppressed", "target", "source_target", "dns", "first_match", "protected"} {
		t.Run(kind, func(t *testing.T) {
			m, q, _, _ := testManager(t, "fail:")
			event := manualEvent(m)
			source, target := "s1", "direct-out"
			switch kind {
			case "foreign":
				source = "other"
			case "missing":
				event.Failure = nil
			case "future":
				event.Failure.At = time.Now().Add(2 * time.Hour)
			case "suppressed":
				m.suppressed[m.key(q)] = true
			case "target":
				target = "vpn"
			case "source_target":
				target = q.Source
			case "dns":
				q.IP = "203.0.113.99"
				event.Query = q
			case "first_match":
				s := m.sources[q.Source]
				s.ExcludedSystem = true
				m.sources[q.Source] = s
				event.Inbound = "system-in"
			case "protected":
				event.Domain = "example.ru"
			}
			if _, err := manualAPI(m, source, event.ID, target); err == nil {
				t.Fatal("unauthorized manual apply accepted")
			}
			if len(m.leases) != 0 {
				t.Fatal("lease granted")
			}
		})
	}
}

func TestManualApplyChosenWARPAndDecisionID(t *testing.T) {
	m, q, _, direct := testManager(t, "fail:")
	warp := &testOutbound{tag: "warp-section", kind: "warp", address: direct.address}
	original := m.Outbound
	m.Outbound = func(tag string) (adapter.Outbound, bool) {
		if tag == warp.tag {
			return warp, true
		}
		return original(tag)
	}
	s := m.sources[q.Source]
	s.WARP = warp.tag
	s.WARPSection = "chosen-section"
	m.sources[q.Source] = s
	event := manualEvent(m)
	m.decisions["inconclusive"] = Decision{Lease: Lease{SourceID: "s1", Failure: event.Failure}, Scope: m.key(q)}
	answer, err := manualAPI(m, "s1", "inconclusive", warp.tag)
	if err != nil {
		t.Fatal(err)
	}
	d := answer.(Decision)
	if d.Target != warp.tag || d.TargetSection != "chosen-section" || d.AutoApplyEligible {
		t.Fatalf("wrong chosen direction: %+v", d)
	}
	if _, err = manualAPI(m, "s1", event.ID, "direct-out"); err != nil {
		t.Fatal(err)
	}
	if len(m.leases) != 1 {
		t.Fatal("same scope lease not replaced")
	}
}
func TestManualApplyPreservesBoundIPOnlyScope(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	s := m.sources[q.Source]
	s.Mode = "web"
	s.Domain = ""
	m.sources[q.Source] = s
	event := manualEvent(m)
	event.ObservedDomain = event.Domain
	event.Domain = ""
	original := event.Query
	answer, err := manualAPI(m, "s1", event.ID, "direct-out")
	if err != nil {
		t.Fatal(err)
	}
	d := answer.(Decision)
	if !d.IPOnly || d.Domain != "" || event.Query != original || d.DomainKnown {
		t.Fatal("manual apply rebound event identity")
	}
	sibling := metadata(original)
	sibling.DestinationAddresses = []netip.Addr{netip.MustParseAddr("203.0.113.8")}
	sibling.Destination.Addr = netip.MustParseAddr("203.0.113.8")
	if m.Select(context.Background(), q.Source, &sibling) != q.Source {
		t.Fatal("healthy sibling routed")
	}
}

func TestManualApplyCancellationAndRegistryBudget(t *testing.T) {
	for _, kind := range []string{"cancel", "budget"} {
		t.Run(kind, func(t *testing.T) {
			m, q, _, _ := testManager(t, "fail:")
			event := manualEvent(m)
			if kind == "budget" {
				fillEssentialBudget(m)
			} else {
				lookup := m.Lookup
				m.Lookup = func(ctx context.Context, name string) ([]netip.Addr, uint32, error) {
					m.mu.Lock()
					m.registryAdvance(m.key(q))
					m.mu.Unlock()
					return lookup(ctx, name)
				}
			}
			if _, err := manualAPI(m, "s1", event.ID, "direct-out"); err == nil {
				t.Fatal("grant escaped cancellation/budget")
			}
			if len(m.leases) != 0 {
				t.Fatal("failed apply changed leases")
			}
		})
	}
}
