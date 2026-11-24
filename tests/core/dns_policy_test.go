// Runs in package dns on clean UPSTREAM+patches with generated ucode fixtures.
package dns

import (
	"context"
	"net/netip"
	"os"
	"path/filepath"
	"testing"

	mDNS "github.com/miekg/dns"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	R "github.com/sagernet/sing-box/route/rule"
	"github.com/sagernet/sing/common/json"
	M "github.com/sagernet/sing/common/metadata"
	"github.com/sagernet/sing/service"
	"github.com/stretchr/testify/require"
)

type policyRuleSets struct {
	adapter.Router
	sets map[string]adapter.RuleSet
}

func (r *policyRuleSets) RuleSet(tag string) (adapter.RuleSet, bool) {
	set, ok := r.sets[tag]
	return set, ok
}

func policyRules(t *testing.T, mode, setKind string) []adapter.DNSRule {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("/fixtures", mode+".json"))
	require.NoError(t, err)
	var config struct {
		DNS struct {
			Rules []option.DNSRule `json:"rules"`
		} `json:"dns"`
		Route struct {
			Sets []option.RuleSet `json:"rule_set"`
		} `json:"route"`
	}
	require.NoError(t, json.UnmarshalContext(context.Background(), raw, &config))
	router := &policyRuleSets{sets: make(map[string]adapter.RuleSet)}
	ctx := service.ContextWith[adapter.Router](context.Background(), router)
	for _, set := range config.Route.Sets {
		content := `{"type":"inline","tag":"fixture","rules":[{"ip_cidr":["203.0.113.0/24","2001:db9::/32"]}]}`
		if setKind == "mixed" {
			content = `{"type":"inline","tag":"fixture","rules":[{"ip_cidr":["203.0.113.0/24","2001:db9::/32"]},{"domain_suffix":["bypass.example.org"]}]}`
		}
		var inline option.RuleSet
		require.NoError(t, json.Unmarshal([]byte(content), &inline))
		for _, tag := range set.Tag {
			local, err := R.NewRuleSet(ctx, log.NewNOPFactory().Logger(), tag, inline)
			require.NoError(t, err)
			router.sets[tag] = local
			t.Cleanup(func() { local.Close() })
		}
	}
	var rules []adapter.DNSRule
	for _, rawRule := range config.DNS.Rules {
		rule, err := R.NewDNSRule(ctx, log.NewNOPFactory().Logger(), rawRule, true, false)
		require.NoError(t, err)
		require.NoError(t, rule.Start())
		t.Cleanup(func() { rule.Close() })
		rules = append(rules, rule)
	}
	// The same validation used at startup must accept the generated response bindings.
	_, err = validateLegacyDNSModeDisabledRules(router, config.DNS.Rules, nil)
	require.NoError(t, err)
	return rules
}

