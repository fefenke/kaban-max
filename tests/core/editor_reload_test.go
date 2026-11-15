// Copied into cmd/sing-box of a clean UPSTREAM+patches checkout by the local
// verification command documented in docs/TESTING.md. Only loopback is used.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"testing"
	"time"
)

// Exercise the Close/Create cycle used by cmd_run.go on SIGHUP with loopback
// streams, rather than inferring stream lifetime from a configuration diff.
func TestEditorReloadClosesOldStreamsAndUsesNewEndpoint(t *testing.T) {
	endpoint := func(marker string) int {
		listener, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { listener.Close() })
		go func() {
			for {
				conn, err := listener.Accept()
				if err != nil {
					return
				}
				go func() { defer conn.Close(); io.WriteString(conn, marker); io.Copy(conn, conn) }()
			}
		}()
		return listener.Addr().(*net.TCPAddr).Port
	}
	firstPort, secondPort := endpoint("A"), endpoint("B")
	reservation, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	listenPort := reservation.Addr().(*net.TCPAddr).Port
	reservation.Close()
	start := func(target int) interface{ Close() error } {
		config := []byte(fmt.Sprintf(`{"log":{"disabled":true},"inbounds":[{"type":"direct","tag":"local","listen":"127.0.0.1","listen_port":%d,"network":"tcp","override_address":"127.0.0.1","override_port":%d}],"outbounds":[{"type":"direct","tag":"server"}]}`, listenPort, target))
		instance, _ := stableReloadTestBox(t, config)
		if err := instance.Start(); err != nil {
			t.Fatal(err)
		}
		return instance
	}
	connect := func(marker string) net.Conn {
		conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", listenPort), time.Second)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { conn.Close() })
		conn.SetDeadline(time.Now().Add(2 * time.Second))
		if _, err := io.WriteString(conn, "x"); err != nil {
			t.Fatal(err)
		}
		received := make([]byte, 2)
		if _, err := io.ReadFull(conn, received); err != nil {
			t.Fatal(err)
		}
		if string(received) != marker+"x" {
			t.Fatal("wrong local endpoint")
		}
		return conn
	}
	oldInstance := start(firstPort)
	oldStream := connect("A")
	if err := oldInstance.Close(); err != nil {
		t.Fatal(err)
	}
	oldStream.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := oldStream.Read(make([]byte, 1)); err == nil {
		t.Fatal("old stream survived instance shutdown")
	} else if timeout, ok := err.(net.Error); ok && timeout.Timeout() {
		t.Fatal("old stream was left open")
	}
	start(secondPort)
	connect("B")
}

func TestEditorReloadDoesNotReuseChangedConnectionGraph(t *testing.T) {
	raw := []byte(`{"outbounds":[{"tag":"section/Backup","type":"fallback","stable":true,"groups":[{"outbounds":["section/Poland"]}]},{"tag":"section/Poland","type":"parser","link":"socks://127.0.0.1:1080#Poland"}]}`)
	original := stableObservationFingerprints(raw)["section/Backup"]
	if original == "" {
		t.Fatal("missing initial graph")
	}
	for _, scenario := range []string{"uri", "server-name", "fallback-name"} {
		var config map[string]any
		if err := json.Unmarshal(raw, &config); err != nil {
			t.Fatal(err)
		}
		entries := config["outbounds"].([]any)
		group := entries[0].(map[string]any)
		server := entries[1].(map[string]any)
		tag := "section/Backup"
		switch scenario {
		case "uri":
			server["link"] = "socks://127.0.0.1:1081#New"
		case "server-name":
			server["tag"] = "section/Warsaw"
			group["groups"].([]any)[0].(map[string]any)["outbounds"] = []string{"section/Warsaw"}
		case "fallback-name":
			group["tag"] = "section/New backup"
			tag = "section/New backup"
		}
		changed, err := json.Marshal(config)
		if err != nil {
			t.Fatal(err)
		}
		next := stableObservationFingerprints(changed)[tag]
		if next == "" || next == original {
			t.Fatalf("%s reused stale observations", scenario)
		}
		if stableObservationFingerprints(changed)[tag] != next {
			t.Fatalf("%s repeat save changed graph", scenario)
		}
	}
}
