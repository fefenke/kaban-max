package route

import (
	"net/netip"
	"testing"

	"github.com/sagernet/sing-box/adapter"
	M "github.com/sagernet/sing/common/metadata"
)

func TestKabanmaxFakeIPSniffIdentity(t *testing.T) {
	for _, network := range []string{"tcp", "udp"} {
		t.Run(network, func(t *testing.T) {
			origin := M.Socksaddr{Addr: netip.MustParseAddr("198.18.0.8"), Port: 443}
			metadata := adapter.InboundContext{
				Network: network, FakeIP: true, OriginDestination: origin,
				Destination: M.Socksaddr{Fqdn: "stale.example", Port: 443},
				Domain: "actual.example", Protocol: "tls",
				DestinationAddresses: []netip.Addr{netip.MustParseAddr("203.0.113.8")},
			}
			kabanmaxReconcileFakeIPIdentity(&metadata)
			if metadata.Destination.Fqdn != "actual.example" || len(metadata.DestinationAddresses) != 0 {
				t.Fatalf("stale FakeIP destination retained: %+v", metadata)
			}
			if metadata.OriginDestination != origin || metadata.Destination.Port != 443 || !metadata.FakeIP {
				t.Fatal("lost original FakeIP mapping required by packet NAT")
			}
		})
	}
	for _, fake := range []bool{false, true} {
		metadata := adapter.InboundContext{FakeIP: fake,
			Destination: M.Socksaddr{Fqdn: "explicit.example", Port: 443}}
		if !fake { metadata.Domain = "sniffed.example" }
		kabanmaxReconcileFakeIPIdentity(&metadata)
		if metadata.Destination.Fqdn != "explicit.example" {
			t.Fatal("overrode explicit destination or used missing sniff identity")
		}
	}
}
