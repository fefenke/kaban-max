package dns

import (
	"context"
	mDNS "github.com/miekg/dns"
	"github.com/sagernet/sing-box/adapter"
	M "github.com/sagernet/sing/common/metadata"
	"github.com/stretchr/testify/require"
	"net"
	"net/netip"
	"testing"
)

type mixedPolicyTransport struct {
	*fakeDNSTransport
	addresses []string
}

func (t *mixedPolicyTransport) Exchange(ctx context.Context, request *mDNS.Msg) (*mDNS.Msg, error) {
	response := new(mDNS.Msg)
	response.SetReply(request)
	for _, ip := range t.addresses {
		header := mDNS.RR_Header{Name: request.Question[0].Name, Class: mDNS.ClassINET, Ttl: 1}
		if netip.MustParseAddr(ip).Is4() {
			header.Rrtype = mDNS.TypeA
			response.Answer = append(response.Answer, &mDNS.A{Hdr: header, A: net.ParseIP(ip).To4()})
		} else {
			header.Rrtype = mDNS.TypeAAAA
			response.Answer = append(response.Answer, &mDNS.AAAA{Hdr: header, AAAA: net.ParseIP(ip).To16()})
		}
	}
	return response, nil
}
func (t *mixedPolicyTransport) ExchangeAsync(ctx context.Context, request *mDNS.Msg, done func(*mDNS.Msg, error)) {
	done(t.Exchange(ctx, request))
}

func TestKabanmaxGeneratedDNSMixedAnswers(t *testing.T) {
	for _, mode := range []string{"policy", "srs-only", "priority", "detour-off", "resolve-all", "resolve-selected"} {
		t.Run(mode, func(t *testing.T) {
			main := &mixedPolicyTransport{fakeDNSTransport: &fakeDNSTransport{tag: "dns-server"}}
			fake := &fakeDNSTransport{tag: "fakeip-server", address: netip.MustParseAddr("198.18.0.7")}
			router := raceTestRouter(t, fake)
			router.transport.(*fakeDNSTransportManager).transports["dns-server"] = main
			rules := policyRules(t, mode, "ip-only")
			for _, addresses := range [][]string{
				{"203.0.113.7", "198.51.100.7"},
				{"203.0.113.7", "203.0.113.8"},
				{"203.0.113.7", "2001:db9::7"},
				{},
				{"198.51.100.7", "203.0.113.7"},
				{"203.0.113.7", "2001:dba::7"},
				{"198.51.100.7", "2001:dba::7"},
				{"203.0.113.8"},
				{"198.51.100.8"},
			} {
				main.addresses = addresses
				message := new(mDNS.Msg)
				message.SetQuestion("www.example.org.", mDNS.TypeA)
				metadata := &adapter.InboundContext{Domain: "www.example.org", QueryType: mDNS.TypeA, Inbound: "source-dns-in", Source: M.ParseSocksaddr("192.0.2.7:12345")}
				result := router.exchangeWithRules(adapter.WithContext(context.Background(), metadata), rules, message, adapter.DNSQueryOptions{}, true)
				require.NoError(t, result.err)
				bypass := mode != "priority"
				match := false
				all := len(addresses) > 0
				for _, ip := range addresses {
					if netip.MustParsePrefix("203.0.113.0/24").Contains(netip.MustParseAddr(ip)) || netip.MustParsePrefix("2001:db9::/32").Contains(netip.MustParseAddr(ip)) {
						match = true
					} else {
						all = false
					}
				}
				if bypass && match && all {
					require.Equal(t, "dns-server", result.transport.Tag(), "addresses: %v", addresses)
					require.Len(t, result.response.Answer, len(addresses), "DNS returns the complete answer; routing must check each destination")
				} else {
					require.Equal(t, "fakeip-server", result.transport.Tag(), "addresses: %v", addresses)
				}
			}
		})
	}
}
