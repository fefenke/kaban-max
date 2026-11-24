package autoroute

import "testing"

func TestBenchmarkFakeIPv6NeverBecomesPublicAutorouteEvidence(t *testing.T) {
	m := new(Manager)
	for _, address := range []string{"2001:2::2", "2001:2::ffff", "2001:2:0:ffff::1", "fc00::2", "198.18.0.2"} {
		if !m.protected(Query{IP: address, Domain: "example.com"}) {
			t.Fatalf("synthetic/benchmark address admitted: %s", address)
		}
	}
	if m.protected(Query{IP: "2606:4700:4700::1111", Domain: "example.com"}) {
		t.Fatal("real public IPv6 blocked")
	}
}
