package autoroute

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"testing"
	"time"

	"github.com/sagernet/sing-box/adapter"
	M "github.com/sagernet/sing/common/metadata"
)

func TestFailedDialRetainsConcreteIPWithMixedDNS(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	m.events = map[string]*Event{}
	meta := metadata(q)
	meta.DestinationAddresses = append(meta.DestinationAddresses, netip.MustParseAddr("2001:db8::7"))
	event := m.Observe(&meta, q.Source)
	err := &net.OpError{Op: "dial", Net: "tcp", Addr: &net.TCPAddr{IP: net.ParseIP(q.IP), Port: 443}, Err: errors.New("i/o timeout")}
	ReportDial(BindObservation(context.Background(), m, event), nil, err)
	m.Failed(event, err)
	if event.IP != q.IP {
		t.Fatalf("actual failed IP lost: %+v", event)
	}
	result, e := m.Probe(context.Background(), event.Query)
	if e != nil {
		t.Fatal(e)
	}
	d, ok := result.(Decision)
	if !ok || d.Status != "proposed" || d.Target != "direct-out" || d.Domain != q.Domain {
		t.Fatalf("missing concrete Direct proposal: %+v", result)
	}
}

func TestDomainMismatchBecomesIPScopeWithoutLosingFailure(t *testing.T) {
	m, q := ipCertificateManager(t, true)
	s := m.sources[q.Source]
	s.AutoApply = false
	s.AllowIPOnly = false
	m.sources[q.Source] = s
	m.events = map[string]*Event{}
	q.Domain = "unconfirmed.example"
	meta := metadata(q)
	event := m.Observe(&meta, q.Source)
	m.Failed(event, errors.New("synthetic timeout"))
	m.Lookup = func(context.Context, string) ([]netip.Addr, uint32, error) {
		return []netip.Addr{netip.MustParseAddr("203.0.113.99")}, 60, nil
	}
	result, e := m.Probe(context.Background(), event.Query)
	if e != nil {
		t.Fatal(e)
	}
	d, ok := result.(Decision)
	if !ok || d.Status != "proposed" || !d.IPOnly || d.Domain != "" || d.Target != "direct-out" || d.Failure == nil {
		t.Fatalf("IP scope was discarded: %+v", result)
	}
	if _, e = m.Apply(context.Background(), d.ID); e != nil {
		t.Fatal(e)
	}
}

func TestIPOnlyManualProposalDoesNotRequireAutomaticApply(t *testing.T) {
	m, q := ipCertificateManager(t, true)
	s := m.sources[q.Source]
	s.AutoApply = false
	s.AllowIPOnly = false
	m.sources[q.Source] = s
	result, e := m.Probe(context.Background(), q)
	if e != nil {
		t.Fatal(e)
	}
	d, ok := result.(Decision)
	if !ok || d.Status != "proposed" || !d.IPOnly || !d.ApplyAllowed || len(m.leases) != 0 {
		t.Fatalf("manual IP proposal unavailable: %+v", result)
	}
}

func TestDirectPreferredAndWARPUsedOnlyAfterDirectFailure(t *testing.T) {
	for _, directWorks := range []bool{true, false} {
		t.Run(map[bool]string{true: "direct", false: "warp"}[directWorks], func(t *testing.T) {
			m, q, _, d := webManager(t, 200, normalPage)
			warp := &testOutbound{tag: "warp-section", kind: "warp", address: d.address}
			if !directWorks {
				d.address = "127.0.0.1:1"
			}
			original := m.Outbound
			m.Outbound = func(tag string) (adapter.Outbound, bool) {
				if tag == warp.tag {
					return warp, true
				}
				return original(tag)
			}
			s := m.sources[q.Source]
			s.WARP = warp.tag
			m.sources[q.Source] = s
			result, e := m.Probe(context.Background(), q)
			if e != nil {
				t.Fatal(e)
			}
			decision := result.(Decision)
			want := "direct-out"
			if !directWorks {
				want = warp.tag
			}
			if decision.Status != "proposed" || decision.Target != want || (directWorks && warp.calls.Load() != 0) {
				t.Fatal(decision)
			}
		})
	}
}

