package autoroute

import (
	"context"
	"io"
	"net"
	"sync/atomic"
	"testing"
	"time"

	"github.com/sagernet/sing-box/adapter"
	M "github.com/sagernet/sing/common/metadata"
)

type probeBudgetOutbound struct {
	adapter.Outbound
	budget    time.Duration
	delay     time.Duration
	remaining atomic.Int64
}

type probeBudgetGroup struct{ adapter.Outbound }

func (o *probeBudgetGroup) All() []string                     { return []string{o.Outbound.Tag()} }
func (o *probeBudgetGroup) Selected(string) adapter.Outbound  { return o.Outbound }
func (o *probeBudgetGroup) AttachConnection(io.Closer) func() { return func() {} }

func TestWebProbeKeepsDefaultAndFollowsSelectedGroup(t *testing.T) {
	for _, grouped := range []bool{false, true} {
		m, q, _, target := webManager(t, 200, normalPage)
		wrapped := &probeBudgetOutbound{Outbound: target}
		var selected adapter.Outbound = wrapped
		expected := 5 * time.Second
		if grouped {
			wrapped.budget = 8 * time.Second
			expected = 13 * time.Second
			selected = &probeBudgetGroup{Outbound: wrapped}
		}
		original := m.Outbound
		m.Outbound = func(tag string) (adapter.Outbound, bool) {
			if tag == "direct-out" {
				return selected, true
			}
			return original(tag)
		}
		a := m.webAttempt(context.Background(), q, m.sources[q.Source], "direct-out")
		if a.Status != "verified" || time.Duration(wrapped.remaining.Load()) < expected-time.Second || time.Duration(wrapped.remaining.Load()) > expected {
			t.Fatalf("wrong selected/default budget: %s %+v", time.Duration(wrapped.remaining.Load()), a)
		}
	}
}
func (o *probeBudgetOutbound) KabanmaxProbeDialTimeout() time.Duration { return o.budget }
func (o *probeBudgetOutbound) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	if deadline, ok := ctx.Deadline(); ok {
		o.remaining.Store(int64(time.Until(deadline)))
	}
	timer := time.NewTimer(o.delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-timer.C:
	}
	return o.Outbound.DialContext(ctx, network, destination)
}

func TestWebProbeAllowsConfiguredFallbackDialBeforeVerifiedHTTPS(t *testing.T) {
	m, q, _, target := webManager(t, 200, normalPage)
	wrapped := &probeBudgetOutbound{Outbound: target, budget: 8 * time.Second, delay: 5200 * time.Millisecond}
	original := m.Outbound
	m.Outbound = func(tag string) (adapter.Outbound, bool) {
		if tag == "direct-out" {
			return wrapped, true
		}
		return original(tag)
	}
	a := m.webAttempt(context.Background(), q, m.sources[q.Source], "direct-out")
	if a.Status != "verified" || !a.TLSVerified || a.HTTPStatus != 200 || a.BodyBytes == 0 {
		t.Fatalf("working fallback timed out before HTTPS: %+v", a)
	}
	if time.Duration(wrapped.remaining.Load()) < 12*time.Second || time.Duration(wrapped.remaining.Load()) > 13*time.Second {
		t.Fatalf("expected 8s dial + 5s HTTPS allowance, got %s", time.Duration(wrapped.remaining.Load()))
	}
}

func TestWebProbeDoesNotExtendParentDeadline(t *testing.T) {
	m, q, _, target := webManager(t, 200, normalPage)
	wrapped := &probeBudgetOutbound{Outbound: target, budget: 8 * time.Second, delay: time.Second}
	original := m.Outbound
	m.Outbound = func(tag string) (adapter.Outbound, bool) {
		if tag == "direct-out" {
			return wrapped, true
		}
		return original(tag)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	started := time.Now()
	a := m.webAttempt(ctx, q, m.sources[q.Source], "direct-out")
	if a.Status == "verified" || time.Since(started) > time.Second || time.Duration(wrapped.remaining.Load()) > 150*time.Millisecond {
		t.Fatalf("parent job deadline extended: elapsed=%s attempt=%+v", time.Since(started), a)
	}
}
