package parser

import (
	"context"
	"encoding/json"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/service"
	"os"
	"testing"
)

func TestApplicationFingerprintCatalogParser(t *testing.T) {
	raw, err := os.ReadFile(os.Getenv("KABANMAX_FINGERPRINT_CATALOG"))
	if err != nil {
		t.Fatal(err)
	}
	var profiles []struct{ ID string }
	if err = json.Unmarshal(raw, &profiles); err != nil {
		t.Fatal(err)
	}
	for _, profile := range profiles {
		registry := &captureRegistry{}
		ctx := service.ContextWith[adapter.OutboundRegistry](context.Background(), registry)
		_, err := NewOutbound(ctx, nil, nil, "test", option.ParserOutboundOptions{Link: "vless://00000000-0000-0000-0000-000000000001@example.org:443?security=tls&fp=chrome", TLSFingerprint: profile.ID})
		if err != nil {
			t.Fatalf("catalog parser rejected %s", profile.ID)
		}
		parsed, ok := registry.options.(*option.VLESSOutboundOptions)
		if !ok || parsed.TLS.UTLS.Fingerprint != profile.ID {
			t.Fatalf("override not applied for %s", profile.ID)
		}
	}
}
