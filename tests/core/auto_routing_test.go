package autoroute

import (
	"errors"
	"context"
	"crypto/x509"
	"encoding/json"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/option"
	M "github.com/sagernet/sing/common/metadata"
	"github.com/sagernet/sing/service"
	"net"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"sync/atomic"
	"testing"
	"time"
)

type testRoots struct {
	adapter.CertificateStore
	pool *x509.CertPool
}

func (r *testRoots) Pool() *x509.CertPool { return r.pool }

type testOutbound struct {
	adapter.Outbound
	tag, kind, address string
	mark               uint32
	calls              atomic.Int32
}

func (o *testOutbound) Tag() string                 { return o.tag }
func (o *testOutbound) Type() string                { return o.kind }
func (o *testOutbound) Dependencies() []string      { return nil }
func (o *testOutbound) KabanmaxRoutingMark() uint32 { return o.mark }
func (o *testOutbound) DialContext(ctx context.Context, network string, d M.Socksaddr) (net.Conn, error) {
	o.calls.Add(1)
	if d.Addr.String() != "203.0.113.7" {
		return nil, context.Canceled
	}
	return (&net.Dialer{}).DialContext(ctx, network, o.address)
}
func testManager(t *testing.T, failBody string) (*Manager, Query, *testOutbound, *testOutbound) {
	t.Helper()
	makeServer := func(status int, prefix string) *httptest.Server {
		return httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			nonce := r.Header.Get("X-Kabanmax-Probe")
			w.Header().Set("X-Kabanmax-Probe", nonce)
			w.WriteHeader(status)
			_, _ = w.Write([]byte(prefix + nonce))
		}))
	}
	failure := makeServer(451, failBody)
	success := makeServer(200, "ok:")
	t.Cleanup(failure.Close)
	t.Cleanup(success.Close)
	pool := x509.NewCertPool()
	pool.AddCert(failure.Certificate())
	pool.AddCert(success.Certificate())
	ctx := service.ContextWith[adapter.CertificateStore](context.Background(), &testRoots{pool: pool})
	source := option.KabanmaxAutoSource{ID: "s1", Outbound: "zap", Mark: 0x02000001, ProbeZapret: true, Direct: true, Domain: "example.com", Path: "/contract", Port: 443, Status: 200, Prefix: "ok:", FailureStatus: 451, FailurePrefix: "fail:"}
	m := New(ctx, []option.KabanmaxAutoSource{source})
	zap := &testOutbound{tag: "zap", kind: "direct", mark: source.Mark, address: failure.Listener.Addr().String()}
	direct := &testOutbound{tag: "direct-out", kind: "direct", address: success.Listener.Addr().String()}
	m.Outbound = func(tag string) (adapter.Outbound, bool) {
		if tag == "zap" {
			return zap, true
		}
		if tag == "direct-out" {
			return direct, true
		}
		return nil, false
	}
	m.Match = func(context.Context, *adapter.InboundContext) (string, error) { return "zap", nil }
	m.Lookup = func(context.Context, string) ([]netip.Addr, uint32, error) {
		return []netip.Addr{netip.MustParseAddr("203.0.113.7")}, 60, nil
	}
	q:=Query{IP: "203.0.113.7", Domain: "example.com", SourceIP: "192.0.2.8", Inbound: "tproxy-in", Port: 443, Source: "zap"}
	m.LogFailure=func(Event,error)bool{return true}
	meta:=metadata(q);event:=m.Observe(&meta,q.Source)
	m.Failed(event,errors.New("synthetic connection timeout"))
	return m,q,zap,direct
}