func TestMixedDNSAppliesOnlyToTheActualDialIP(t *testing.T) {
	m, q, z, d := webManager(t, 200, normalPage)
	result, e := m.Probe(context.Background(), q)
	if e != nil {
		t.Fatal(e)
	}
	if _, e = m.Apply(context.Background(), result.(Decision).ID); e != nil {
		t.Fatal(e)
	}
	meta := metadata(q)
	meta.DestinationAddresses = append(meta.DestinationAddresses, netip.MustParseAddr("203.0.113.8"))
	event := m.Observe(&meta, q.Source)
	ctx := BindObservation(context.Background(), m, event)
	before := d.calls.Load()
	conn, e := WrapDial(ctx, z).DialContext(ctx, "tcp", M.Socksaddr{Addr: netip.MustParseAddr(q.IP), Port: q.Port})
	if e != nil {
		t.Fatal(e)
	}
	conn.Close()
	if d.calls.Load() != before+1 {
		t.Fatal("mixed DNS dial did not use the approved IP route")
	}
	before = d.calls.Load()
	_, _ = WrapDial(ctx, z).DialContext(ctx, "tcp", M.Socksaddr{Addr: netip.MustParseAddr("203.0.113.8"), Port: q.Port})
	if d.calls.Load() != before {
		t.Fatal("healthy sibling IP stolen by approved route")
	}
}

type testWARPSection struct {
	*testOutbound
	members []string
}

func (o *testWARPSection) Dependencies() []string { return o.members }

func TestConfiguredWARPSectionUsesItsGroupAndRejectsForeignMembers(t *testing.T) {
	m, q, _, d := webManager(t, 200, normalPage)
	warp := &testOutbound{tag: "warp-one", kind: "warp", address: d.address}
	group := &testWARPSection{testOutbound: &testOutbound{tag: "WARP", kind: "fallback", address: d.address}, members: []string{warp.tag}}
	original := m.Outbound
	m.Outbound = func(tag string) (adapter.Outbound, bool) {
		if tag == group.tag {
			return group, true
		}
		if tag == warp.tag {
			return warp, true
		}
		return original(tag)
	}
	s := m.sources[q.Source]
	s.WARP = group.tag
	s.Direct = false
	m.sources[q.Source] = s
	result, e := m.Probe(context.Background(), q)
	if e != nil {
		t.Fatal(e)
	}
	decision := result.(Decision)
	if decision.Status != "proposed" || decision.Target != group.tag || group.calls.Load() != 2 {
		t.Fatal(decision)
	}
	group.members = append(group.members, "direct-out")
	if _, e = m.target(s, group.tag); e == nil {
		t.Fatal("mixed WARP/VPN/direct group accepted")
	}
}

func TestRepeatedLoggedSourceErrorsCanConfirmAnInconclusiveRecheck(t *testing.T) {
	m, q, z, _ := webManager(t, 200, normalPage)
	plain := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte(normalPage)) }))
	defer plain.Close()
	z.address = plain.Listener.Addr().String()
	meta := metadata(q)
	event := m.Observe(&meta, q.Source)
	m.Failed(event, errors.New("synthetic connection timeout"))
	result, e := m.Probe(context.Background(), q)
	if e != nil {
		t.Fatal(e)
	}
	d := result.(Decision)
	if d.Status != "proposed" || d.Target != "direct-out" {
		t.Fatalf("repeated real source failures ignored: %+v", d)
	}
}

func TestOldOrDifferentFailureDoesNotConfirmTheNewError(t *testing.T) {
	for _, expired := range []bool{false, true} {
		t.Run(map[bool]string{false: "different", true: "expired"}[expired], func(t *testing.T) {
			m, q, z, direct := webManager(t, 200, normalPage)
			for _, old := range m.events {
				old.Count = 2
				if expired {
					old.Failure.At = time.Now().Add(-2 * time.Hour)
				}
			}
			plain := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte(normalPage)) }))
			defer plain.Close()
			z.address = plain.Listener.Addr().String()
			message := "different current source failure"
			if expired {
				message = "synthetic connection timeout"
			}
			meta := metadata(q)
			current := m.Observe(&meta, q.Source)
			m.Failed(current, errors.New(message))
			result, e := m.Probe(context.Background(), q)
			if e != nil {
				t.Fatal(e)
			}
			if result.(Decision).ApplyAllowed || direct.calls.Load() != 0 || current.Count != 1 {
				t.Fatal("old or different logged failure authorized a new proposal", result)
			}
		})
	}
}
