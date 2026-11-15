package route

import (
	"context"
	"errors"
	"net/http"
	"net/netip"
	"os"
	"testing"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	R "github.com/sagernet/sing-box/route/rule"
	"github.com/sagernet/sing/common/json"
	"github.com/sagernet/sing/common/logger"
	M "github.com/sagernet/sing/common/metadata"
	"github.com/sagernet/sing/service"
	"github.com/stretchr/testify/require"
)

type mixedRouteSets struct {
	adapter.Router
	sets map[string]adapter.RuleSet
}

func (r *mixedRouteSets) RuleSet(tag string) (adapter.RuleSet, bool) {
	s, ok := r.sets[tag]
	return s, ok
}

type mixedRouteDNS struct{ adapter.DNSTransportManager }

func (*mixedRouteDNS) FakeIP() adapter.FakeIPTransport { return nil }
func (*mixedRouteDNS) Transport(string) (adapter.DNSTransport, bool) {
	return &mixedLookupTransport{}, true
}

type mixedLookupTransport struct{ adapter.DNSTransport }

func (*mixedLookupTransport) Tag() string { return "dns-server" }

type mixedLookup struct {
	adapter.DNSRouter
	addresses []netip.Addr
	err       error
}

func (r *mixedLookup) Lookup(context.Context, string, adapter.DNSQueryOptions) ([]netip.Addr, error) {
	return append([]netip.Addr(nil), r.addresses...), r.err
}

type unavailableHTTP struct{ adapter.HTTPClientManager }
type unavailableTransport struct{ *http.Transport }

func (*unavailableTransport) RoundTrip(*http.Request) (*http.Response, error) {
	return nil, errors.New("synthetic VPN unavailable")
}
func (t *unavailableTransport) Reset() { t.CloseIdleConnections() }
func (*unavailableHTTP) ResolveTransport(context.Context, logger.ContextLogger, option.HTTPClientOptions) (adapter.HTTPTransport, error) {
	return &unavailableTransport{&http.Transport{}}, nil
}

func TestKabanmaxUnavailableRouteRejectsOnlyItsDevices(t *testing.T) {
	ctx := service.ContextWith[adapter.HTTPClientManager](context.Background(), &unavailableHTTP{})
	var spec option.RuleSet
	require.NoError(t, json.Unmarshal([]byte(`{"type":"remote","tag":"protected","format":"source","url":"https://rules.example/protected.json","http_client":{"detour":"vpn"}}`), &spec))
	set, err := R.NewRemoteRuleSet(ctx, log.NewNOPFactory().Logger(), "protected", spec)
	require.NoError(t, err)
	require.NoError(t, set.StartContext(ctx, adapter.NewHTTPStartContext()))
	defer set.Close()
	ctx = service.ContextWith[adapter.Router](ctx, &mixedRouteSets{sets: map[string]adapter.RuleSet{"protected": set}})
	for _, outbound := range []string{"proxy", "direct-out"} {
		var opts option.Rule
		require.NoError(t, json.Unmarshal([]byte(`{"type":"logical","mode":"and","rules":[{"rule_set":"protected"},{"source_ip_cidr":"192.0.2.7/32"}],"action":"route","outbound":"`+outbound+`"}`), &opts))
		rule, err := R.NewRule(ctx, log.NewNOPFactory().Logger(), opts, true)
		require.NoError(t, err)
		require.NoError(t, rule.Start())
		defer rule.Close()
		router := &Router{ctx: ctx, logger: log.NewNOPFactory().Logger(), dnsTransport: &mixedRouteDNS{}, rules: []adapter.Rule{rule}}
		for _, source := range []string{"192.0.2.7:12345", "192.0.2.8:12345"} {
			for _, resolved := range []bool{false, true} {
				metadata := &adapter.InboundContext{Domain: "www.example.org", Source: M.ParseSocksaddr(source), Destination: M.ParseSocksaddr("198.51.100.7:443")}
				if resolved {
					metadata.Destination = M.Socksaddr{Fqdn: metadata.Domain, Port: 443}
					metadata.DestinationAddresses = []netip.Addr{netip.MustParseAddr("198.51.100.7")}
				}
				selected, _, _, _, err := router.matchRule(ctx, metadata, nil, nil)
				require.Nil(t, selected)
				if source == "192.0.2.7:12345" {
					require.ErrorContains(t, err, "remote rule-set unavailable")
				} else {
					require.NoError(t, err)
				}
			}
		}
	}
}

