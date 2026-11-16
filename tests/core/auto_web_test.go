package autoroute

import (
	"fmt"
	"context"
	"crypto/x509"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing/service"
	"net"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"testing"
	"sync/atomic"
	"time"
)

func webManager(t *testing.T, status int, body string, headers ...map[string]string) (*Manager, Query, *testOutbound, *testOutbound) {
	t.Helper()
	m, q, z, d := testManager(t, "fail:")
	ordinary := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Host != "example.com:443" || r.URL.Path != "/" {
			t.Error("identity/path changed", r.Host, r.URL.Path)
		}
		w.Header().Set("Content-Type", "text/html")
		for _, group := range headers {
			for key, value := range group {
				w.Header().Set(key, value)
			}
		}
		w.WriteHeader(status)
		_, _ = w.Write([]byte(body))
	}))
	t.Cleanup(ordinary.Close)
	pool := x509.NewCertPool()
	pool.AddCert(ordinary.Certificate())
	m.ctx = service.ContextWith[adapter.CertificateStore](m.ctx, &testRoots{pool: pool})
	s := m.sources["zap"]
	s.Mode = "web"
	s.Domain = ""
	s.Path = "/"
	s.Prefix = ""
	s.FailureStatus = 0
	s.AutoApply = false
	m.sources["zap"] = s
	z.address = "127.0.0.1:1"
	d.address = ordinary.Listener.Addr().String()
	meta := metadata(q)
	m.Observe(&meta, "zap")
	return m, q, z, d
}

const normalPage = "<html><body>Ordinary application content is available.</body></html>"

func TestWebLeaseDoesNotChooseAnAddressFromMixedDNS(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	meta := metadata(q)
	lease := Lease{Source: q.Source, IP: q.IP, Domain: q.Domain, SourceIP: q.SourceIP, Inbound: q.Inbound, Port: q.Port, Deadline: time.Now().Add(time.Minute)}
	meta.DestinationAddresses = append(meta.DestinationAddresses, netip.MustParseAddr("203.0.113.8"))
	if lease.matches(q.Source, &meta, time.Now()) {
		t.Fatal("lease can pin a multi-address domain and steal its healthy sibling IP")
	}
	_ = m
}

type webPeerConn struct {
	net.Conn
	peer net.Addr
}

func (c webPeerConn) RemoteAddr() net.Addr { return c.peer }

func TestWebActualDialKeepsFlowIdentityAndOneConcreteIP(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	meta := metadata(q)
	meta.DestinationAddresses = append(meta.DestinationAddresses, netip.MustParseAddr("203.0.113.8"))
	event := m.Observe(&meta, q.Source)
	if event.IP != "" {
		t.Fatal("guessed DNS address")
	}
	conn := webPeerConn{peer: &net.TCPAddr{IP: net.ParseIP("203.0.113.8"), Port: 443}}
	ReportDial(context.Background(), conn, nil)
	if event.IP != "" {
		t.Fatal("unbound dial attributed")
	}
	ReportDial(BindObservation(context.Background(), m, event), conn, nil)
	if event.IP != "203.0.113.8" || event.Domain != q.Domain || !event.DomainKnown {
		t.Fatal(event)
	}
	result, err := m.Probe(context.Background(), Query{IP: "", Domain: q.Domain, SourceIP: q.SourceIP, Inbound: q.Inbound, Port: q.Port, Source: q.Source})
	if err != nil || result.(map[string]any)["reason"] != "actual_destination_ip_unknown" {
		t.Fatal("web expanded unknown IP to DNS batch", result, err)
	}
}

func TestWebInvalidTLSIsNotTransportFailureProof(t *testing.T) {
	m, q, z, d := webManager(t, 200, normalPage)
	m.ctx = service.ContextWith[adapter.CertificateStore](m.ctx, &testRoots{pool: x509.NewCertPool()})
	z.address = d.address
	result, err := m.Probe(context.Background(), q)
	if err != nil {
		t.Fatal(err)
	}
	decision := result.(Decision)
	if decision.ApplyAllowed || d.calls.Load() != 0 || decision.Attempts[0].Reason != "tls_verification_failed" {
		t.Fatal(decision)
	}
}