func TestKabanmaxGeneratedDNSBypass(t *testing.T) {
	for _, scenario := range []struct {
		name, mode, setKind, domain, source, address, want string
		qtype                                              uint16
	}{
		{"inline IPv4", "policy", "mixed", "www.example.org", "192.0.2.7", "192.0.2.4", "main", mDNS.TypeA},
		{"inline IPv6", "policy", "mixed", "www.example.org", "192.0.2.7", "2001:db8::4", "main", mDNS.TypeAAAA},
		{"IP-only SRS IPv4", "srs-only", "ip-only", "www.example.org", "192.0.2.7", "203.0.113.4", "main", mDNS.TypeA},
		{"IP-only SRS IPv6", "srs-only", "ip-only", "www.example.org", "192.0.2.7", "2001:db9::4", "main", mDNS.TypeAAAA},
		{"mixed SRS IP branch", "srs-only", "mixed", "www.example.org", "192.0.2.7", "203.0.113.4", "main", mDNS.TypeA},
		{"mixed SRS domain branch", "srs-only", "mixed", "bypass.example.org", "192.0.2.7", "198.51.100.4", "main", mDNS.TypeA},
		{"IP miss keeps FakeIP", "policy", "ip-only", "www.example.org", "192.0.2.7", "198.51.100.4", "fake", mDNS.TypeA},
		{"IPv6 miss keeps FakeIP", "policy", "ip-only", "www.example.org", "192.0.2.7", "2001:dba::4", "fake", mDNS.TypeAAAA},
		{"other device keeps FakeIP", "policy", "mixed", "www.example.org", "192.0.2.8", "192.0.2.4", "fake", mDNS.TypeA},
		{"earlier section keeps FakeIP", "priority", "mixed", "www.example.org", "192.0.2.7", "192.0.2.4", "fake", mDNS.TypeA},
		{"ports cannot select DNS answer", "ports", "ip-only", "www.example.org", "192.0.2.7", "192.0.2.4", "fake", mDNS.TypeA},
		{"local zone is not evaluated", "policy", "mixed", "host.lan", "192.0.2.7", "192.0.2.4", "local", mDNS.TypeA},
		{"detour off preserves Bypass", "detour-off", "mixed", "www.example.org", "192.0.2.7", "192.0.2.4", "main", mDNS.TypeA},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			main := &fakeDNSTransport{tag: "dns-server", address: netip.MustParseAddr(scenario.address)}
			fake := &fakeDNSTransport{tag: "fakeip-server", address: netip.MustParseAddr("198.18.0.7")}
			if scenario.qtype == mDNS.TypeAAAA {
				fake.address = netip.MustParseAddr("2001:2::7")
			}
			local := &fakeDNSTransport{tag: "dnsmasq-server", address: netip.MustParseAddr("192.0.2.1")}
			bootstrap := &fakeDNSTransport{tag: "bootstrap-dns-server", address: netip.MustParseAddr("198.51.100.99")}
			router := raceTestRouter(t, main, fake, local, bootstrap)
			rules := policyRules(t, scenario.mode, scenario.setKind)
			message := new(mDNS.Msg)
			message.SetQuestion(scenario.domain+".", scenario.qtype)
			metadata := &adapter.InboundContext{Domain: scenario.domain, QueryType: scenario.qtype,
				Inbound: "source-dns-in", Source: M.Socksaddr{Addr: netip.MustParseAddr(scenario.source), Port: 12345}}
			result := router.exchangeWithRules(adapter.WithContext(context.Background(), metadata), rules, message, adapter.DNSQueryOptions{}, true)
			require.NoError(t, result.err)
			want := map[string]*fakeDNSTransport{"main": main, "fake": fake, "local": local}[scenario.want]
			require.Equal(t, want.tag, result.transport.Tag())
			require.NotNil(t, result.response)
			require.EqualValues(t, 0, bootstrap.queryCount.Load(), "user domains must never fall back to bootstrap")
			if scenario.want == "local" || scenario.mode == "priority" || scenario.source == "192.0.2.8" {
				require.EqualValues(t, 0, main.queryCount.Load(), "device/order/local constraints prevent speculative lookups")
			}
		})
	}
}

func TestKabanmaxGeneratedDNSFailureDoesNotUseBootstrap(t *testing.T) {
	main := &fakeDNSTransport{tag: "dns-server", exchangeErr: context.DeadlineExceeded}
	fake := &fakeDNSTransport{tag: "fakeip-server", address: netip.MustParseAddr("198.18.0.7")}
	bootstrap := &fakeDNSTransport{tag: "bootstrap-dns-server", address: netip.MustParseAddr("198.51.100.99")}
	router := raceTestRouter(t, main, fake, bootstrap)
	message := new(mDNS.Msg)
	message.SetQuestion("www.example.org.", mDNS.TypeA)
	metadata := &adapter.InboundContext{Domain: "www.example.org", QueryType: mDNS.TypeA, Inbound: "source-dns-in",
		Source: M.Socksaddr{Addr: netip.MustParseAddr("192.0.2.7"), Port: 12345}}
	result := router.exchangeWithRules(adapter.WithContext(context.Background(), metadata), policyRules(t, "policy", "ip-only"), message, adapter.DNSQueryOptions{}, true)
	// A failed real lookup may still yield FakeIP for the protected proxy; it cannot yield a real Direct answer.
	if result.err == nil {
		require.Equal(t, "fakeip-server", result.transport.Tag())
	}
	require.EqualValues(t, 0, bootstrap.queryCount.Load())
}
