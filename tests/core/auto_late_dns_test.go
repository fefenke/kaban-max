package autoroute

import (
	"context"
	"errors"
	"net/netip"
	"syscall"
	"testing"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/common/dialer"
	"github.com/sagernet/sing/service"
)

type lateDNSRouter struct {
	adapter.DNSRouter
	ip     netip.Addr
	err    error
	leaked bool
}

func (r *lateDNSRouter) Lookup(ctx context.Context, _ string, _ adapter.DNSQueryOptions) ([]netip.Addr, error) {
	r.leaked = ctx.Value(observationKey{}) != nil
	if r.err != nil {
		return nil, r.err
	}
	return []netip.Addr{r.ip}, nil
}

func TestLateResolvedDomainMustUseAppliedIP(t *testing.T) {
	for _, parallel := range []bool{false, true} {
		name := "serial"
		if parallel {
			name = "parallel"
		}
		t.Run(name, func(t *testing.T) {
			m, q, source, alternative := webManager(t, 200, normalPage)
			if _, err := manualAPI(m, "s1", manualEvent(m).ID, "direct-out"); err != nil {
				t.Fatal(err)
			}
			meta := metadata(q)
			meta.DestinationAddresses = nil // Domain reaches Direct before DNS, as on the router.
			event := m.Observe(&meta, q.Source)
			ctx := BindObservation(context.Background(), m, event)
			dns := &lateDNSRouter{ip: netip.MustParseAddr(q.IP)}
			ctx = service.ContextWith[adapter.DNSRouter](ctx, dns)
			resolver := dialer.NewResolveDialer(ctx, source, parallel, "", adapter.DNSQueryOptions{}, 0)
			before := alternative.calls.Load()
			conn, err := WrapDial(ctx, resolver).DialContext(ctx, "tcp", meta.Destination)
			if conn != nil {
				defer conn.Close()
			}
			if err != nil {
				t.Fatalf("applied IP bypassed after late DNS: original calls=%d alternative calls=%d error=%v", source.calls.Load(), alternative.calls.Load()-before, err)
			}
			if alternative.calls.Load() != before+1 {
				t.Fatal("late-resolved IP did not select its applied alternative")
			}
			if dns.leaked {
				t.Fatal("application observation leaked into DNS transport")
			}
			ReportDial(ctx, conn, nil)
			if event.routedLease == "" || event.routedTarget != "direct-out" {
				t.Fatal("winning concrete-IP route was not retained")
			}
			visible := 0
			m.LogSourceFailure = func(Event, error) { visible++ }
			m.Failed(event, syscall.ETIMEDOUT)
			if visible != 0 {
				t.Fatal("alternative error mislabeled as original source failure")
			}
			lease := m.leases[event.routedLease]
			if !lease.NewError || lease.Reason != "applied_target_failed" {
				t.Fatal("target failure retains a stale bypass label", lease)
			}
		})
	}
}

func TestLateDNSDoesNotOverrideSiblingExclusionOrResolverFailure(t *testing.T) {
	for _, mode := range []string{"sibling", "excluded", "dns_error"} {
		t.Run(mode, func(t *testing.T) {
			m, q, source, alternative := webManager(t, 200, normalPage)
			if _, err := manualAPI(m, "s1", manualEvent(m).ID, "direct-out"); err != nil {
				t.Fatal(err)
			}
			meta := metadata(q)
			meta.DestinationAddresses = nil
			event := m.Observe(&meta, q.Source)
			ctx := BindObservation(context.Background(), m, event)
			dns := &lateDNSRouter{ip: netip.MustParseAddr(q.IP)}
			if mode == "sibling" {
				dns.ip = netip.MustParseAddr("203.0.113.99")
			}
			if mode == "excluded" {
				denied := q
				denied.Domain = ""
				m.suppressed[m.key(denied)] = true
			}
			if mode == "dns_error" {
				dns.err = errors.New("synthetic resolver failure")
			}
			ctx = service.ContextWith[adapter.DNSRouter](ctx, dns)
			resolver := dialer.NewResolveDialer(ctx, source, true, "", adapter.DNSQueryOptions{}, 0)
			before := alternative.calls.Load()
			conn, err := WrapDial(ctx, resolver).DialContext(ctx, "tcp", meta.Destination)
			if conn != nil {
				conn.Close()
			}
			if err == nil {
				t.Fatal("unexpected successful dial")
			}
			if alternative.calls.Load() != before {
				t.Fatal("late DNS crossed its approved IP/exclusion boundary")
			}
			if mode == "dns_error" && source.calls.Load() != 0 {
				t.Fatal("resolver failure dialed the original route")
			}
			if dns.leaked {
				t.Fatal("application observation leaked into DNS transport")
			}
		})
	}
}
