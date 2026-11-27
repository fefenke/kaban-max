package group

import (
	"testing"
	"time"
)

func TestFallbackProbeBudgetUsesDialAttemptsNotHealthTimeout(t *testing.T) {
	a, b := newFallbackHealthTestOutbound("primary", true), newFallbackHealthTestOutbound("backup", true)
	s := stableTestGroup(t, a, b)
	s.timeout = 2 * time.Second
	s.attemptTimeout = 8 * time.Second
	if got := s.KabanmaxProbeDialTimeout(); got != 8*time.Second {
		t.Fatalf("stable dial budget=%s", got)
	}
	s.stable = nil
	if got := s.KabanmaxProbeDialTimeout(); got != 16*time.Second {
		t.Fatalf("serial candidate budget=%s", got)
	}
}
