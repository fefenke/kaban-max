package warp

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/option"
)

type hintTestPath struct {
	adapter.Endpoint
	port            uint16
	handshake, data int64
}

func (p *hintTestPath) WARPPathStats() (uint16, int64, int64, uint64) {
	return p.port, p.handshake, p.data, 1
}

func TestWARPPersistentPortHintJSON(t *testing.T) {
	var opts option.WARPEndpointOptions
	if err := json.Unmarshal([]byte(`{"listen_port_hint":42000,"port":2408}`), &opts); err != nil {
		t.Fatal(err)
	}
	if opts.ListenPortHint != 42000 || opts.ListenPort != 0 || opts.Port != 2408 {
		t.Fatalf("hint confused with bind/server: %+v", opts)
	}
	if got := warpListenPortHint(opts, 0); got != 42000 {
		t.Fatalf("empty RAM cache must use durable hint, got %d", got)
	}
	if got := warpListenPortHint(opts, 43000); got != 43000 {
		t.Fatalf("newer RAM recovery lost, got %d", got)
	}
	opts.ListenPort = 44000
	if got := warpListenPortHint(opts, 43000); got != 0 {
		t.Fatal("explicit binding must not use hints")
	}
	opts.ListenPort = 0
	opts.Profile.Recreate = true
	if got := warpListenPortHint(opts, 43000); got != 0 {
		t.Fatal("recreated profile inherited old path")
	}
}

func TestWARPPathStatusOnlyReportsAuthenticatedData(t *testing.T) {
	w := &Endpoint{ctx: context.Background(), pathInstance: "first", endpoint: &hintTestPath{port: 42000, handshake: 1000, data: 1001}}
	got := w.WARPPathStatus()
	if got.Port != 42000 || got.HandshakeAt != 1000 || got.DataAt != 1001 || got.Instance != "first:1" {
		t.Fatalf("bad status: %+v", got)
	}
	w.endpoint = nil
	if got := w.WARPPathStatus(); got.Port != 0 {
		t.Fatal("uninitialized path was accepted")
	}
	w.endpoint = &hintTestPath{port: 42000, handshake: 1000, data: 1001}
	w.options.ListenPort = 42000
	if got := w.WARPPathStatus(); got.Port != 0 {
		t.Fatal("explicit bind eligible for hint persistence")
	}
}
