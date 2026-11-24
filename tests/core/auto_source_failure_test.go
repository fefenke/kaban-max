package autoroute

import (
	"errors"
	"testing"
)

func TestEveryAcceptedSourceFailureIsVisible(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	m.events = map[string]*Event{}
	count := 0
	m.LogSourceFailure = func(e Event, err error) { count++ }
	fail := func(query Query) *Event {
		meta := metadata(query)
		e := m.Observe(&meta, query.Source)
		if e == nil {
			t.Fatal("missing attributed event")
		}
		m.Failed(e, errors.New("synthetic connection timeout"))
		return e
	}
	first := fail(q)
	m.Failed(first, errors.New("synthetic connection timeout"))
	fail(q)
	if count != 2 {
		t.Fatalf("repeated source failure logged %d times", count)
	}
	neighbor := q
	neighbor.IP = "203.0.113.8"
	fail(neighbor)
	if count != 3 {
		t.Fatalf("neighbor hidden: %d", count)
	}
	m.LogFailure = func(Event, error) bool { return false }
	neighbor.IP = "203.0.113.9"
	fail(neighbor)
	if count != 3 {
		t.Fatalf("unaccepted failure logged: %d", count)
	}
	m.LogFailure = func(Event, error) bool { return true }
	meta := metadata(neighbor)
	alternative := m.Observe(&meta, neighbor.Source)
	if alternative == nil {
		t.Fatal("missing alternative event")
	}
	alternative.routedLease, alternative.routedTarget = "synthetic-lease", "WARP"
	m.Failed(alternative, errors.New("synthetic connection timeout"))
	if count != 3 {
		t.Fatalf("alternative mislabeled as source failure: %d", count)
	}
}
