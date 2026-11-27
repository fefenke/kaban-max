package group

import (
	"bytes"
	"context"
	"errors"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/sagernet/sing-box/log"
	M "github.com/sagernet/sing/common/metadata"
)

func partialFailureGroup(t *testing.T, primaryOK, backupOK *bool) *Fallback {
	t.Helper()
	nodes := make([]fallbackCandidate, 0, 2)
	for i, ok := range []*bool{primaryOK, backupOK} {
		tag := []string{"primary", "backup"}[i]
		node := &stableTrafficOutbound{fallbackHealthTestOutbound: newFallbackHealthTestOutbound(tag, true)}
		node.dial = func(ctx context.Context, network string, dst M.Socksaddr) (net.Conn, error) {
			if dst.Fqdn == "health.test" && !*ok {
				return nil, errors.New("primary service unavailable")
			}
			return node.fallbackHealthTestOutbound.DialContext(ctx, network, dst)
		}
		nodes = append(nodes, fallbackCandidate{tag: tag, outbound: node})
	}
	return stableCandidateGroup(t, nodes...)
}

func TestStableConfirmationSuccessKeepsActiveWithoutWarning(t *testing.T) {
	primary, backup := false, true
	s := partialFailureGroup(t, &primary, &backup)
	var output bytes.Buffer
	factory := log.NewDefaultFactory(context.Background(), log.Formatter{DisableColors: true}, &output, "", nil, false)
	if err := factory.Start(); err != nil {
		t.Fatal(err)
	}
	defer factory.Close()
	factory.SetLevel(log.LevelWarn)
	s.logger = factory.NewLogger("fallback")
	s.checkOutbounds(context.Background(), 0)
	if selectedTag(s) != "primary" {
		t.Fatal("single observation switched selection")
	}
	if strings.Contains(output.String(), "WARN") {
		t.Fatalf("successful confirmation produced a health warning: %s", output.String())
	}
	s.access.Lock()
	s.stable.confirmAfter = time.Time{}
	s.access.Unlock()
	s.checkOutbounds(context.Background(), 0)
	if selectedTag(s) != "primary" || s.StableStatus().State != "primary" {
		t.Fatalf("successful confirmation did not preserve healthy primary: %+v", s.StableStatus())
	}
	for _, member := range s.StableStatus().Stats.Members {
		if member.FailedChecks != 0 {
			t.Fatalf("successful confirmation counted as failed check: %+v", member)
		}
	}
}

func TestStableRecoveryAcceptsConfirmationAfterThreeFreshSuccesses(t *testing.T) {
	primary, backup := false, true
	s := partialFailureGroup(t, &primary, &backup)
	s.selected = "backup"
	for i := 0; i < 3; i++ {
		s.stable.lastRecovery = time.Time{}
		s.checkOutbounds(context.Background(), 0)
		if i < 2 && selectedTag(s) != "backup" {
			t.Fatal("confirmation recovery bypassed three-success threshold")
		}
	}
	if selectedTag(s) != "primary" {
		t.Fatal("priority did not recover")
	}
}

func TestStableSharedServiceFailureDoesNotBounceSelection(t *testing.T) {
	primary, backup := false, false
	s := partialFailureGroup(t, &primary, &backup)
	for i := 0; i < 4; i++ {
		s.stable.confirmAfter = time.Time{}
		s.checkOutbounds(context.Background(), 0)
	}
	if selectedTag(s) != "primary" || s.StableStatus().State != "primary" {
		t.Fatalf("working confirmation treated as outage or switched: %+v", s.StableStatus())
	}
	// A selected reserve must remain stable until three recovery successes.
	s.selected = "backup"
	for i := 0; i < 4; i++ {
		s.stable.confirmAfter = time.Time{}
		s.checkOutbounds(context.Background(), 0)
	}
	if selectedTag(s) != "backup" {
		t.Fatal("all-failed round changed selection without a healthy alternative")
	}
}
