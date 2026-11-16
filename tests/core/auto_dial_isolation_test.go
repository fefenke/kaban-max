package autoroute

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"testing"
	"time"

	"github.com/sagernet/sing-box/common/dialer"
	C "github.com/sagernet/sing-box/constant"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

type siblingDialer struct {
	N.Dialer
	fail bool
}

func (d *siblingDialer) DialContext(ctx context.Context, network string, to M.Socksaddr) (net.Conn, error) {
	if d.fail {
		return nil, &net.OpError{Op: "dial", Net: "tcp", Addr: &net.TCPAddr{IP: net.ParseIP(to.Addr.String()), Port: int(to.Port)}, Err: errors.New("synthetic sibling refusal")}
	}
	a, b := net.Pipe()
	b.Close()
	return webPeerConn{Conn: a, peer: &net.TCPAddr{IP: net.ParseIP(to.Addr.String()), Port: int(to.Port)}}, nil
}

func TestFailedAlternativeDoesNotContaminateOriginalSibling(t *testing.T) {
	for _, fail := range []bool{false, true} {
		t.Run(map[bool]string{false: "success", true: "failure"}[fail], func(t *testing.T) {
			m, q, z, alt := webManager(t, 200, normalPage)
			result, err := m.Probe(context.Background(), q)
			if err != nil {
				t.Fatal(err)
			}
			if _, err = m.Apply(context.Background(), result.(Decision).ID); err != nil {
				t.Fatal(err)
			}
			alt.address = "127.0.0.1:1"
			meta := metadata(q)
			meta.DestinationAddresses = append(meta.DestinationAddresses, netip.MustParseAddr("203.0.113.8"))
			event := m.Observe(&meta, q.Source)
			ctx := BindObservation(context.Background(), m, event)
			wrapped := WrapDial(ctx, &siblingDialer{fail: fail})
			_, err = wrapped.DialContext(ctx, "tcp", M.Socksaddr{Addr: netip.MustParseAddr(q.IP), Port: q.Port})
			if err == nil {
				t.Fatal("expected failed alternative")
			}
			conn, err := wrapped.DialContext(ctx, "tcp", M.Socksaddr{Addr: netip.MustParseAddr("203.0.113.8"), Port: q.Port})
			ReportDial(ctx, conn, err)
			if conn != nil {
				conn.Close()
			}
			if event.IP != "203.0.113.8" || event.routedLease != "" || event.routedTarget != "" {
				t.Fatalf("sibling inherited alternative attribution: %+v", event)
			}
			_ = z
		})
	}
}

type strategySpy struct {
	siblingDialer
	strategy        *C.NetworkStrategy
	types, fallback []C.InterfaceType
	delay           time.Duration
	calls           int
}

func (d *strategySpy) DialParallelInterface(ctx context.Context, network string, to M.Socksaddr, strategy *C.NetworkStrategy, types, fallback []C.InterfaceType, delay time.Duration) (net.Conn, error) {
	d.calls++
	d.strategy = strategy
	d.types = types
	d.fallback = fallback
	d.delay = delay
	return d.siblingDialer.DialContext(ctx, network, to)
}
func (d *strategySpy) ListenSerialInterfacePacket(ctx context.Context, to M.Socksaddr, strategy *C.NetworkStrategy, types, fallback []C.InterfaceType, delay time.Duration) (net.PacketConn, error) {
	return nil, errors.New("unused")
}

func TestObservedDialRetainsInterfaceStrategy(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	meta := metadata(q)
	event := m.Observe(&meta, q.Source)
	ctx := BindObservation(context.Background(), m, event)
	spy := &strategySpy{}
	strategy := C.NetworkStrategy(1)
	types := []C.InterfaceType{C.InterfaceType(1)}
	fallback := []C.InterfaceType{C.InterfaceType(2)}
	delay := 17 * time.Millisecond
	conn, err := dialer.DialSerialNetwork(ctx, WrapParallelDial(ctx, spy), "tcp", meta.Destination, meta.DestinationAddresses, &strategy, types, fallback, delay)
	if err != nil {
		t.Fatal(err)
	}
	conn.Close()
	if spy.calls != 1 || spy.strategy != &strategy || spy.delay != delay || len(spy.types) != 1 || spy.types[0] != types[0] || spy.fallback[0] != fallback[0] {
		t.Fatal("network strategy options dropped", spy)
	}
}
