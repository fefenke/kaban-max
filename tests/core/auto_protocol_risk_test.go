package autoroute

import (
	"context"
	"crypto/x509"
	"encoding/json"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/option"
	M "github.com/sagernet/sing/common/metadata"
	"github.com/sagernet/sing/service"
	"net"
	"testing"
)

func protocolRiskSource(t *testing.T, m *Manager, source string, on bool) {
	t.Helper()
	raw, err := json.Marshal(m.sources[source])
	if err != nil {
		t.Fatal(err)
	}
	var values map[string]any
	if err = json.Unmarshal(raw, &values); err != nil {
		t.Fatal(err)
	}
	values["allow_unconfirmed_protocol"] = on
	values["auto_apply"] = true
	raw, err = json.Marshal(values)
	if err != nil {
		t.Fatal(err)
	}
	s := m.sources[source]
	if err = json.Unmarshal(raw, &s); err != nil {
		t.Fatal(err)
	}
	m.sources[source] = s
}

func TestUnconfirmedProtocolOptInUsesTwoTCPAttemptsAndHonestEvidence(t *testing.T) {
	m, q, original, alternative := webManager(t, 200, normalPage)
	for _, e := range m.events {
		e.originalMetadata.Protocol = ""
		e.originalMetadata.SniffedALPN = nil
	}
	protocolRiskSource(t, m, q.Source, true)
	result, err := m.Probe(context.Background(), q)
	if err != nil {
		t.Fatal(err)
	}
	d := result.(Decision)
	if d.Status != "applied" || d.Target != "direct-out" || d.Evidence != "unverified_protocol_tcp_reachable" {
		t.Fatalf("explicit risk opt-in ignored or misrepresented: %+v", d)
	}
	if original.calls.Load() != 0 || alternative.calls.Load() != 2 {
		t.Fatalf("unexpected attempts: %d/%d", original.calls.Load(), alternative.calls.Load())
	}
	for _, a := range d.Attempts {
		if a.Status == "transport_reachable" && (a.Method != "TCP" || a.TLSVerified || a.BodyBytes != 0 || a.HTTPStatus != 0) {
			t.Fatalf("TCP advertised as verified protocol: %+v", a)
		}
	}
}

func TestUnconfirmedProtocolRemainsBlockedByDefaultAndForUDP(t *testing.T) {
	for _, udp := range []bool{false, true} {
		m, q, _, alternative := webManager(t, 200, normalPage)
		for _, e := range m.events {
			e.originalMetadata.Protocol = ""
			e.originalMetadata.SniffedALPN = nil
			if udp {
				e.Network = "udp"
				e.originalMetadata.Network = "udp"
			}
		}
		protocolRiskSource(t, m, q.Source, udp)
		result, err := m.Probe(context.Background(), q)
		if err != nil {
			t.Fatal(err)
		}
		d := result.(Decision)
		if d.Status == "applied" || d.Status == "proposed" || alternative.calls.Load() != 0 || len(m.leases) != 0 {
			t.Fatalf("default/UDP protection changed: %+v", d)
		}
	}
}

func TestProtocolOptInDoesNotReplaceIPOnlyPreference(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	for _, e := range m.events {
		e.originalMetadata.Protocol = ""
		e.originalMetadata.SniffedALPN = nil
	}
	protocolRiskSource(t, m, q.Source, true)
	q.Domain = ""
	result, err := m.Probe(context.Background(), q)
	if err == nil {
		if d, ok := result.(Decision); ok && (d.Status == "applied" || d.AutoApplyEligible) {
			t.Fatalf("IP-only preference bypassed: %+v", d)
		}
	}
	if len(m.leases) != 0 {
		t.Fatal("IP-only grant created without separate opt-in")
	}
}

