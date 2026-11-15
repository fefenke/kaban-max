// Loopback-only integration of generated resolver policy and actual core dialers.
package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	mDNS "github.com/miekg/dns"
	M "github.com/sagernet/sing/common/metadata"
)

func TestKabanmaxGeneratedDNSDialPolicy(t *testing.T) {
	for _, source := range []string{"manual", "provider"} {
		for _, detour := range []bool{false, true} {
			if source == "provider" && !detour {
				continue
			}
			for _, dnsHost := range []string{"dns.example", "127.0.0.1", "::1"} {
				t.Run(fmt.Sprintf("%s/detour=%t/dns=%s", source, detour, dnsHost), func(t *testing.T) {
					var access sync.Mutex
					var bootstrapNames, mainNames []string
					var proxyConnections []net.Conn
					handler := func(bootstrap bool) mDNS.HandlerFunc {
						return func(w mDNS.ResponseWriter, request *mDNS.Msg) {
							name := strings.TrimSuffix(request.Question[0].Name, ".")
							access.Lock()
							if bootstrap {
								bootstrapNames = append(bootstrapNames, name)
							} else {
								mainNames = append(mainNames, name)
							}
							access.Unlock()
							response := new(mDNS.Msg)
							response.SetReply(request)
							address := "127.0.0.1"
							if bootstrap && strings.HasSuffix(name, ".example.org") {
								address = "127.0.0.2"
							} // poisoned direct user DNS
							if request.Question[0].Qtype == mDNS.TypeA {
								response.Answer = []mDNS.RR{&mDNS.A{Hdr: mDNS.RR_Header{Name: request.Question[0].Name, Rrtype: mDNS.TypeA, Class: mDNS.ClassINET, Ttl: 1}, A: net.ParseIP(address)}}
							} else if request.Question[0].Qtype == mDNS.TypeAAAA {
								response.Answer = []mDNS.RR{&mDNS.AAAA{Hdr: mDNS.RR_Header{Name: request.Question[0].Name, Rrtype: mDNS.TypeAAAA, Class: mDNS.ClassINET, Ttl: 1}, AAAA: net.ParseIP("::1")}}
							}
							w.WriteMsg(response)
						}
					}
					bootstrapConn, err := net.ListenPacket("udp", "127.0.0.1:0")
					if err != nil {
						t.Fatal(err)
					}
					bootstrap := &mDNS.Server{PacketConn: bootstrapConn, Handler: handler(true)}
					go bootstrap.ActivateAndServe()
					t.Cleanup(func() { bootstrap.Shutdown() })
					dnsListener, err := net.Listen("tcp", "[::]:0")
					if err != nil {
						t.Fatal(err)
					}
					mainDNS := &mDNS.Server{Listener: dnsListener, Handler: handler(false)}
					go mainDNS.ActivateAndServe()
					t.Cleanup(func() { mainDNS.Shutdown() })
					target, err := net.Listen("tcp", "127.0.0.1:0")
					if err != nil {
						t.Fatal(err)
					}
					t.Cleanup(func() { target.Close() })
					go func() {
						for {
							c, err := target.Accept()
							if err != nil {
								return
							}
							c.Close()
						}
					}()
					proxy, err := net.Listen("tcp", "127.0.0.1:0")
					if err != nil {
						t.Fatal(err)
					}
					t.Cleanup(func() { proxy.Close() })
					go func() {
						for {
							conn, err := proxy.Accept()
							if err != nil {
								return
							}
							access.Lock()
							proxyConnections = append(proxyConnections, conn)
							access.Unlock()
							go policySOCKSConnection(conn)
						}
					}()
					mode := "policy"
					if !detour {
						mode = "detour-off"
					}
					if source == "provider" {
						mode = "provider"
					}
					raw, err := os.ReadFile("/fixtures/" + mode + ".json")
					if err != nil {
						t.Fatal(err)
					}
					var config map[string]any
					if err := json.Unmarshal(raw, &config); err != nil {
						t.Fatal(err)
					}
					config["inbounds"] = []any{}
					config["log"] = map[string]any{"disabled": true}
					delete(config, "experimental")
					route := config["route"].(map[string]any)
					delete(route, "default_mark")
					sets := route["rule_set"].([]any)
					for _, item := range sets {
						set := item.(map[string]any)
						set["type"] = "inline"
						delete(set, "path")
						delete(set, "format")
						set["rules"] = []any{map[string]any{"ip_cidr": []string{"203.0.113.0/24"}}}
					}
					for _, item := range config["dns"].(map[string]any)["servers"].([]any) {
						server := item.(map[string]any)
						switch server["tag"] {
						case "bootstrap-dns-server":
							server["server"] = "127.0.0.1"
							server["server_port"] = bootstrapConn.LocalAddr().(*net.UDPAddr).Port
						case "dns-server":
							server["type"] = "tcp"
							server["server"] = dnsHost
							server["server_port"] = dnsListener.Addr().(*net.TCPAddr).Port
							delete(server, "path")
							if dnsHost == "dns.example" {
								server["domain_resolver"] = "bootstrap-dns-server"
							} else {
								delete(server, "domain_resolver")
							}
						}
					}
					for _, item := range config["outbounds"].([]any) {
						outbound := item.(map[string]any)
						if outbound["type"] == "parser" {
							outbound["link"] = fmt.Sprintf("socks://vpn.example:%d#VPN", proxy.Addr().(*net.TCPAddr).Port)
						}
					}
					if source == "provider" {
						path := t.TempDir() + "/nodes.txt"
						if err := os.WriteFile(path, []byte(fmt.Sprintf("socks://vpn.example:%d#VPN", proxy.Addr().(*net.TCPAddr).Port)), 0600); err != nil {
							t.Fatal(err)
						}
						for _, item := range config["providers"].([]any) {
							item.(map[string]any)["path"] = path
						}
					}
					raw, err = json.Marshal(config)
					if err != nil {
						t.Fatal(err)
					}
					instance, _ := stableReloadTestBox(t, raw)
					if err := instance.Start(); err != nil {
						t.Fatal(err)
					}
					direct, ok := instance.Outbound().Outbound("direct-out")
					if !ok {
						t.Fatal("missing direct outbound")
					}
					ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
					defer cancel()
					connection, err := direct.DialContext(ctx, "tcp", M.Socksaddr{Fqdn: "www.example.org", Port: uint16(target.Addr().(*net.TCPAddr).Port)})
					if err != nil {
						t.Fatal("main DNS cannot resolve user destination without a loop:", err)
					}
					connection.Close()
					access.Lock()
					for _, name := range bootstrapNames {
						if name == "www.example.org" {
							t.Error("ordinary destination leaked to bootstrap")
						}
					}
					if len(mainNames) == 0 {
						t.Error("main DNS was not queried")
					}
					access.Unlock()
					if detour {
						proxy.Close()
						access.Lock()
						for _, connection := range proxyConnections {
							connection.Close()
						}
						access.Unlock()
						protected, _ := instance.Outbound().Outbound("proxy")
						failedCtx, failedCancel := context.WithTimeout(context.Background(), time.Second)
						defer failedCancel()
						connection, err := protected.DialContext(failedCtx, "tcp", M.Socksaddr{Addr: M.ParseSocksaddr("127.0.0.1:1").Addr, Port: uint16(target.Addr().(*net.TCPAddr).Port)})
						if err == nil {
							connection.Close()
							t.Fatal("unavailable VPN silently used a direct connection")
						}
						connection, err = direct.DialContext(failedCtx, "tcp", M.Socksaddr{Fqdn: "failed.example.org", Port: uint16(target.Addr().(*net.TCPAddr).Port)})
						if err == nil {
							connection.Close()
							t.Fatal("unavailable DNS detour silently used bootstrap")
						}
						access.Lock()
						for _, name := range bootstrapNames {
							if strings.HasSuffix(name, ".example.org") {
								t.Error("user DNS fell back to bootstrap after VPN failure")
							}
						}
						access.Unlock()
					}
				})
			}
		}
	}
}

