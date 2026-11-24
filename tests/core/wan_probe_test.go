package wanstate

import (
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestRouteEvidenceIgnoresRejectAndLoopbackDefaults(t *testing.T) {
	v4 := "Iface Destination Gateway Flags RefCnt Use Metric Mask\nwan 00000000 01010101 0003 0 0 0 00000000\nlo 00000000 00000000 0001 0 0 0 00000000\nbad 00000000 00000000 0201 0 0 0 00000000\n"
	v6 := strings.Repeat("0", 32) + " 00 " + strings.Repeat("0", 32) + " 00 " + strings.Repeat("0", 32) + " 00000001 00000000 00000000 00000001 wan6\n"
	got := routeInterfaces(v4, v6)
	if strings.Join(got, ",") != "wan,wan6" {
		t.Fatalf("wrong route evidence: %v", got)
	}
}
func TestWANRequiresActualValidReceivedResponse(t *testing.T) {
	for _, test := range []struct {
		body  string
		code  int
		valid bool
	}{
		{`{"Status":0}`, 200, true}, {`{"Status":3}`, 200, true},
		{``, 200, false}, {`<html>login</html>`, 200, false}, {`{"Status":0}`, 302, false},
		{strings.Repeat("x", 4097), 200, false},
	} {
		err := verifyBody(&http.Response{StatusCode: test.code, Body: io.NopCloser(strings.NewReader(test.body))})
		if (err == nil) != test.valid {
			t.Fatalf("response acceptance=%v for %q", err, test.body[:min(len(test.body), 30)])
		}
	}
}

func TestNetifdReasonReportsStatusCodesWithoutPrivateParameters(t *testing.T) {
	data := []byte(`{"interface":[{"interface":"wan","device":"eth1","up":false,"pending":true,"available":true,"errors":[{"subsystem":"ppp","code":"AUTH_FAILED","data":{"password":"do-not-log"}}]},{"interface":"lan","up":true,"errors":[{"code":"unrelated"}]}]}`)
	reason := formatNetifd(data, nil)
	if !strings.Contains(reason, "up=false") || !strings.Contains(reason, "ppp:AUTH_FAILED") {
		t.Fatalf("missing factual cause: %s", reason)
	}
	if strings.Contains(reason, "do-not-log") || strings.Contains(reason, "unrelated") {
		t.Fatalf("private/unrelated data leaked: %s", reason)
	}
}
