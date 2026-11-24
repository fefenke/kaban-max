package autoroute

import (
	"context"
	"encoding/json"
	"github.com/sagernet/sing-box/option"
	"net/netip"
	"testing"
)

func TestAppliedIPIsSectionWideAcrossDevicesAndPorts(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	if _, err := manualAPI(m, "s1", manualEvent(m).ID, "direct-out"); err != nil {
		t.Fatal(err)
	}
	for _, network := range []string{"tcp", "udp"} {
		other := q
		other.SourceIP = "192.0.2.99"
		other.Port = 5222
		meta := metadata(other)
		meta.Network = network
		if got := m.Select(context.Background(), q.Source, &meta); got != "direct-out" {
			t.Fatalf("device/IP rule missed %s: %s", network, got)
		}
		if got := m.Select(context.Background(), "unrelated-section", &meta); got != "unrelated-section" {
			t.Fatal("crossed section boundary")
		}
		meta.DestinationAddresses = []netip.Addr{netip.MustParseAddr("203.0.113.99")}
		if got := m.Select(context.Background(), q.Source, &meta); got != q.Source {
			t.Fatal("crossed destination IP boundary")
		}
	}
}

func TestLegacyWebIPApprovalMigratesToAllDevices(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	answer, err := manualAPI(m, "s1", manualEvent(m).ID, "direct-out")
	if err != nil {
		t.Fatal(err)
	}
	l := answer.(Decision).Lease
	raw, _ := json.Marshal(l)
	var legacy map[string]any
	json.Unmarshal(raw, &legacy)
	delete(legacy, "all_devices")
	raw, _ = json.Marshal(legacy)
	source := m.sources[q.Source]
	source.Saved = []json.RawMessage{raw}
	restored := New(context.Background(), []option.KabanmaxAutoSource{source})
	defer restored.Close()
	restored.Outbound = m.Outbound
	restored.Lookup = m.Lookup
	restored.Match = m.Match
	restored.LogFailure = m.LogFailure
	q.SourceIP = "192.0.2.99"
	q.Port = 5222
	meta := metadata(q)
	if got := restored.Select(context.Background(), q.Source, &meta); got != "direct-out" {
		t.Fatal("old applied record remains device-scoped", got)
	}
}

func TestSectionWideGrantStillRespectsActualDeviceExclusion(t *testing.T) {
	m, q, _, _ := webManager(t, 200, normalPage)
	if _, err := manualAPI(m, "s1", manualEvent(m).ID, "direct-out"); err != nil {
		t.Fatal(err)
	}
	q.SourceIP = "192.0.2.99"
	denied := q
	denied.Domain = ""
	m.suppressed[m.key(denied)] = true
	meta := metadata(q)
	if got := m.Select(context.Background(), q.Source, &meta); got != q.Source {
		t.Fatal("section-wide grant overrode explicit exclusion")
	}
}
