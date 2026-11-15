package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"testing"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/protocol/group"
)

// New Box instances share only a disk cache, never reload snapshots or health.
func TestLifecycleColdCache(t *testing.T) {
	for _, mode := range []string{"saved", "missing", "corrupt", "removed-member", "unpin"} {
		t.Run(mode, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "cache.db")
			start := func(removed bool) *box.Box {
				members := []string{"a", "b"}
				if removed {
					members = []string{"a"}
				}
				raw, err := json.Marshal(map[string]any{
					"log":          map[string]any{"disabled": true},
					"experimental": map[string]any{"cache_file": map[string]any{"enabled": true, "path": path, "store_fakeip": true}},
					"outbounds": []any{
						map[string]any{"type": "selector", "tag": "outer", "outbounds": []string{"fb", "ut"}, "default": "fb"},
						map[string]any{"type": "fallback", "tag": "fb", "stable": true, "outbounds": members, "url": "http://127.0.0.1:1/"},
						map[string]any{"type": "urltest", "tag": "ut", "outbounds": members, "url": "http://127.0.0.1:1/"},
						map[string]any{"type": "direct", "tag": "a"}, map[string]any{"type": "direct", "tag": "b"},
					},
				})
				if err != nil {
					t.Fatal(err)
				}
				instance, _ := stableReloadTestBox(t, raw)
				if err := instance.Start(); err != nil {
					t.Fatal(err)
				}
				return instance
			}
			first := start(false)
			outer, _ := first.Outbound().Outbound("outer")
			fb, _ := first.Outbound().Outbound("fb")
			if !outer.(*group.Selector).SelectOutbound("ut") || !fb.(*group.Fallback).SelectOutbound("b") {
				t.Fatal("pin failed")
			}
			if mode == "unpin" && !fb.(*group.Fallback).SelectOutbound("") {
				t.Fatal("unpin failed")
			}
			if err := first.Close(); err != nil {
				t.Fatal(err)
			}
			if mode == "missing" {
				if err := os.Remove(path); err != nil {
					t.Fatal(err)
				}
			}
			if mode == "corrupt" {
				if err := os.WriteFile(path, []byte("invalid database"), 0600); err != nil {
					t.Fatal(err)
				}
			}
			second := start(mode == "removed-member")
			defer second.Close()
			outer, _ = second.Outbound().Outbound("outer")
			fb, _ = second.Outbound().Outbound("fb")
			expectedOuter, expectedMember := "ut", "b"
			if mode == "missing" || mode == "corrupt" {
				expectedOuter, expectedMember = "fb", "a"
			}
			if mode == "removed-member" || mode == "unpin" {
				expectedMember = "a"
			}
			if got := outer.(*group.Selector).Selected("tcp").Tag(); got != expectedOuter {
				t.Fatalf("outer: %s, want %s", got, expectedOuter)
			}
			if got := fb.(*group.Fallback).Selected("tcp").Tag(); got != expectedMember {
				t.Fatalf("fallback: %s, want %s", got, expectedMember)
			}
			expectedPin := ""
			if mode == "saved" {
				expectedPin = "b"
			}
			if got := fb.(*group.Fallback).Fixed(); got != expectedPin {
				t.Fatalf("pin: %s, want %s", got, expectedPin)
			}
		})
	}
}

type lifecycleCloser struct {
	once   sync.Once
	closed chan struct{}
}

func (c *lifecycleCloser) Close() error { c.once.Do(func() { close(c.closed) }); return nil }

func TestLifecycleSelectorInterrupt(t *testing.T) {
	for _, interrupt := range []bool{false, true} {
		raw, _ := json.Marshal(map[string]any{"log": map[string]any{"disabled": true}, "outbounds": []any{
			map[string]any{"type": "selector", "tag": "s", "outbounds": []string{"a", "b"}, "interrupt_exist_connections": interrupt},
			map[string]any{"type": "direct", "tag": "a"}, map[string]any{"type": "direct", "tag": "b"},
		}})
		instance, _ := stableReloadTestBox(t, raw)
		if err := instance.Start(); err != nil {
			t.Fatal(err)
		}
		outbound, _ := instance.Outbound().Outbound("s")
		selector := outbound.(*group.Selector)
		conn := &lifecycleCloser{closed: make(chan struct{})}
		detach := selector.AttachConnection(conn)
		if !selector.SelectOutbound("b") {
			t.Fatal("selection failed")
		}
		closed := false
		select {
		case <-conn.closed:
			closed = true
		default:
		}
		if closed != interrupt {
			t.Fatalf("interrupt=%v closed=%v", interrupt, closed)
		}
		detach()
		instance.Close()
	}
}