func TestAutoProbeAndLease(t *testing.T) {
	m, q, z, d := testManager(t, "fail:")
	result, e := m.Probe(context.Background(), q)
	if e != nil {
		t.Fatal(e)
	}
	decision := result.(Decision)
	if decision.Status != "proposed" || z.calls.Load() != 2 || d.calls.Load() != 2 {
		t.Fatalf("not two independent application attempts: %+v", decision)
	}
	for _, a := range decision.Attempts {
		if !a.TLSVerified || !a.Reachable {
			t.Fatal("missing TLS/dial evidence", a)
		}
	}
	if _, e = m.Apply(context.Background(), decision.ID); e != nil {
		t.Fatal(e)
	}
	if _, e = m.Apply(context.Background(), decision.ID); e == nil {
		t.Fatal("replayed decision")
	}
	meta := metadata(q)
	if target := m.Select(context.Background(), "zap", &meta); target != "direct-out" {
		t.Fatal(target)
	}
	other := meta
	other.Destination.Fqdn = "other.example.com"
	if m.Select(context.Background(), "zap", &other) != "zap" {
		t.Fatal("shared CDN IP leaked")
	}
	if m.Select(context.Background(), "vpn", &meta) != "vpn" {
		t.Fatal("original first match bypassed")
	}
	keys, e := m.Revoke(decision.ID, false)
	if e != nil || len(keys) != 1 {
		t.Fatal(e, keys)
	}
	if m.Select(context.Background(), "zap", &meta) != "zap" {
		t.Fatal("revoke left rule")
	}
	_, e = m.guard(context.Background(), q)
	if e == nil || e.Error() != "suppressed" {
		t.Fatal("suppression lost", e)
	}
	reset := New(context.Background(), nil)
	if len(reset.leases) != 0 {
		t.Fatal("new Box restored unverified lease")
	}
}

func TestAutoUnprovenFailureDoesNotProbeAlternative(t *testing.T) {
	m, q, z, d := testManager(t, "wrong:")
	result, e := m.Probe(context.Background(), q)
	if e != nil {
		t.Fatal(e)
	}
	decision := result.(Decision)
	if decision.Status != "inconclusive" || z.calls.Load() != 2 || d.calls.Load() != 0 {
		t.Fatal("unproven failure caused fallback", decision)
	}
}

func TestAutoGuardBeforeDial(t *testing.T) {
	for _, change := range []func(*Manager, *Query){
		func(m *Manager, q *Query) { q.Domain = "" }, func(m *Manager, q *Query) { q.Domain = "bank.ru" },
		func(m *Manager, q *Query) {
			m.Match = func(context.Context, *adapter.InboundContext) (string, error) { return "block", nil }
		},
		func(m *Manager, q *Query) { m.disabled["zap"] = true },
		func(m *Manager, q *Query) {
			s := m.sources["zap"]
			s.ExcludedSources = []string{"192.0.2.0/24"}
			m.sources["zap"] = s
		},
		func(m *Manager, q *Query) {
			s := m.sources["zap"]
			s.ExcludedSystem = true
			m.sources["zap"] = s
			q.Inbound = "system-in"
		},
		func(m *Manager, q *Query) {
			s := m.sources["zap"]
			s.ExcludedSources = []string{"malformed"}
			m.sources["zap"] = s
		},
		func(m *Manager, q *Query) {
			s := m.sources["zap"]
			s.Protected = []string{"infrastructure.example"}
			m.sources["zap"] = s
		},
		func(m *Manager, q *Query) { q.IP = "198.18.0.7" },
		func(m *Manager, q *Query) {
			q.Domain = "bank.ru"
			s := m.sources["zap"]
			s.Domain = q.Domain
			m.sources["zap"] = s
		},
	} {
		m, q, z, d := testManager(t, "fail:")
		change(m, &q)
		_, _ = m.Probe(context.Background(), q)
		if z.calls.Load()+d.calls.Load() != 0 {
			t.Fatal("policy guard dialed")
		}
	}
}

func TestAutoIPOnlyObservationIsRetained(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	meta := metadata(q)
	meta.Destination = M.ParseSocksaddr("203.0.113.7:443")
	meta.Domain = "reverse-is-not-evidence.test"
	event := m.Observe(&meta, "zap")
	if event == nil || event.IP != q.IP || event.Domain != "" || event.Status != "identity_unknown" {
		t.Fatal(event)
	}
	if m.Observe(&meta, "direct-out") != nil {
		t.Fatal("plain Direct attributed as Zapret")
	}
	data, e := json.Marshal(m.State())
	if e != nil || !json.Valid(data) {
		t.Fatal(e)
	}
}

