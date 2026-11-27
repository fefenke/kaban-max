package route

import (
	"context"
	"errors"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/common/autoroute"
	"github.com/sagernet/sing-box/dns"
	"net"
	"strings"
	"sync/atomic"
	"syscall"
	"testing"

	E "github.com/sagernet/sing/common/exceptions"
	M "github.com/sagernet/sing/common/metadata"
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
			ctx := adapter.WithContext(context.Background(), &adapter.InboundContext{Destination: M.ParseSocksaddr("example.com:443"), RouteOutbound: "test-profile"})
			manager.logConnectionFailure(ctx, E.Cause(test.err, "open connection to example.com using outbound/vless[server]"))
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

func TestConnectionCopyErrorsStayDebugAndKeepCloseCause(t *testing.T) {
	for _, direction := range []bool{false, true} {
		router, output := newLoggedRouter(t)
		manager := &ConnectionManager{logger: router.logger}
		cause := errors.New("remote error: tls: protocol version not supported")
		var done atomic.Bool
		done.Store(true)
		var closed error
		ctx := adapter.WithContext(context.Background(), &adapter.InboundContext{Destination: M.ParseSocksaddr("example.com:443"), RouteOutbound: "test-profile"})
		manager.connectionCopy(ctx, &logPolicyConn{readErr: cause}, &logPolicyConn{}, direction, &done, func(err error) { closed = err })
		if !errors.Is(closed, cause) {
			t.Fatalf("close handler lost failure: %v", closed)
		}
		if got := output.String(); !strings.HasPrefix(got, "DEBUG") || !strings.Contains(got, cause.Error()) {
			t.Fatalf("unexpected close log: %q", got)
		}
	}
}

func TestUnattributedTLSFailureStaysDebug(t *testing.T) {
	router, output := newLoggedRouter(t)
	manager := &ConnectionManager{logger: router.logger}
	manager.logConnectionFailure(context.Background(), errors.New("remote error: tls: protocol version not supported"))
	if got := output.String(); !strings.HasPrefix(got, "DEBUG") {
		t.Fatalf("unattributed failure escaped into Error: %s", got)
	}
}

func TestActionableOpenFailureIncludesContextAndNextCheck(t *testing.T) {
	router, output := newLoggedRouter(t)
	manager := &ConnectionManager{logger: router.logger}
	ctx := adapter.WithContext(context.Background(), &adapter.InboundContext{Destination: M.ParseSocksaddr("example.com:443"), RouteOutbound: "test-profile"})
	manager.logConnectionFailure(ctx, errors.New("TLS: protocol version not supported"))
	got := output.String()
	for _, value := range []string{"ERROR", "example.com:443", "test-profile", "stage=connect", "check=", "protocol version not supported"} {
		if !strings.Contains(got, value) {
			t.Fatalf("missing %s in %s", value, got)
		}
	}
}

func TestUnknownOpenFailureWithContextStillStaysDebug(t *testing.T) {
	router, output := newLoggedRouter(t)
	manager := &ConnectionManager{logger: router.logger}
	ctx := adapter.WithContext(context.Background(), &adapter.InboundContext{Destination: M.ParseSocksaddr("example.com:443"), RouteOutbound: "test-profile"})
	manager.logConnectionFailure(ctx, errors.New("unclassified failure"))
	if got := output.String(); !strings.HasPrefix(got, "DEBUG") {
		t.Fatalf("unknown failure promoted without guidance: %s", got)
	}
}

type actionableLogOutbound struct {
	adapter.Outbound
	kind  string
	cause error
}

func (o *actionableLogOutbound) Type() string { return o.kind }
func (o *actionableLogOutbound) Tag() string  { return "selected-profile" }
func (o *actionableLogOutbound) DialContext(context.Context, string, M.Socksaddr) (net.Conn, error) {
	return nil, o.cause
}

func TestNewConnectionFailureCarriesSelectedProfileAndCause(t *testing.T) {
	for _, kind := range []string{"vless", "warp"} {
		t.Run(kind, func(t *testing.T) {
			router, output := newLoggedRouter(t)
			manager := &ConnectionManager{logger: router.logger}
			cause := errors.New("authentication failed")
			client, peer := net.Pipe()
			defer client.Close()
			defer peer.Close()
			var closed error
			manager.NewConnection(context.Background(), &actionableLogOutbound{kind: kind, cause: cause}, client, adapter.InboundContext{Network: "tcp", Destination: M.ParseSocksaddr("example.com:443")}, func(err error) { closed = err })
			if !errors.Is(closed, cause) {
				t.Fatalf("close callback lost cause: %v", closed)
			}
			got := output.String()
			for _, value := range []string{"ERROR", "example.com:443", kind + "[selected-profile]", "stage=connect", "check=", cause.Error()} {
				if !strings.Contains(got, value) {
					t.Fatalf("missing %s in %s", value, got)
				}
			}
		})
	}
}

func TestDeferredHandshakeFailureRetainsActionableError(t *testing.T) {
	router, output := newLoggedRouter(t)
	manager := &ConnectionManager{logger: router.logger}
	ctx := adapter.WithContext(context.Background(), &adapter.InboundContext{Destination: M.ParseSocksaddr("example.com:443"), RouteOutbound: "selected-profile"})
	manager.logConnectionStageFailure(ctx, "outbound_handshake", errors.New("authentication failed"))
	got := output.String()
	if !strings.HasPrefix(got, "ERROR") || !strings.Contains(got, "stage=outbound_handshake") || !strings.Contains(got, "check=") {
		t.Fatalf("deferred handshake lost actionable failure: %s", got)
	}
}

func TestClientHandshakeFailureIsNotReportedAsProxyFault(t *testing.T) {
	router, output := newLoggedRouter(t)
	manager := &ConnectionManager{logger: router.logger}
	ctx := adapter.WithContext(context.Background(), &adapter.InboundContext{Destination: M.ParseSocksaddr("example.com:443"), RouteOutbound: "selected-profile"})
	manager.logConnectionStageFailure(ctx, "client_handshake", errors.New("TLS: authentication failed"))
	if got := output.String(); !strings.HasPrefix(got, "DEBUG") || strings.Contains(got, "check=") {
		t.Fatalf("client fault promoted as proxy misconfiguration: %s", got)
	}
}

func TestContextAndDestinationNamesDoNotClassifyUnknownCause(t *testing.T) {
	router, output := newLoggedRouter(t)
	manager := &ConnectionManager{logger: router.logger}
	ctx := adapter.WithContext(context.Background(), &adapter.InboundContext{Destination: M.ParseSocksaddr("certificate.example:443"), RouteOutbound: "tls-profile"})
	manager.logConnectionFailure(ctx, E.Cause(errors.New("unknown cause"), "open certificate.example using tls-profile"))
	if got := output.String(); !strings.HasPrefix(got, "DEBUG") {
		t.Fatalf("hostname classified unknown cause: %s", got)
	}
}

func TestDNSRefusalIncludesResolverCheck(t *testing.T) {
	router, output := newLoggedRouter(t)
	manager := &ConnectionManager{logger: router.logger}
	ctx := adapter.WithContext(context.Background(), &adapter.InboundContext{Destination: M.ParseSocksaddr("example.com:443"), RouteOutbound: "selected-profile"})
	manager.logConnectionFailure(ctx, E.Cause(dns.RcodeRefused, "lookup example.com"))
	got := output.String()
	if !strings.HasPrefix(got, "ERROR") || !strings.Contains(got, "DNS") || !strings.Contains(got, "check=") || !strings.Contains(got, "example.com:443") {
		t.Fatalf("actionable DNS refusal lost: %s", got)
	}
}