func TestProtocolOptInDoesNotBypassKnownTLSIdentity(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	protocolRiskSource(t, m, q.Source, true)
	m.ctx = service.ContextWith[adapter.CertificateStore](m.ctx, &testRoots{pool: x509.NewCertPool()})
	result, err := m.Probe(context.Background(), q)
	if err != nil {
		t.Fatal(err)
	}
	d := result.(Decision)
	if d.Status == "applied" || d.Status == "proposed" || len(m.leases) != 0 {
		t.Fatalf("TLS identity bypassed: %+v", d)
	}
	for _, a := range d.Attempts {
		if a.Status == "transport_reachable" {
			t.Fatal("known TLS failure downgraded to TCP proof")
		}
	}
}

func TestRiskProposalCannotBeAppliedAfterOptOut(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	for _, e := range m.events {
		e.originalMetadata.Protocol = ""
		e.originalMetadata.SniffedALPN = nil
	}
	protocolRiskSource(t, m, q.Source, true)
	source := m.sources[q.Source]
	source.AutoApply = false
	m.sources[q.Source] = source
	result, err := m.Probe(context.Background(), q)
	if err != nil {
		t.Fatal(err)
	}
	d := result.(Decision)
	if d.Status != "proposed" {
		t.Fatalf("missing risk proposal: %+v", d)
	}
	protocolRiskSource(t, m, q.Source, false)
	if _, err = m.Apply(context.Background(), d.ID); err == nil || len(m.leases) != 0 {
		t.Fatal("stale opt-in granted a rule")
	}
}

type pendingProtocolConn struct{ net.Conn }

func (c *pendingProtocolConn) NeedHandshakeForWrite() bool { return true }

type pendingProtocolOutbound struct{ adapter.Outbound }

func (o *pendingProtocolOutbound) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	conn, err := o.Outbound.DialContext(ctx, network, destination)
	if err != nil {
		return nil, err
	}
	return &pendingProtocolConn{Conn: conn}, nil
}
func TestProtocolRiskDoesNotCountDeferredProxyHandshakeAsConnectedTCP(t *testing.T) {
	m, q, _, alternative := webManager(t, 200, normalPage)
	for _, e := range m.events {
		e.originalMetadata.Protocol = ""
		e.originalMetadata.SniffedALPN = nil
	}
	protocolRiskSource(t, m, q.Source, true)
	original := m.Outbound
	m.Outbound = func(tag string) (adapter.Outbound, bool) {
		if tag == "direct-out" {
			return &pendingProtocolOutbound{Outbound: alternative}, true
		}
		return original(tag)
	}
	result, err := m.Probe(context.Background(), q)
	if err != nil {
		t.Fatal(err)
	}
	d := result.(Decision)
	if d.Status == "applied" || d.Status == "proposed" || len(m.leases) != 0 {
		t.Fatalf("unestablished proxy counted as connected TCP: %+v", d)
	}
}

func TestEnablingProtocolRiskRechecksRestoredUnconfirmedPending(t *testing.T) {
	m, q, _, alternative := webManager(t, 200, normalPage)
	for _, e := range m.events {
		e.originalMetadata.Protocol = ""
		e.originalMetadata.SniffedALPN = nil
	}
	result, err := m.Probe(context.Background(), q)
	if err != nil {
		t.Fatal(err)
	}
	if result.(Decision).Reason != "protocol_unconfirmed" {
		t.Fatal("missing retained protocol failure")
	}
	saved := m.checkpoint()
	if len(saved) != 1 {
		t.Fatalf("unexpected checkpoint count %d", len(saved))
	}
	raw, err := json.Marshal(saved[0])
	if err != nil {
		t.Fatal(err)
	}
	protocolRiskSource(t, m, q.Source, true)
	source := m.sources[q.Source]
	source.Pending = []json.RawMessage{raw}
	restored := New(m.ctx, []option.KabanmaxAutoSource{source})
	defer restored.Close()
	restored.Outbound = m.Outbound
	restored.Match = m.Match
	restored.Lookup = m.Lookup
	restored.LogFailure = m.LogFailure
	restored.Sweep(context.Background())
	if len(restored.leases) != 1 || alternative.calls.Load() != 2 {
		t.Fatalf("existing Pending was not reconsidered after opt-in: leases=%d calls=%d", len(restored.leases), alternative.calls.Load())
	}
}
