package main

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"strings"
	"testing"
	"time"

	mDNS "github.com/miekg/dns"
	"github.com/stretchr/testify/require"
)

// Actual FakeIP transport/store and DNS inbound, not the walker transport mock.
func TestKabanmaxGeneratedDNSMixedRealFakeIP(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	upstream := &mDNS.Server{Listener: listener, Handler: mDNS.HandlerFunc(func(w mDNS.ResponseWriter, request *mDNS.Msg) {
		response := new(mDNS.Msg)
		response.SetReply(request)
		response.Answer = []mDNS.RR{
			&mDNS.A{Hdr: mDNS.RR_Header{Name: request.Question[0].Name, Rrtype: mDNS.TypeA, Class: mDNS.ClassINET, Ttl: 1}, A: net.ParseIP("203.0.113.7").To4()},
			&mDNS.A{Hdr: mDNS.RR_Header{Name: request.Question[0].Name, Rrtype: mDNS.TypeA, Class: mDNS.ClassINET, Ttl: 1}, A: net.ParseIP("198.51.100.7").To4()},
		}
		_ = w.WriteMsg(response)
	})}
	go upstream.ActivateAndServe()
	defer upstream.Shutdown()
	probe, err := net.ListenPacket("udp", "127.0.0.1:0")
	require.NoError(t, err)
	port := probe.LocalAddr().(*net.UDPAddr).Port
	probe.Close()
	raw, err := os.ReadFile("/fixtures/detour-off.json")
	require.NoError(t, err)
	// Only transplant source addresses and privileged listener/socket options.
	raw = []byte(strings.ReplaceAll(strings.ReplaceAll(string(raw), "192.0.2.7/32", "127.0.0.1/32"), "192.0.2.0/24", "127.0.0.0/8"))
	var config map[string]any
	require.NoError(t, json.Unmarshal(raw, &config))
	config["inbounds"] = []any{map[string]any{"type": "direct", "tag": "source-dns-in", "listen": "127.0.0.1", "listen_port": port, "network": "udp"}}
	config["log"] = map[string]any{"disabled": true}
	delete(config, "experimental")
	route := config["route"].(map[string]any)
	delete(route, "default_mark")
	for _, entry := range route["rule_set"].([]any) {
		set := entry.(map[string]any)
		set["type"] = "inline"
		delete(set, "path")
		delete(set, "format")
		set["rules"] = []any{map[string]any{"ip_cidr": []string{"203.0.113.0/24"}}}
	}
	for _, entry := range config["dns"].(map[string]any)["servers"].([]any) {
		server := entry.(map[string]any)
		if server["tag"] == "dns-server" {
			server["type"] = "tcp"
			server["server"] = "127.0.0.1"
			server["server_port"] = listener.Addr().(*net.TCPAddr).Port
			delete(server, "path")
			delete(server, "domain_resolver")
		}
	}
	raw, err = json.Marshal(config)
	require.NoError(t, err)
	instance, _ := stableReloadTestBox(t, raw)
	require.NoError(t, instance.Start())
	message := new(mDNS.Msg)
	message.SetQuestion("mixed.example.org.", mDNS.TypeA)
	response, _, err := (&mDNS.Client{Net: "udp", Timeout: time.Second}).Exchange(message, net.JoinHostPort("127.0.0.1", fmt.Sprint(port)))
	require.NoError(t, err)
	require.Equal(t, mDNS.RcodeSuccess, response.Rcode)
	require.NotEmpty(t, response.Answer)
	answer, ok := response.Answer[0].(*mDNS.A)
	require.True(t, ok)
	_, prefix, err := net.ParseCIDR("198.18.0.0/16")
	require.NoError(t, err)
	require.True(t, prefix.Contains(answer.A), "a mixed real response must not expose the protected real address outside capture")
}