func TestAutoWARPIndependentPermissionAndDNSChange(t *testing.T) {
	m, q, z, d := testManager(t, "fail:")
	s := m.sources["zap"]
	s.Direct = false
	s.WARP = "warp/profile"
	m.sources["zap"] = s
	warp := &testOutbound{tag: s.WARP, kind: "warp", address: d.address}
	original := m.Outbound
	m.Outbound = func(tag string) (adapter.Outbound, bool) {
		if tag == s.WARP {
			return warp, true
		}
		return original(tag)
	}
	result, e := m.Probe(context.Background(), q)
	if e != nil {
		t.Fatal(e)
	}
	decision := result.(Decision)
	if decision.Target != s.WARP || warp.calls.Load() != 2 || d.calls.Load() != 0 || z.calls.Load() != 2 {
		t.Fatal(decision)
	}
	if _, e = m.Apply(context.Background(), decision.ID); e != nil {
		t.Fatal(e)
	}
	m.Lookup = func(context.Context, string) ([]netip.Addr, uint32, error) {
		return []netip.Addr{netip.MustParseAddr("203.0.113.8")}, 60, nil
	}
	meta := metadata(q)
	if m.Select(context.Background(), "zap", &meta) != "zap" || len(m.leases) != 0 {
		t.Fatal("DNS rebinding kept lease")
	}
}

func TestAutoDoesNotMonitorByteCounters(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	meta := metadata(q)
	e := m.Observe(&meta, "zap")
	client, inbound := net.Pipe()
	defer client.Close()
	defer inbound.Close()
	watched := m.Track(inbound, e)
	go func() { _, _ = client.Write([]byte("request")) }()
	b := make([]byte, 7)
	if _, err := watched.Read(b); err != nil {
		t.Fatal(err)
	}
	if e.Upload != 0 || e.Download != 0 || watched!=inbound {
		t.Fatal("error-driven routing installed a byte counter watcher")
	}
}

func TestAutoClearCancelsInFlightDecision(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	once := false
	m.Match = func(context.Context, *adapter.InboundContext) (string, error) {
		if !once {
			once = true
			_, _ = m.Revoke("zap", false)
		}
		return "zap", nil
	}
	answer, e := m.Probe(context.Background(), q)
	if e == nil {
		if d, ok := answer.(Decision); ok && d.Status == "proposed" {
			t.Fatal("clear was followed by a fresh proposal from the same running job")
		}
	}
	if len(m.leases) != 0 {
		t.Fatal("clear left a lease")
	}
}

func TestAutoWorkingOriginalAndCooldown(t *testing.T) {
	m, q, z, d := testManager(t, "fail:")
	z.address = d.address
	answer, e := m.Probe(context.Background(), q)
	if e != nil {
		t.Fatal(e)
	}
	decision := answer.(Decision)
	if decision.Status != "unchanged" || z.calls.Load() != 2 || d.calls.Load() != 0 || len(m.leases) != 0 {
		t.Fatal(decision)
	}
	if _, e = m.Probe(context.Background(), q); e == nil || e.Error() != "cooldown" {
		t.Fatal("repeat was not bounded", e)
	}
	if z.calls.Load() != 2 {
		t.Fatal("cooldown made new requests")
	}
}

func TestAutoSuppressionUsesStableSectionID(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	answer, e := m.Probe(context.Background(), q)
	if e != nil {
		t.Fatal(e)
	}
	d := answer.(Decision)
	if _, e = m.Apply(context.Background(), d.ID); e != nil {
		t.Fatal(e)
	}
	keys, e := m.Revoke(d.ID, false)
	if e != nil {
		t.Fatal(e)
	}
	source := m.sources["zap"]
	source.Outbound = "renamed"
	source.Suppressed = keys
	next := New(context.Background(), []option.KabanmaxAutoSource{source})
	q.Source = "renamed"
	if _, e = next.guard(context.Background(), q); e == nil || e.Error() != "suppressed" {
		t.Fatal("rename lost persistent scope", e)
	}
}

func TestAutoUDPIsObservedWithoutHTTPSProbe(t *testing.T) {
	m, q, z, d := testManager(t, "fail:")
	m.events=map[string]*Event{}
	meta := metadata(q)
	meta.Network = "udp"
	meta.Destination = M.ParseSocksaddr("203.0.113.7:443")
	event := m.Observe(&meta, "zap")
	m.Failed(event, context.Canceled)
	m.Sweep(context.Background())
	if event == nil || event.IP != q.IP || event.Reason != "udp_not_supported" || z.calls.Load()+d.calls.Load() != 0 {
		t.Fatal(event)
	}
}

func TestAutoNoProgressIsPerConnection(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	meta := metadata(q)
	first := m.Observe(&meta, "zap")
	first.Upload = 99
	first.progress = time.Now().Add(-time.Hour)
	second := m.Observe(&meta, "zap")
	if first == second || second.Upload != 0 || time.Since(second.progress) > time.Second {
		t.Fatal("a new connection inherited stale progress")
	}
}

