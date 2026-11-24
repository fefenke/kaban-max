package autoroute

import (
	"context"
	"fmt"
	"net"
	"os"
	"syscall"
	"testing"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing-box/protocol/warp"
)

func TestWouldBlockDoesNotTriggerRouting(t *testing.T) {
	for _, errno := range []error{syscall.EAGAIN, syscall.EWOULDBLOCK} {
		err := fmt.Errorf("splice read: %w", &os.SyscallError{Syscall: "splice", Err: errno})
		if connectionFailure(err) {
			t.Fatalf("temporary readiness error triggered routing: %v", err)
		}
	}
	if !connectionFailure(os.ErrDeadlineExceeded) {
		t.Fatal("real timeout was discarded")
	}
}

func TestWithdrawAlreadyAbsentLeaseDoesNotDisableSource(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	s := m.sources[q.Source]
	if _, err := m.registryWithdraw(s.ID, "already-gone"); err != nil {
		t.Fatal(err)
	}
	if _, ok := m.source(q.Source); !ok {
		t.Fatal("source was disabled")
	}
	if _, err := m.registryWithdraw("foreign", "already-gone"); err == nil {
		t.Fatal("unknown owner accepted")
	}
}

func TestDisabledSourceStillAllowsRegistryCleanup(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	s := m.sources[q.Source]
	key := m.key(q)
	m.suppressed[key] = true
	m.disabled[q.Source] = true
	if _, err := m.registryReset(s.ID, key); err != nil {
		t.Fatal(err)
	}
	if m.suppressed[key] {
		t.Fatal("disabled source trapped an exclusion")
	}
	if _, err := m.registryReset("foreign", key); err == nil {
		t.Fatal("foreign scope accepted")
	}
	if !m.disabled[q.Source] {
		t.Fatal("cleanup silently enabled routing")
	}
}

func TestRealNetworkTimeoutIsRetainedAsLoggedFailure(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	m.events = map[string]*Event{}
	meta := metadata(q)
	event := m.Observe(&meta, q.Source)
	dialErr := &net.OpError{Op: "dial", Net: "tcp", Addr: &net.TCPAddr{IP: net.ParseIP(q.IP), Port: int(q.Port)}, Err: os.ErrDeadlineExceeded}
	ReportDial(BindObservation(context.Background(), m, event), nil, dialErr)
	m.Failed(event, fmt.Errorf("open connection using outbound/direct[META]: %w", dialErr))
	rows := m.State().(map[string]any)["candidates"].([]Event)
	if len(rows) != 1 || rows[0].Failure == nil || rows[0].IP != q.IP {
		t.Fatalf("real i/o timeout disappeared: %+v", rows)
	}
}

type registrationDetourWARP struct {
	*testWARPSection
	transport string
}

func (o *registrationDetourWARP) KabanmaxWARPTransportDetour() string { return o.transport }

func TestWARPRegistrationDetourDoesNotChangeTrafficClassification(t *testing.T) {
	m, _, _, _ := testManager(t, "fail:")
	warp := &registrationDetourWARP{testWARPSection: &testWARPSection{testOutbound: &testOutbound{tag: "warp-registration", kind: "warp"}, members: []string{"registration-vpn"}}}
	original := m.Outbound
	m.Outbound = func(tag string) (adapter.Outbound, bool) {
		if tag == warp.Tag() {
			return warp, true
		}
		return original(tag)
	}
	if !m.warpOutput(warp.Tag(), nil) {
		t.Fatal("registration-only VPN detour hid direct WARP traffic")
	}
	warp.transport = "registration-vpn"
	if m.warpOutput(warp.Tag(), nil) {
		t.Fatal("actual VPN transport accepted as direct WARP")
	}
}

func TestRealWARPEndpointSeparatesRegistrationFromTransport(t *testing.T) {
	for _, transport := range []string{"", "direct-out", "registration-vpn"} {
		t.Run(transport, func(t *testing.T) {
			m, _, _, _ := testManager(t, "fail:")
			options := option.WARPEndpointOptions{Profile: option.CloudflareProfile{Detour: "registration-vpn"}}
			options.Detour = transport
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			endpoint, err := warp.NewEndpoint(ctx, nil, nil, "real-warp", options)
			if err != nil {
				t.Fatal(err)
			}
			original := m.Outbound
			m.Outbound = func(tag string) (adapter.Outbound, bool) {
				if tag == endpoint.Tag() {
					return endpoint, true
				}
				return original(tag)
			}
			if got, want := m.warpOutput(endpoint.Tag(), nil), transport != "registration-vpn"; got != want {
				t.Fatalf("transport %q, registration via VPN: got %v want %v", transport, got, want)
			}
		})
	}
}