func TestKabanmaxMixedGeneratedRoutes(t *testing.T) {
	for _, mode := range []string{"policy", "srs-only", "priority", "detour-off", "resolve-all", "resolve-selected"} {
		t.Run(mode, func(t *testing.T) {
			raw, err := os.ReadFile("/fixtures/" + mode + ".json")
			require.NoError(t, err)
			var config struct {
				Route struct {
					Rules []option.Rule    `json:"rules"`
					Sets  []option.RuleSet `json:"rule_set"`
				} `json:"route"`
			}
			require.NoError(t, json.Unmarshal(raw, &config))
			sets := &mixedRouteSets{sets: map[string]adapter.RuleSet{}}
			ctx := service.ContextWith[adapter.Router](context.Background(), sets)
			for _, spec := range config.Route.Sets {
				var inline option.RuleSet
				require.NoError(t, json.Unmarshal([]byte(`{"type":"inline","tag":"fixture","rules":[{"ip_cidr":["203.0.113.0/24"]}]}`), &inline))
				for _, tag := range spec.Tag {
					s, err := R.NewRuleSet(ctx, log.NewNOPFactory().Logger(), tag, inline)
					require.NoError(t, err)
					sets.sets[tag] = s
					t.Cleanup(func() { s.Close() })
				}
			}
			lookup := &mixedLookup{addresses: []netip.Addr{netip.MustParseAddr("203.0.113.7"), netip.MustParseAddr("198.51.100.7"), netip.MustParseAddr("2001:dba::7")}}
			router := &Router{ctx: ctx, logger: log.NewNOPFactory().Logger(), dnsTransport: &mixedRouteDNS{}, dns: lookup}
			for _, spec := range config.Route.Rules {
				// Run generated resolve actions against synthetic lookup results.
				action := spec.DefaultOptions.Action
				if spec.Type == "logical" {
					action = spec.LogicalOptions.Action
				}
				if action != "route" && action != "reject" && action != "resolve" {
					continue
				}
				rule, err := R.NewRule(ctx, log.NewNOPFactory().Logger(), spec, true)
				require.NoError(t, err)
				require.NoError(t, rule.Start())
				t.Cleanup(func() { rule.Close() })
				router.rules = append(router.rules, rule)
			}
			for _, ip := range []string{"203.0.113.7", "198.51.100.7", "2001:dba::7", "203.0.113.8", "198.51.100.8"} {
				metadata := &adapter.InboundContext{Domain: "www.example.org", Inbound: "tproxy-in", Source: M.ParseSocksaddr("192.0.2.7:12345"), Destination: M.Socksaddr{Addr: netip.MustParseAddr(ip), Port: 443}}
				rule, _, _, _, err := router.matchRule(ctx, metadata, nil, nil)
				require.NoError(t, err)
				require.NotNil(t, rule)
				want := "proxy"
				if mode != "priority" && netip.MustParsePrefix("203.0.113.0/24").Contains(metadata.Destination.Addr) {
					want = "direct-out"
				}
				require.Equal(t, want, rule.Action().(*R.RuleActionRoute).Outbound)
			}
			metadata := &adapter.InboundContext{Domain: "www.example.org", Inbound: "tproxy-in", Source: M.ParseSocksaddr("192.0.2.7:12345"), Destination: M.Socksaddr{Fqdn: "www.example.org", Port: 443}, FakeIP: true,
				DestinationAddresses: []netip.Addr{netip.MustParseAddr("203.0.113.7"), netip.MustParseAddr("198.51.100.7"), netip.MustParseAddr("2001:dba::7")}}
			rule, _, _, _, err := router.matchRule(ctx, metadata, nil, nil)
			require.NoError(t, err)
			require.NotNil(t, rule)
			if mode == "priority" {
				require.Len(t, metadata.DestinationAddresses, 3)
			} else {
				require.Equal(t, []netip.Addr{netip.MustParseAddr("203.0.113.7")}, metadata.DestinationAddresses)
			}
			metadata.Source = M.ParseSocksaddr("192.0.2.8:12345")
			metadata.DestinationAddresses = []netip.Addr{netip.MustParseAddr("203.0.113.7"), netip.MustParseAddr("198.51.100.7")}
			lookup.addresses = metadata.DestinationAddresses
			rule, _, _, _, err = router.matchRule(ctx, metadata, nil, nil)
			require.NoError(t, err)
			require.NotNil(t, rule)
			require.Equal(t, "proxy", rule.Action().(*R.RuleActionRoute).Outbound)
			require.Len(t, metadata.DestinationAddresses, 2)
			if mode != "priority" {
				lookup.err = errors.New("synthetic protected DNS failure")
				metadata.Source = M.ParseSocksaddr("192.0.2.7:12345")
				metadata.DestinationAddresses = nil
				selected, _, _, _, err := router.matchRule(ctx, metadata, nil, nil)
				require.Error(t, err)
				require.Nil(t, selected, "DNS failure must not fall through to Direct")
			}
		})
	}
}

func TestKabanmaxMixedResolvedRoute(t *testing.T) {
	for _, data := range []struct {
		name, first, domain string
		addresses, want     []string
	}{
		{"mixed A", `"ip_cidr":["203.0.113.0/24"]`, "www.example.org", []string{"203.0.113.7", "198.51.100.7"}, []string{"203.0.113.7"}},
		{"mixed families", `"ip_cidr":["203.0.113.0/24"]`, "www.example.org", []string{"203.0.113.7", "2001:db8::7"}, []string{"203.0.113.7"}},
		{"domain priority", `"domain_suffix":["example.org"]`, "www.example.org", []string{"203.0.113.7", "198.51.100.7"}, []string{"203.0.113.7", "198.51.100.7"}},
	} {
		t.Run(data.name, func(t *testing.T) {
			var opts option.Rule
			require.NoError(t, json.Unmarshal([]byte(`{`+data.first+`,"action":"route","outbound":"direct-out"}`), &opts))
			rule, err := R.NewRule(context.Background(), log.NewNOPFactory().Logger(), opts, true)
			require.NoError(t, err)
			router := &Router{ctx: context.Background(), logger: log.NewNOPFactory().Logger(), rules: []adapter.Rule{rule}}
			for iteration := 0; iteration < 2; iteration++ {
				metadata := &adapter.InboundContext{Domain: data.domain, Destination: M.Socksaddr{Fqdn: data.domain, Port: 443}}
				for _, ip := range data.addresses {
					metadata.DestinationAddresses = append(metadata.DestinationAddresses, netip.MustParseAddr(ip))
				}
				selected, _, _, _, err := router.matchRule(context.Background(), metadata, nil, nil)
				require.NoError(t, err)
				require.Equal(t, rule, selected)
				var got []string
				for _, ip := range metadata.DestinationAddresses {
					got = append(got, ip.String())
				}
				require.Equal(t, data.want, got, "a route must never dial another rule's resolved address")
			}
		})
	}
}
