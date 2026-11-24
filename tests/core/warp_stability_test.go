package warp

import (
	"context"
	"errors"
	"net"
	"sync/atomic"
	"testing"
	"time"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	M "github.com/sagernet/sing/common/metadata"
	"github.com/sagernet/sing/service"
)

func TestWARPStartsStandbyHandshakeWithoutOverridingKeepalive(t *testing.T) {
	if got := warpKeepalive(nil); got.From != 25 || got.To != 25 {
		t.Fatalf("standby WARP has no initial handshake trigger: %+v", got)
	}
	for _, value := range []uint32{0, 7, 60} {
		explicit := &option.Range[uint32]{From: value, To: value}
		if warpKeepalive(explicit) != explicit {
			t.Fatalf("explicit keepalive %d changed", value)
		}
	}
}

type apiTestManager struct {
	adapter.OutboundManager
	outbound adapter.Outbound
}

func (m apiTestManager) Outbound(tag string) (adapter.Outbound, bool) {
	return m.outbound, tag == "marked-api"
}

type apiTestOutbound struct {
	adapter.Outbound
	calls atomic.Int32
}

func (o *apiTestOutbound) DialContext(context.Context, string, M.Socksaddr) (net.Conn, error) {
	o.calls.Add(1)
	return nil, errors.New("synthetic API unavailable")
}

// Both registration and existing-profile reads must use the supplied core
// outbound. No real DNS, TLS, Cloudflare or router is involved.
func TestWARPAPIUsesExplicitDetourForRegistrationAndRead(t *testing.T) {
	for _, supplied := range []bool{false, true} {
		outbound := &apiTestOutbound{}
		ctx := service.ContextWith[adapter.OutboundManager](context.Background(), apiTestManager{outbound: outbound})
		profile := option.CloudflareProfile{Detour: "marked-api"}
		if supplied {
			profile.ID, profile.AuthToken = "synthetic-id", "synthetic-token"
			profile.PrivateKey = validWARPTestConfig(t).PrivateKey
		}
		endpoint, err := NewEndpoint(ctx, nil, log.NewNOPFactory().NewLogger("warp"), "test", option.WARPEndpointOptions{Profile: profile})
		if err != nil {
			t.Fatal(err)
		}
		w := endpoint.(*Endpoint)
		_, err = w.createConfig()
		w.cancel()
		if err == nil || outbound.calls.Load() == 0 {
			t.Fatal("API did not use its explicit outbound")
		}
	}
}

func TestWARPProfilesRetryIndependentlyWithoutRecreatingEndpoint(t *testing.T) {
	first := newProfileRetryTestEndpoint(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	second := &Endpoint{ctx: ctx, cancel: cancel, await: make(chan struct{}), done: make(chan struct{})}
	valid := validWARPTestConfig(t)
	blocked := make(chan struct{})
	finished := make(chan *Config, 1)
	go func() {
		finished <- first.fetchConfig(log.NewNOPFactory().NewLogger("first"), func() (*Config, error) {
			<-blocked
			return nil, errors.New("synthetic network not ready")
		})
	}()
	got := second.fetchConfig(log.NewNOPFactory().NewLogger("second"), func() (*Config, error) { return valid, nil })
	if got != valid {
		t.Fatal("one pending profile blocked another")
	}
	first.cancel()
	close(blocked)
	select {
	case got = <-finished:
		if got != nil {
			t.Fatal("cancelled initialization returned a profile")
		}
	case <-time.After(time.Second):
		t.Fatal("profile did not stop on close")
	}
}

type interfaceUpdateTestEndpoint struct {
	adapter.Endpoint
	seen  context.Context
	calls int
}

func (e *interfaceUpdateTestEndpoint) InterfaceUpdated(ctx context.Context) {
	e.seen = ctx
	e.calls++
}

func TestWARPForwardsNetworkResetToInitializedTransport(t *testing.T) {
	w := &Endpoint{}
	listener, ok := any(w).(adapter.InterfaceUpdateListener)
	if !ok {
		t.Fatal("network manager skips WARP on interface updates and network resets")
	}
	// Network changes while registration is pending must not block the manager.
	listener.InterfaceUpdated(context.Background())
	transport := &interfaceUpdateTestEndpoint{}
	w.endpoint = transport
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	listener.InterfaceUpdated(ctx)
	listener.InterfaceUpdated(ctx)
	if transport.calls != 2 || transport.seen != ctx {
		t.Fatal("WARP lost the transport reset or its cancellation context")
	}
}
