package clashapi

import (
	"encoding/json"
	"github.com/sagernet/sing-box/adapter"
	"net/http/httptest"
	"strings"
	"testing"
)

type warpPathTestEndpoint struct{ adapter.Endpoint }

func (*warpPathTestEndpoint) WARPPathStatus() adapter.WARPPathStatus {
	return adapter.WARPPathStatus{Tag: "test-warp", Port: 42000, HandshakeAt: 1000, DataAt: 1001, Instance: "boot:1"}
}

type warpPathTestManager struct{ adapter.EndpointManager }

func (*warpPathTestManager) Endpoints() []adapter.Endpoint {
	return []adapter.Endpoint{&warpPathTestEndpoint{}}
}

func TestWARPPathsReadOnlySnapshot(t *testing.T) {
	for _, manager := range []adapter.EndpointManager{nil, &warpPathTestManager{}} {
		recorder := httptest.NewRecorder()
		warpPaths(manager).ServeHTTP(recorder, httptest.NewRequest("GET", "/kabanmax/warp-paths", nil))
		if recorder.Code != 200 || recorder.Header().Get("Cache-Control") != "no-store" {
			t.Fatal("unsafe response")
		}
		var reply struct {
			Endpoints []adapter.WARPPathStatus `json:"endpoints"`
		}
		if err := json.Unmarshal(recorder.Body.Bytes(), &reply); err != nil {
			t.Fatal(err)
		}
		if manager == nil && len(reply.Endpoints) != 0 {
			t.Fatal("uninitialized manager")
		}
		if manager != nil && (len(reply.Endpoints) != 1 || reply.Endpoints[0].Port != 42000) {
			t.Fatal("missing path status")
		}
		for _, secret := range []string{"private_key", "auth_token", "address"} {
			if strings.Contains(recorder.Body.String(), secret) {
				t.Fatal("status exposed credentials or endpoint")
			}
		}
	}
}
