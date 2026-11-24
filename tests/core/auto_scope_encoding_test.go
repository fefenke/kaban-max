package autoroute

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/sagernet/sing-box/option"
)

func TestRegistryEquivalentScopeEncodingIsCanonical(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	key := m.key(q)
	var fields []any
	if err := json.Unmarshal([]byte(key), &fields); err != nil {
		t.Fatal(err)
	}
	pretty, err := json.MarshalIndent(fields, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	encoded := strings.Replace(string(pretty), `"s1"`, `"\u00731"`, 1)
	other := q
	other.SourceIP = "192.0.2.99"
	neighbour := m.key(other)
	m.suppressed[neighbour] = true
	call := func(op, source, scope string) error {
		raw, err := json.Marshal(map[string]any{"op": op, "source_id": source, "scope": scope})
		if err != nil {
			t.Fatal(err)
		}
		_, err = m.API(context.Background(), raw)
		return err
	}
	if err := call("registry_suppress", "s1", encoded); err != nil {
		t.Fatal(err)
	}
	if !m.suppressed[key] || m.suppressed[encoded] || len(m.suppressed) != 2 {
		t.Fatal("suppression did not use one canonical identity")
	}
	if err := call("registry_reset", "other", encoded); err == nil {
		t.Fatal("foreign scope owner accepted")
	}
	if err := call("registry_reset", "s1", encoded); err != nil {
		t.Fatal(err)
	}
	if m.suppressed[key] || !m.suppressed[neighbour] {
		t.Fatal("reset crossed the selected device scope")
	}
	if err := call("registry_reset", "s1", encoded); err != nil {
		t.Fatal("repeated exact removal failed", err)
	}
	m.reserved[key], m.reserved[neighbour] = true, true
	if err := call("registry_release", "s1", encoded); err != nil {
		t.Fatal(err)
	}
	if m.reserved[key] || !m.reserved[neighbour] {
		t.Fatal("release crossed the selected device scope")
	}
}

func TestSavedScopeEncodingRestoresOneIdentity(t *testing.T) {
	m, q, _, _ := testManager(t, "fail:")
	key := m.key(q)
	var fields []any
	if err := json.Unmarshal([]byte(key), &fields); err != nil {
		t.Fatal(err)
	}
	pretty, err := json.MarshalIndent(fields, "", " ")
	if err != nil {
		t.Fatal(err)
	}
	source := m.sources[q.Source]
	source.Suppressed = []string{string(pretty), key}
	source.RegistryScopes = []string{string(pretty), key}
	n := New(m.ctx, []option.KabanmaxAutoSource{source})
	if len(n.suppressed) != 1 || !n.suppressed[key] || len(n.reserved) != 1 || !n.reserved[key] {
		t.Fatal("saved scopes were not canonicalized/deduplicated")
	}
}