func policySOCKSConnection(conn net.Conn) {
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(3 * time.Second))
	header := make([]byte, 2)
	if _, err := io.ReadFull(conn, header); err != nil {
		return
	}
	methods := make([]byte, int(header[1]))
	if _, err := io.ReadFull(conn, methods); err != nil {
		return
	}
	if _, err := conn.Write([]byte{5, 0}); err != nil {
		return
	}
	request := make([]byte, 4)
	if _, err := io.ReadFull(conn, request); err != nil || request[1] != 1 {
		return
	}
	var host string
	switch request[3] {
	case 1, 4:
		size := 4
		if request[3] == 4 {
			size = 16
		}
		address := make([]byte, size)
		if _, err := io.ReadFull(conn, address); err != nil {
			return
		}
		host = net.IP(address).String()
	case 3:
		if _, err := io.ReadFull(conn, header[:1]); err != nil {
			return
		}
		address := make([]byte, int(header[0]))
		if _, err := io.ReadFull(conn, address); err != nil {
			return
		}
		host = string(address)
		if strings.HasSuffix(host, ".example") || strings.HasSuffix(host, ".example.org") {
			host = "127.0.0.1"
		}
	default:
		return
	}
	if _, err := io.ReadFull(conn, header); err != nil {
		return
	}
	// This fake proxy may only dial loopback, even if the generated policy regresses.
	if ip := net.ParseIP(host); ip == nil || !ip.IsLoopback() {
		return
	}
	remote, err := net.DialTimeout("tcp", net.JoinHostPort(host, fmt.Sprint(binary.BigEndian.Uint16(header))), time.Second)
	if err != nil {
		return
	}
	defer remote.Close()
	if _, err := conn.Write([]byte{5, 0, 0, 1, 127, 0, 0, 1, 0, 0}); err != nil {
		return
	}
	done := make(chan struct{})
	go func() { io.Copy(remote, conn); close(done) }()
	io.Copy(conn, remote)
	conn.Close()
	<-done
}
