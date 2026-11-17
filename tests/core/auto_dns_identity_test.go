package route

import (
	"fmt"
	"net/netip"
	"testing"

	"github.com/miekg/dns"
)

func TestKabanmaxDNSAttestedIdentity(t *testing.T) {
	tests := []struct {
		name    string
		qtype   uint16
		answers []string
		want    []string
		ttl     uint32
		bad     bool
	}{
		{"direct", dns.TypeA, []string{"app.example. 120 IN A 203.0.113.2"}, []string{"203.0.113.2"}, 120, false},
		{"rooted unordered chain", dns.TypeA, []string{"edge.example. 90 IN A 203.0.113.2", "middle.example. 30 IN CNAME edge.example.", "APP.example. 60 IN CNAME Middle.example."}, []string{"203.0.113.2"}, 30, false},
		{"ipv6 chain", dns.TypeAAAA, []string{"app.example. 180 IN CNAME edge.example.", "edge.example. 120 IN AAAA 2001:db8::2"}, []string{"2001:db8::2"}, 120, false},
		{"cname only no AAAA", dns.TypeAAAA, []string{"app.example. 180 IN CNAME edge.example."}, nil, 180, false},
		{"empty no data", dns.TypeAAAA, nil, nil, 900, false},
		{"zero chain ttl", dns.TypeA, []string{"app.example. 0 IN CNAME edge.example.", "edge.example. 120 IN A 203.0.113.2"}, []string{"203.0.113.2"}, 0, false},
		{"multiple addresses", dns.TypeA, []string{"app.example. 50 IN CNAME edge.example.", "edge.example. 100 IN A 203.0.113.2", "edge.example. 20 IN A 203.0.113.3"}, []string{"203.0.113.2", "203.0.113.3"}, 20, false},
		{"unrelated address", dns.TypeA, []string{"app.example. 60 IN CNAME edge.example.", "foreign.example. 60 IN A 203.0.113.2"}, nil, 0, true},
		{"injected other family", dns.TypeA, []string{"app.example. 60 IN A 203.0.113.2", "app.example. 60 IN AAAA 2001:db8::2"}, nil, 0, true},
		{"unrooted alias", dns.TypeA, []string{"foreign.example. 60 IN CNAME edge.example.", "edge.example. 60 IN A 203.0.113.2"}, nil, 0, true},
		{"unrelated alias", dns.TypeA, []string{"app.example. 60 IN A 203.0.113.2", "foreign.example. 60 IN CNAME edge.example."}, nil, 0, true},
		{"loop", dns.TypeA, []string{"app.example. 60 IN CNAME edge.example.", "edge.example. 60 IN CNAME app.example."}, nil, 0, true},
		{"conflicting aliases", dns.TypeA, []string{"app.example. 60 IN CNAME edge.example.", "app.example. 60 IN CNAME foreign.example."}, nil, 0, true},
		{"address at alias owner", dns.TypeA, []string{"app.example. 60 IN CNAME edge.example.", "app.example. 60 IN A 203.0.113.2"}, nil, 0, true},
		{"non IN address", dns.TypeA, []string{"app.example. 60 CH A 203.0.113.2"}, nil, 0, true},
		{"non IN alias", dns.TypeA, []string{"app.example. 60 CH CNAME edge.example."}, nil, 0, true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			reply := new(dns.Msg)
			for _, text := range tc.answers {
				rr, err := dns.NewRR(text)
				if err != nil {
					t.Fatal(err)
				}
				reply.Answer = append(reply.Answer, rr)
			}
			got, ttl, err := kabanmaxDNSIdentity(reply, "app.example", tc.qtype)
			if tc.bad {
				if err == nil || len(got) != 0 {
					t.Fatalf("unattested answer admitted: %v ttl=%d err=%v", got, ttl, err)
				}
				return
			}
			if err != nil || ttl != tc.ttl || len(got) != len(tc.want) {
				t.Fatalf("got %v ttl=%d err=%v; want %v ttl=%d", got, ttl, err, tc.want, tc.ttl)
			}
			for i, address := range tc.want {
				if got[i] != netip.MustParseAddr(address) {
					t.Fatalf("got %v want %v", got, tc.want)
				}
			}
		})
	}
}

func TestKabanmaxDNSIdentityChainBound(t *testing.T) {
	for _, count := range []int{8, 9} {
		reply := new(dns.Msg)
		owner := "app.example."
		for i := 0; i < count; i++ {
			next := fmt.Sprintf("alias%d.example.", i)
			rr, _ := dns.NewRR(fmt.Sprintf("%s 60 IN CNAME %s", owner, next))
			reply.Answer = append(reply.Answer, rr)
			owner = next
		}
		rr, _ := dns.NewRR(owner + " 120 IN A 203.0.113.2")
		reply.Answer = append(reply.Answer, rr)
		addresses, _, err := kabanmaxDNSIdentity(reply, "app.example", dns.TypeA)
		if count == 8 && (err != nil || len(addresses) != 1) {
			t.Fatalf("bounded chain rejected: %v", err)
		}
		if count == 9 && err == nil {
			t.Fatal("excessive chain admitted")
		}
	}
}