func TestWebOrdinaryResourceStaysManualWithoutAutoApply(t *testing.T) {
	m, q, z, d := webManager(t, 200, normalPage)
	result, err := m.Probe(context.Background(), q)
	if err != nil {
		t.Fatal(err)
	}
	decision := result.(Decision)
	if decision.Status != "proposed" || decision.Evidence != "alternative_reachable" || !decision.ApplyAllowed || decision.AutoApplyEligible || len(m.leases) != 0 || z.calls.Load() != 2 || d.calls.Load() != 2 {
		t.Fatalf("ordinary evidence incorrectly classified: %+v", decision)
	}
	if _, err = m.Apply(context.Background(), decision.ID); err != nil {
		t.Fatal(err)
	}
	meta := metadata(q)
	if m.Select(context.Background(), q.Source, &meta) != "direct-out" {
		t.Fatal("scoped manual Apply failed")
	}
	meta.Destination.Fqdn = "other.example.com"
	if m.Select(context.Background(), q.Source, &meta) != q.Source {
		t.Fatal("CDN scope expanded")
	}
}

func TestWebRecheckDoesNotSilentlyApplyANewProposal(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	result, err := m.Probe(context.Background(), q)
	if err != nil {
		t.Fatal(err)
	}
	d := result.(Decision)
	if _, err = m.Apply(context.Background(), d.ID); err != nil {
		t.Fatal(err)
	}
	lease := m.leases[d.ID]
	lease.Created = time.Now().Add(-6 * time.Minute)
	m.leases[d.ID] = lease
	m.cooldown[m.key(q)] = time.Now().Add(-6 * time.Minute)
	m.Sweep(context.Background())
	if len(m.leases) != 0 {
		t.Fatal("web recheck auto-applied a new decision")
	}
}

func TestWebHTTPOutcomesDoNotAuthorizeApply(t *testing.T) {
	for _, item := range []struct {
		status       int
		body, reason string
	}{
		{302, normalPage, "redirect"}, {401, normalPage, "authentication_required"}, {403, normalPage, "access_denied"}, {429, normalPage, "rate_limited"}, {405, normalPage, "method_unsupported"},
		{200, "<html>captcha verify you are human challenge</html>", "anti_bot"}, {200, "ok", "content_contract_unconfirmed"}, {503, normalPage, "server_error"},
	} {
		t.Run(item.reason, func(t *testing.T) {
			m, q, _, _ := webManager(t, item.status, item.body)
			result, err := m.Probe(context.Background(), q)
			if err != nil {
				t.Fatal(err)
			}
			d := result.(Decision)
			if d.ApplyAllowed || d.Status == "proposed" || len(m.leases) != 0 {
				t.Fatal(d)
			}
			if len(d.Attempts) < 4 || d.Attempts[2].Reason != item.reason {
				t.Fatalf("wrong outcome %+v", d)
			}
		})
	}
}

func TestWebCacheAndContentRestrictions(t *testing.T) {
	for _, headers := range []map[string]string{{"Age": "100"}, {"Content-Type": "application/octet-stream"}, {"Content-Encoding": "gzip"}} {
		m, q, _, _ := webManager(t, 200, normalPage, headers)
		result, err := m.Probe(context.Background(), q)
		if err != nil {
			t.Fatal(err)
		}
		if d := result.(Decision); d.ApplyAllowed || d.AutoApplyEligible {
			t.Fatal(d)
		}
	}
}

func TestWebRepeatedBodyStallIsSuspectedNotDPIFailure(t *testing.T) {
	m, q, z, _ := webManager(t, 200, normalPage)
	stalled := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		w.WriteHeader(200)
		w.(http.Flusher).Flush()
		<-r.Context().Done()
	}))
	t.Cleanup(stalled.Close)
	adapter.RootPoolFromContext(m.ctx).AddCert(stalled.Certificate())
	z.address = stalled.Listener.Addr().String()
	result, err := m.Probe(context.Background(), q)
	if err != nil {
		t.Fatal(err)
	}
	d := result.(Decision)
	if d.Status != "proposed" || d.Evidence != "alternative_reachable" || d.AutoApplyEligible || len(m.leases) != 0 {
		t.Fatal(d)
	}
}

