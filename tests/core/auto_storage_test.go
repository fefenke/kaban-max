package autoroute

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/sagernet/sing-box/option"
	"runtime"
	"strings"
	"testing"
	"time"
)

func fillEssentialBudget(m *Manager) {
	for i := 0; m.essentialBytesLocked() < m.memoryLimit()/2; i++ {
		m.reserved[strings.Repeat("x", 2048)+fmt.Sprint(i)] = true
	}
}

func TestStorageThousandsRestoreAndCleanupKeepGrants(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	source := m.sources[q.Source]
	source.MemoryBytes = 8 << 20
	source.Saved = nil
	for i := 0; i < 2000; i++ {
		l := Lease{ID: fmt.Sprint(i), Owner: "auto-routing", Source: q.Source, SourceID: source.ID, IP: fmt.Sprintf("203.0.%d.%d", i/256, i%256), SourceIP: q.SourceIP, Inbound: q.Inbound, Port: q.Port, Target: "direct-out", Status: "applied", PersistentIP: true, AllPorts: true, IPOnly: true, Created: time.Now().Add(-time.Minute), Failure: &Failure{SourceID: source.ID}}
		raw, _ := json.Marshal(l)
		source.Saved = append(source.Saved, raw)
	}
	runtime.GC()
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	n := New(context.Background(), []option.KabanmaxAutoSource{source})
	defer n.Close()
	n.mu.Lock()
	n.cleanupLocked(time.Now(), true)
	bytes := n.essentialBytesLocked()
	n.mu.Unlock()
	runtime.GC()
	runtime.ReadMemStats(&after)
	runtime.KeepAlive(source)
	t.Logf("2000 routes: accounted=%d heap delta=%d", bytes, int64(after.HeapAlloc)-int64(before.HeapAlloc))
	if len(n.leases) != 2000 {
		t.Fatalf("restoration lost grants: %d", len(n.leases))
	}
	if len(n.State().(map[string]any)["leases"].([]Lease)) != 2000 {
		t.Fatal("state truncated routes")
	}
	if bytes > n.memoryLimit()/2 {
		t.Fatal("admission exceeded essential budget")
	}
	source.MemoryBytes = 1 << 20
	smaller := New(context.Background(), []option.KabanmaxAutoSource{source})
	defer smaller.Close()
	if len(smaller.leases) != 2000 {
		t.Fatal("lowering the budget silently discarded saved routes")
	}
	if smaller.grantRoomLocked(Lease{Source: q.Source, IP: "203.1.1.1", SourceIP: q.SourceIP, Inbound: q.Inbound, Port: q.Port}) {
		t.Fatal("over-budget restore admitted new growth")
	}
}

func TestStoragePressureDropsOldEvidenceButNotGrantsOrExclusions(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	event := manualEvent(m)
	answer, err := manualAPI(m, "s1", event.ID, "direct-out")
	if err != nil {
		t.Fatal(err)
	}
	lease := answer.(Decision).Lease
	key := m.key(q)
	m.suppressed[key] = true
	event.Updated = time.Now().Add(-2 * time.Hour)
	event.Status = "inconclusive"
	event.active = 0
	m.cooldown["expired"] = time.Now().Add(-2 * time.Hour)
	m.mu.Lock()
	m.cleanupLocked(time.Now(), true)
	m.mu.Unlock()
	if len(m.leases) != 1 || m.leases[lease.ID].Target != lease.Target || !m.suppressed[key] {
		t.Fatal("cleanup erased essential routing state")
	}
	if len(m.events) != 0 || len(m.cooldown) != 0 {
		t.Fatal("expired diagnostics retained")
	}
	if _, ok := m.source(q.Source); !ok {
		t.Fatal("cleanup disabled source")
	}
}

func TestStorageLowerBudgetRetainsRestoredRoutesAndFreshErrors(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	answer, err := manualAPI(m, "s1", manualEvent(m).ID, "direct-out")
	if err != nil {
		t.Fatal(err)
	}
	l := answer.(Decision).Lease
	l.Created = time.Now().Add(-3 * time.Hour)
	l.NewError = true
	l.ErrorPort = 5222
	l.Failure = &Failure{ID: "fresh", SourceID: l.SourceID, Message: "fresh failure", At: time.Now()}
	m.leases[l.ID] = l
	m.mu.Lock()
	m.cleanupLocked(time.Now(), true)
	m.mu.Unlock()
	if !m.leases[l.ID].NewError || m.leases[l.ID].Failure.ID != "fresh" {
		t.Fatal("cleanup hid a fresh applied-route error")
	}
	fillEssentialBudget(m)
	if !m.grantRoomLocked(l) {
		t.Fatal("same grant cannot be replaced without growing memory")
	}
	if _, ok := m.source(q.Source); !ok {
		t.Fatal("pressure disabled source")
	}
}

func TestStorageInFlightObservationBudgetIsReleased(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	baseline := m.inFlightBytes
	meta := metadata(q)
	var events []*Event
	for i := 0; i < 10000; i++ {
		event := m.Observe(&meta, q.Source)
		if event == nil {
			break
		}
		events = append(events, event)
	}
	if len(events) == 10000 || len(events) == 0 {
		t.Fatal("in-flight metadata is not bounded")
	}
	for _, event := range events {
		m.Failed(event, nil)
		m.Failed(event, nil)
	}
	if m.inFlightBytes != baseline {
		t.Fatal("completed observations retained memory", m.inFlightBytes)
	}
	if m.Observe(&meta, q.Source) == nil {
		t.Fatal("capacity was not restored")
	}
}

func TestStorageSuccessfulFlowsDoNotReserializeEveryPendingRecord(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	for i := 0; i < 1000; i++ {
		m.events[fmt.Sprint(i)] = &Event{ID: fmt.Sprint(i), Failure: &Failure{Message: "synthetic timeout"}}
	}
	m.transientCached = false
	meta := metadata(q)
	allocations := testing.AllocsPerRun(20, func() {
		e := m.Observe(&meta, q.Source)
		if e == nil {
			t.Fatal("unexpected admission failure")
		}
		m.Failed(e, nil)
	})
	t.Logf("successful flow with 1000 pending records: %.0f allocations", allocations)
	if allocations > 150 {
		t.Fatal("successful flow reserialized the pending registry", allocations)
	}
}
