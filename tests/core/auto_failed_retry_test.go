package autoroute

import (
	"context"
	"testing"
	"time"
)

func TestFailedTransportCheckRetriesAfterCooldownWithoutNewSourceError(t *testing.T) {
	m, q, _, alternative := webManager(t, 200, normalPage)
	healthy := alternative.address
	alternative.address = "127.0.0.1:1"
	source := m.sources[q.Source]
	source.AutoApply = true
	m.sources[q.Source] = source
	answer, err := m.Probe(context.Background(), q)
	if err != nil {
		t.Fatal(err)
	}
	if d := answer.(Decision); d.Status != "inconclusive" || d.Reason != "no_working_alternative" {
		t.Fatalf("unexpected initial result: %+v", d)
	}
	alternative.address = healthy
	calls := alternative.calls.Load()
	for _, e := range m.events {
		e.attempted = true
		e.lastJob = time.Now().Add(-4 * time.Minute)
	}
	m.Sweep(context.Background())
	if alternative.calls.Load() != calls || len(m.leases) != 0 {
		t.Fatal("retry bypassed the five-minute cooldown")
	}
	old := time.Now().Add(-6 * time.Minute)
	for _, e := range m.events {
		e.lastJob = old
	}
	for key := range m.cooldown {
		m.cooldown[key] = old
	}
	m.Sweep(context.Background())
	if len(m.leases) != 1 || alternative.calls.Load() != calls+2 {
		t.Fatalf("recovered alternative remained pending: leases=%d calls=%d", len(m.leases), alternative.calls.Load()-calls)
	}
	for _, lease := range m.leases {
		if !lease.PersistentIP || !lease.AllDevices || !lease.AllPorts {
			t.Fatal("retry changed approval scope")
		}
	}
}
