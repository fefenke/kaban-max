package log

import (
	"bytes"
	"context"
	"github.com/sagernet/sing-box/common/wanstate"
	"strings"
	"testing"
	"time"
)

func TestWANStateGatesNetworkMessagesBeforeConsoleOutput(t *testing.T) {
	var output bytes.Buffer
	f := NewDefaultFactory(context.Background(), Formatter{BaseTime: time.Now(), DisableColors: true}, &output, "", nil, false)
	if err := f.Start(); err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	m := wanstate.New(func(message string) { f.NewLogger("wan").Warn(message) })
	close := wanstate.Install(m)
	defer close()
	m.Observe(wanstate.Sample{Reason: "no default route; external checks failed"})
	m.Observe(wanstate.Sample{Reason: "no default route; external checks failed"})
	f.NewLogger("dns").Warn("server dns: 10 more exchanges failed in 10s for example.com. IN A: timeout")
	f.NewLogger("vless").Error("TLS handshake timeout")
	f.NewLogger("wireguard").Error("Handshake did not complete")
	f.NewLogger("vless").Error("tls: protocol version not supported")
	f.NewLogger("vless").Error("authentication failed")
	m.Observe(wanstate.Sample{Available: true, Reason: "verified HTTPS response"})
	lines := strings.Split(strings.TrimSpace(output.String()), "\n")
	if len(lines) != 2 || !strings.Contains(lines[0], "WAN unavailable") || !strings.Contains(lines[1], "WAN restored") {
		t.Fatalf("unexpected network logs: %q", lines)
	}
}