func TestAutoLeaseScope(t *testing.T) {
	now := time.Now()
	l := Lease{Source: "zap", IP: "203.0.113.7", Domain: "one.test", SourceIP: "192.0.2.8", Inbound: "tproxy-in", Port: 443, Target: "direct-out", Deadline: now.Add(time.Minute)}
	meta := adapter.InboundContext{Network: "tcp", Inbound: "tproxy-in", Source: M.ParseSocksaddr("192.0.2.8:5555"), Destination: M.Socksaddr{Fqdn: "one.test", Port: 443}, DestinationAddresses: []netip.Addr{netip.MustParseAddr("203.0.113.7")}}
	if !l.matches("zap", &meta, now) {
		t.Fatal("exact scope did not match")
	}
	for _, mutate := range []func(*adapter.InboundContext){
		func(m *adapter.InboundContext) { m.Destination.Fqdn = "two.test" },
		func(m *adapter.InboundContext) { m.Destination.Port = 80 },
		func(m *adapter.InboundContext) { m.Source = M.ParseSocksaddr("192.0.2.9:5555") },
		func(m *adapter.InboundContext) { m.Network = "udp" },
		func(m *adapter.InboundContext) { m.Inbound = "system-in" },
		func(m *adapter.InboundContext) {
			m.Destination = M.ParseSocksaddr("203.0.113.7:443")
			m.Domain = "one.test"
		},
		func(m *adapter.InboundContext) {
			m.DestinationAddresses = []netip.Addr{netip.MustParseAddr("203.0.113.8")}
		},
	} {
		copy := meta
		mutate(&copy)
		if l.matches("zap", &copy, now) {
			t.Fatal("scope widened", copy)
		}
	}
	if l.matches("other", &meta, now) || l.matches("zap", &meta, now.Add(time.Minute)) {
		t.Fatal("source or expiry ignored")
	}
}

func TestAutoRoutedFailureWithdrawsOnlyOwnLease(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	result, err := m.Probe(context.Background(), q)
	if err != nil {
		t.Fatal(err)
	}
	d := result.(Decision)
	if _, err = m.Apply(context.Background(), d.ID); err != nil {
		t.Fatal(err)
	}
	meta := metadata(q)
	event := m.Observe(&meta, q.Source)
	if m.SelectForEvent(context.Background(), q.Source, &meta, event) != "direct-out" {
		t.Fatal("alternative was not selected")
	}
	replacement := m.leases[d.ID]
	var loggedOutbound string
	m.LogFailure=func(event Event,err error)bool{loggedOutbound=event.Source;return true}
	delete(m.leases, d.ID)
	replacement.ID = "replacement-lease"
	m.leases[replacement.ID] = replacement
	m.Failed(event, context.DeadlineExceeded)
	if len(m.leases) != 1 {
		t.Fatal("late failure revoked a replacement")
	}
	if event.Failure!=nil || loggedOutbound!="direct-out" {t.Fatal("alternative error admitted as original",loggedOutbound)}
	event = m.Observe(&meta, q.Source)
	if m.SelectForEvent(context.Background(), q.Source, &meta, event) != "direct-out" {
		t.Fatal("replacement not selected")
	}
	m.Failed(event, context.DeadlineExceeded)
	if len(m.leases) != 0 || len(m.history) == 0 || m.history[len(m.history)-1].Status != "rolled_back" {
		t.Fatal("failed alternative remained active", m.leases, m.history)
	}
	if event.Failure!=nil || loggedOutbound!="direct-out" {t.Fatal("alternative error admitted as original",loggedOutbound)}
	if m.Select(context.Background(), q.Source, &meta) != q.Source {
		t.Fatal("rollback did not restore source")
	}
}

func TestAutoLeaseIPv6(t *testing.T) {
	now := time.Now()
	l := Lease{Source: "zap", IP: "2001:db8::7", Domain: "one.test", SourceIP: "2001:db8::8", Inbound: "tproxy6-in", Port: 443, Deadline: now.Add(time.Second)}
	m := adapter.InboundContext{Network: "tcp", Inbound: "tproxy6-in", Source: M.ParseSocksaddr("[2001:db8::8]:5555"), Destination: M.Socksaddr{Fqdn: "one.test", Port: 443}, DestinationAddresses: []netip.Addr{netip.MustParseAddr(l.IP)}}
	if !l.matches("zap", &m, now) {
		t.Fatal("IPv6 scope failed")
	}
}