func TestWebOneFailureAndGlobalFailureCannotApply(t *testing.T){
 t.Run("one_failure",func(t *testing.T){
  m,q,z,d:=webManager(t,200,normalPage);var calls atomic.Int32
  intermittent:=httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){if calls.Add(1)==1{conn,_,_:=w.(http.Hijacker).Hijack();conn.Close();return};w.Header().Set("Content-Type","text/html");_,_=w.Write([]byte(normalPage))}));t.Cleanup(intermittent.Close)
  adapter.RootPoolFromContext(m.ctx).AddCert(intermittent.Certificate());z.address=intermittent.Listener.Addr().String()
  result,err:=m.Probe(context.Background(),q);if err!=nil{t.Fatal(err)};decision:=result.(Decision)
  if decision.ApplyAllowed||d.calls.Load()!=0||len(m.leases)!=0{t.Fatal(decision)}
 })
 t.Run("all_unreachable",func(t *testing.T){m,q,_,d:=webManager(t,200,normalPage);d.address="127.0.0.1:1";result,err:=m.Probe(context.Background(),q);if err!=nil{t.Fatal(err)};decision:=result.(Decision);if decision.ApplyAllowed||decision.Evidence!="suspected_failure"||len(m.leases)!=0{t.Fatal(decision)}})
}

func TestWebWARPIsIndependentAndNeverASelector(t *testing.T) {
	for _, directAllowed := range []bool{true, false} {
		m, q, z, d := webManager(t, 403, normalPage)
		server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte(normalPage))
		}))
		t.Cleanup(server.Close)
		adapter.RootPoolFromContext(m.ctx).AddCert(server.Certificate())
		source := m.sources[q.Source]
		source.WARP = "warp/profile"
		source.Direct = directAllowed
		m.sources[q.Source] = source
		warp := &testOutbound{tag: source.WARP, kind: "warp", address: server.Listener.Addr().String()}
		old := m.Outbound
		m.Outbound = func(tag string) (adapter.Outbound, bool) {
			if tag == source.WARP {
				return warp, true
			}
			return old(tag)
		}
		result, err := m.Probe(context.Background(), q)
		if err != nil {
			t.Fatal(err)
		}
		decision := result.(Decision)
		if decision.Target != source.WARP || decision.Evidence != "alternative_reachable" || warp.calls.Load() != 2 || z.calls.Load() != 2 || decision.AutoApplyEligible || len(m.leases) != 0 {
			t.Fatal(decision)
		}
		if !directAllowed && d.calls.Load() != 0 {
			t.Fatal("forbidden Direct dialed")
		}
	}
}

func TestStrictAutoApplyStillRequiresVerifiedContract(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	s := m.sources[q.Source]
	s.AutoApply = true
	m.sources[q.Source] = s
	result, err := m.Probe(context.Background(), q)
	if err != nil {
		t.Fatal(err)
	}
	decision := result.(Decision)
	if decision.Status != "applied" || decision.Evidence != "verified_for_apply" || !decision.AutoApplyEligible || len(m.leases) != 1 {
		t.Fatal(decision)
	}
}

func TestWebHealthyOriginalIsUnchanged(t *testing.T) {
	m, q, z, d := webManager(t, 200, normalPage)
	z.address = d.address
	result, err := m.Probe(context.Background(), q)
	if err != nil {
		t.Fatal(err)
	}
	decision := result.(Decision)
	if decision.Evidence != "healthy" || d.calls.Load() != 0 || decision.ApplyAllowed {
		t.Fatal(decision)
	}
}

func TestWebIPOnlyIsDiagnosticAndUnattributedCannotDial(t *testing.T) {
	m, q, z, d := webManager(t, 200, normalPage)
	q.Domain = ""
	meta := metadata(q)
	event:=m.Observe(&meta, "zap")
	m.Failed(event,fmt.Errorf("synthetic IP connection failure"))
	result, err := m.Probe(context.Background(), q)
	if err != nil {
		t.Fatal(err)
	}
	if result.(map[string]any)["reason"]!="identity_unknown" || len(m.leases)!=0 || z.calls.Load()!=0 || d.calls.Load()!=0 {t.Fatal("IP-only opt-in ignored",result)}
	q.SourceIP = "192.0.2.99"
	_, _ = m.Probe(context.Background(), q)
	if z.calls.Load() != 0 || d.calls.Load() != 0 {
		t.Fatal("unattributed diagnostic dial")
	}
}
