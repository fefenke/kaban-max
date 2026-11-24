package autoroute

import (
	"context"
	"encoding/json"
	"github.com/sagernet/sing-box/option"
	"net/netip"
	"testing"
	"time"
)

func TestSuccessfulDecisionDoesNotExpireOrRestartAutomaticChecks(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	answer, err := m.Probe(context.Background(), q)
	if err != nil {
		t.Fatal(err)
	}
	d := answer.(Decision)
	if d.Status != "proposed" {
		t.Fatalf("missing verified alternative: %+v", d)
	}
	d.Deadline = time.Now().Add(-time.Second)
	d.Expires = d.Deadline
	m.decisions[d.ID] = d
	m.mu.Lock()
	m.cleanupLocked(time.Now(), false)
	m.mu.Unlock()
	if _, ok := m.decisions[d.ID]; !ok {
		t.Fatal("TTL deleted the last successful diagnostic")
	}
	snapshot := m.State().(map[string]any)["decisions"].([]Decision)
	if len(snapshot) != 1 || snapshot[0].Status != "proposed" || snapshot[0].Target != d.Target || len(snapshot[0].Attempts) == 0 || snapshot[0].ApplyAllowed || snapshot[0].AutoApplyEligible {
		t.Fatalf("incorrect expired diagnostic: %+v", snapshot)
	}
	_, _ = m.Apply(context.Background(), d.ID)
	if len(m.leases) != 0 {
		t.Fatal("expired diagnostic granted a route")
	}
	d.Created = time.Now().Add(-m.retention() - time.Second)
	m.decisions[d.ID] = d
	m.mu.Lock()
	m.cleanupLocked(time.Now(), false)
	m.mu.Unlock()
	if len(m.decisions) != 1 {
		t.Fatal("unreviewed successful result disappeared")
	}
	meta := metadata(q)
	next := m.Observe(&meta, q.Source)
	if next == nil {
		t.Fatal("missing later original flow")
	}
	m.Failed(next, context.DeadlineExceeded)
	if next.Status != "proposed" || !next.attempted || m.decisions[d.ID].Target != d.Target {
		t.Fatal("later original failure erased the successful check")
	}
	for _, e := range m.events {
		e.Updated = d.Created
		e.attempted = false
		e.lastJob = d.Created
	}
	saved := m.checkpoint()
	raw, _ := json.Marshal(saved[0])
	source := m.sources[q.Source]
	source.Pending = []json.RawMessage{raw}
	restored := New(context.Background(), []option.KabanmaxAutoSource{source})
	defer restored.Close()
	if len(restored.events) != 1 || len(restored.decisions) != 1 {
		t.Fatal("restart lost pending result", len(restored.events), len(restored.decisions))
	}
	restored.Lookup = func(context.Context, string) ([]netip.Addr, uint32, error) {
		t.Fatal("successful result automatically rechecked")
		return nil, 0, nil
	}
	restored.Sweep(context.Background())
	_, err = restored.registryDismiss(source.ID, saved[0].ID)
	if err != nil || len(restored.events) != 0 || len(restored.decisions) != 0 {
		t.Fatal("explicit removal did not clear result", err)
	}
}
