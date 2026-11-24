package route

import (
	"context"
	"errors"
	"github.com/sagernet/sing-box/common/autoroute"
	"net"
	"strings"
	"sync/atomic"
	"syscall"
	"testing"

	E "github.com/sagernet/sing/common/exceptions"
)

func TestAutoSourceFailureVisibleWithoutDuplicatingActionableErrors(t *testing.T) {
	router, output := newLoggedRouter(t)
	event := autoroute.Event{Query: autoroute.Query{Source: "META", IP: "203.0.113.7", Port: 443}}
	router.logAutoSourceFailure(event, syscall.ETIMEDOUT)
	if got := output.String(); !strings.HasPrefix(got, "WARN") || !strings.Contains(got, "META") || !strings.Contains(got, "203.0.113.7") {
		t.Fatalf("first failure hidden: %q", got)
	}
	router, output = newLoggedRouter(t)
	router.logAutoSourceFailure(event, errors.New("TLS: authentication failed"))
	if output.String() != "" {
		t.Fatalf("actionable error duplicated: %q", output.String())
	}
}

func TestConnectionNoiseIsDebugButActionableFailuresRemainErrors(t *testing.T) {
	for _, test := range []struct {
		err   error
		debug bool
	}{
		{syscall.EHOSTUNREACH, true}, {syscall.ENETUNREACH, true}, {syscall.ENOTCONN, true},
		{syscall.ECONNRESET, true}, {syscall.EPIPE, true}, {context.Canceled, true},
		{errors.New("raw read: no route to host"), true},
		{errors.New("close tcp 172.16.0.2:123: endpoint not connected"), true},
		{errors.New("TLS: protocol version not supported"), false},
		{errors.New("authentication failed"), false}, {context.DeadlineExceeded, true},
		{syscall.ECONNREFUSED, true}, {syscall.ETIMEDOUT, true},
	} {
		t.Run(test.err.Error(), func(t *testing.T) {
			router, output := newLoggedRouter(t)
			manager := &ConnectionManager{logger: router.logger}
			manager.logConnectionFailure(context.Background(), E.Cause(test.err, "open connection to example.com using outbound/vless[server]"))
			logged := output.String()
			level := "ERROR"
			if test.debug {
				level = "DEBUG"
			}
			if !strings.HasPrefix(logged, level) || !strings.Contains(logged, test.err.Error()) {
				t.Fatalf("want %s with cause, got %q", level, logged)
			}
		})
	}
}

type logPolicyConn struct {
	net.Conn
	readErr error
}

func (c *logPolicyConn) Read([]byte) (int, error)    { return 0, c.readErr }
func (c *logPolicyConn) Write(p []byte) (int, error) { return len(p), nil }
func (c *logPolicyConn) Close() error                { return nil }

func TestConnectionCopyErrorsAreDebugAndKeepCloseCause(t *testing.T) {
	for _, direction := range []bool{false, true} {
		router, output := newLoggedRouter(t)
		manager := &ConnectionManager{logger: router.logger}
		cause := errors.New("synthetic copy failure")
		var done atomic.Bool
		done.Store(true)
		var closed error
		manager.connectionCopy(context.Background(), &logPolicyConn{readErr: cause}, &logPolicyConn{}, direction, &done, func(err error) { closed = err })
		if !errors.Is(closed, cause) {
			t.Fatalf("close handler lost failure: %v", closed)
		}
		if got := output.String(); !strings.HasPrefix(got, "DEBUG") || !strings.Contains(got, cause.Error()) {
			t.Fatalf("unexpected close log: %q", got)
		}
	}
}
