package wanstate

import (
	"strings"
	"testing"
)

func TestWANOutageEmitsOnlyDownAndRecovery(t *testing.T) {
	var events []string
	m := New(func(message string) { events = append(events, message) })
	close := Install(m)
	defer close()
	m.Observe(Sample{Available: true, Reason: "verified response"})
	m.Observe(Sample{Reason: "wan carrier=0; both external checks timed out"})
	if Suppress("dns", "server dns: exchange failed for a.example. IN A: timeout") {
		t.Fatal("one failed round must not hide logs")
	}
	m.Observe(Sample{Reason: "wan carrier=0; both external checks timed out"})
	for i := 0; i < 5; i++ {
		if !Suppress("dns", "server dns: exchange failed for a.example. IN A: timeout") {
			t.Fatal("DNS leaked during outage")
		}
		if !Suppress("vless[server]", "connection: TLS handshake timeout") {
			t.Fatal("VLESS leaked during outage")
		}
		if !Suppress("wireguard[warp]", "Handshake did not complete") {
			t.Fatal("WARP leaked during outage")
		}
		if !Suppress("vless[server]", "tls: protocol version not supported") {
			t.Fatal("TLS error leaked during outage")
		}
		if !Suppress("vless[server]", "authentication failed") {
			t.Fatal("transport auth error leaked during outage")
		}
		m.Observe(Sample{Reason: "still unavailable"})
	}
	if len(events) != 1 || !strings.Contains(events[0], "carrier=0") {
		t.Fatalf("missing initial reason or periodic spam: %q", events)
	}
	m.Observe(Sample{Available: true, Reason: "verified Cloudflare response"})
	if len(events) != 2 || !strings.Contains(events[1], "restored") || !strings.Contains(events[1], "suppressed=25") {
		t.Fatalf("unexpected recovery: %q", events)
	}
	if Suppress("dns", "exchange failed for a.example: timeout") {
		t.Fatal("logs stayed suppressed after recovery")
	}
}

func TestUnknownEvidenceAndConfigurationErrorsAreNotNetworkOutages(t *testing.T) {
	m := New(func(string) {})
	close := Install(m)
	defer close()
	m.Observe(Sample{Unknown: true, Reason: "TLS trust store unavailable"})
	m.Observe(Sample{Unknown: true, Reason: "TLS trust store unavailable"})
	if Suppress("dns", "exchange failed for a.example: timeout") {
		t.Fatal("unknown evidence hid logs")
	}
	m.Observe(Sample{Reason: "failed"})
	m.Observe(Sample{Reason: "failed"})
	for _, message := range []string{"WAN unavailable: first event", "WAN restored: second event", "configuration parse error", "out of memory", "authentication failed", "certificate expired", "save checkpoint failed", "permission denied opening socket"} {
		if Suppress("router", message) {
			t.Fatalf("unrelated/critical event hidden: %s", message)
		}
	}
}

func TestDNSQuestionTextCannotDisableWANSuppression(t *testing.T) {
	m := New(func(string) {})
	close := Install(m)
	defer close()
	m.Observe(Sample{Reason: "failed"})
	m.Observe(Sample{Reason: "failed"})
	if !Suppress("dns", "exchange failed for classroom.authentication.example. IN A: timeout") {
		t.Fatal("domain text bypassed outage gate")
	}
	if !Suppress("dns", "DNS failure grouping limit reached (256 active questions)") {
		t.Fatal("overflow warning leaked during outage")
	}
	m.Observe(Sample{Unknown: true, Reason: "monitor temporarily unknown"})
	if !Suppress("dns", "exchange failed for one.example. IN A: timeout") {
		t.Fatal("unknown is not verified recovery")
	}
}

func TestConnectionFailureWakeupsAreCoalesced(t *testing.T) {
	m := New(func(string) {})
	close := Install(m)
	defer close()
	for i := 0; i < 10000; i++ {
		RequestCheck()
	}
	if len(m.wake) != 1 {
		t.Fatal("unbounded connection-failure work queue")
	}
}
