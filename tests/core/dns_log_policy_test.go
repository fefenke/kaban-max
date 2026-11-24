package dns

import (
	"context"
	"errors"
	"fmt"
	mDNS "github.com/miekg/dns"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/log"
	E "github.com/sagernet/sing/common/exceptions"
	"strings"
	"testing"
	"time"
)

func TestServiceDNSRefusalDoesNotPolluteFailureWindow(t *testing.T) {
	output := new(lockedBuffer)
	factory := log.NewDefaultFactory(context.Background(), log.Formatter{BaseTime: time.Now(), DisableColors: true}, output, "", nil, false)
	if err := factory.Start(); err != nil {
		t.Fatal(err)
	}
	defer factory.Close()
	logger := factory.NewLogger("dns")
	var failures failureLog
	message := new(mDNS.Msg)
	message.SetQuestion("version.maradns.", mDNS.TypeTXT)
	message.Question[0].Qclass = mDNS.ClassCHAOS
	cause := E.Cause(RcodeRefused, "response")
	result := failures.failed(context.Background(), logger, "dns-server", message, cause)
	if !IsLoggedFailure(result) || !E.IsMulti(result, RcodeRefused) {
		t.Fatal("error identity/dedup was lost")
	}
	if len(failures.windows) != 0 {
		t.Fatal("service refusal must not open a site failure window")
	}
	if lines := output.lines(); len(lines) != 1 || !strings.HasPrefix(lines[0], "DEBUG") {
		t.Fatalf("want debug, got %q", lines)
	}
	message.Question[0].Qclass = mDNS.ClassINET
	failures.failed(context.Background(), logger, "dns-server", message, cause)
	if len(failures.windows) != 1 {
		t.Fatal("ordinary DNS refused must remain tracked for escalation")
	}
}

func TestDNSFailuresShowFirstDomainAndSummarizeOnlyItsRepeats(t *testing.T) {
	previous := failureLogInterval
	failureLogInterval = 30 * time.Millisecond
	defer func() { failureLogInterval = previous }()
	output := new(lockedBuffer)
	factory := log.NewDefaultFactory(context.Background(), log.Formatter{BaseTime: time.Now(), DisableColors: true}, output, "", nil, false)
	if err := factory.Start(); err != nil {
		t.Fatal(err)
	}
	defer factory.Close()
	message := new(mDNS.Msg)
	message.SetQuestion("example.com.", mDNS.TypeA)
	var failures failureLog
	for i := 0; i < 5; i++ {
		failures.failed(context.Background(), factory.NewLogger("dns"), "dns-server", message, context.DeadlineExceeded)
	}
	for deadline := time.Now().Add(time.Second); ; time.Sleep(time.Millisecond) {
		failures.access.Lock()
		open := len(failures.windows)
		failures.access.Unlock()
		if open == 0 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("DNS window did not close")
		}
	}
	lines := output.lines()
	if len(lines) != 2 || !strings.HasPrefix(lines[0], "WARN") || !strings.HasPrefix(lines[1], "WARN") || !strings.Contains(lines[1], "4 more exchanges failed") {
		t.Fatalf("unexpected levels/count: %q", lines)
	}
}

func TestDNSFailureGroupsDoNotMergeDifferentDomainsOrQuestionTypes(t *testing.T) {
	output := new(lockedBuffer)
	factory := log.NewDefaultFactory(context.Background(), log.Formatter{BaseTime: time.Now(), DisableColors: true}, output, "", nil, false)
	if err := factory.Start(); err != nil {
		t.Fatal(err)
	}
	defer factory.Close()
	var failures failureLog
	for _, q := range []struct {
		name   string
		kind   uint16
		server string
	}{
		{"one.example.", mDNS.TypeA, "dns"}, {"two.example.", mDNS.TypeA, "dns"},
		{"one.example.", mDNS.TypeAAAA, "dns"}, {"ONE.EXAMPLE.", mDNS.TypeA, "dns"},
		{"one.example.", mDNS.TypeA, "other"},
	} {
		msg := new(mDNS.Msg)
		msg.SetQuestion(q.name, q.kind)
		failures.failed(context.Background(), factory.NewLogger("dns"), q.server, msg, context.DeadlineExceeded)
	}
	if len(failures.windows) != 4 {
		t.Fatalf("different questions merged: %d", len(failures.windows))
	}
	if got := output.lines(); len(got) != 4 {
		t.Fatalf("each first failed question must be visible, got %q", got)
	}
}

type logPolicyDNSTransport struct{ adapter.DNSTransport }

func (logPolicyDNSTransport) Tag() string { return "test" }

func TestMalformedDNSQueryIsDebugAndStillRejected(t *testing.T) {
	output := new(lockedBuffer)
	factory := log.NewDefaultFactory(context.Background(), log.Formatter{BaseTime: time.Now(), DisableColors: true}, output, "", nil, false)
	if err := factory.Start(); err != nil {
		t.Fatal(err)
	}
	defer factory.Close()
	logger := factory.NewLogger("dns")
	router := &Router{logger: logger}
	query := new(mDNS.Msg)
	query.Question = []mDNS.Question{{Name: "a.example.", Qtype: mDNS.TypeA, Qclass: mDNS.ClassINET}, {Name: "b.example.", Qtype: mDNS.TypeA, Qclass: mDNS.ClassINET}}
	_, response, err := router.prepareExchange(context.Background(), query)
	if err != nil || response == nil || response.Rcode != mDNS.RcodeFormatError {
		t.Fatalf("malformed query handling changed: %v %v", response, err)
	}
	client := &Client{logger: logger}
	_, response, _, err = client.beginExchange(context.Background(), logPolicyDNSTransport{}, new(mDNS.Msg), adapter.DNSQueryOptions{}, nil, false)
	if err != nil || response == nil || response.Rcode != mDNS.RcodeFormatError {
		t.Fatalf("empty query handling changed: %v %v", response, err)
	}
	lines := output.lines()
	if len(lines) != 2 {
		t.Fatalf("want two debug events, got %q", lines)
	}
	for _, line := range lines {
		if !strings.HasPrefix(line, "DEBUG") {
			t.Fatalf("unexpected severity: %s", line)
		}
	}
}

func TestDNSGroupingHasBoundedWindowsAndKeepsOriginalReturnedCause(t *testing.T) {
	output := new(lockedBuffer)
	factory := log.NewDefaultFactory(context.Background(), log.Formatter{BaseTime: time.Now(), DisableColors: true}, output, "", nil, false)
	if err := factory.Start(); err != nil {
		t.Fatal(err)
	}
	defer factory.Close()
	var failures failureLog
	logger := factory.NewLogger("dns")
	for i := 0; i < maxFailureWindows+10; i++ {
		msg := new(mDNS.Msg)
		msg.SetQuestion(fmt.Sprintf("domain-%d.example.", i), mDNS.TypeA)
		failures.failed(context.Background(), logger, "dns", msg, context.DeadlineExceeded)
	}
	if len(failures.windows) != maxFailureWindows {
		t.Fatalf("unbounded DNS heap: %d", len(failures.windows))
	}
	msg := new(mDNS.Msg)
	msg.SetQuestion("domain-0.example.", mDNS.TypeA)
	cause := errors.New(strings.Repeat("x", 20000))
	returned := failures.failed(context.Background(), logger, "dns", msg, cause)
	if !errors.Is(returned, cause) {
		t.Fatal("diagnostic truncation changed the returned failure")
	}
	for _, window := range failures.windows {
		if window.err != nil && len(window.err.Error()) > 1100 {
			t.Fatal("unbounded saved diagnostic cause")
		}
	}
}
