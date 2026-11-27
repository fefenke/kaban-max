package group

import (
	"context"
	"errors"
	"io"
	"net"
	"syscall"
	"testing"

	"github.com/sagernet/sing/common/buf"
	"github.com/sagernet/sing/common/bufio"
	M "github.com/sagernet/sing/common/metadata"
)

type streamFailureTestConn struct {
	net.Conn
	cause error
}

func (c *streamFailureTestConn) Read([]byte) (int, error)    { return 0, c.cause }
func (c *streamFailureTestConn) Write(p []byte) (int, error) { return 0, c.cause }
func (c *streamFailureTestConn) Close() error                { return nil }

func TestStableStreamFailureDoesNotWakeHealthAfterSuccessfulDial(t *testing.T) {
	for _, operation := range []string{"read", "write", "buffered_read", "buffered_write"} {
		t.Run(operation, func(t *testing.T) {
			primary := &stableTrafficOutbound{fallbackHealthTestOutbound: newFallbackHealthTestOutbound("primary", true)}
			primary.dial = func(context.Context, string, M.Socksaddr) (net.Conn, error) {
				return &streamFailureTestConn{cause: syscall.ETIMEDOUT}, nil
			}
			s := stableCandidateGroup(t, fallbackCandidate{tag: primary.Tag(), outbound: primary})
			conn, err := s.DialContext(context.Background(), "tcp", M.Socksaddr{Fqdn: "user.test", Port: 443})
			if err != nil {
				t.Fatal(err)
			}
			defer conn.Close()
			if operation == "buffered_read" || operation == "buffered_write" {
				b := buf.New()
				defer b.Release()
				if operation == "buffered_read" {
					err = bufio.NewExtendedConn(conn).ReadBuffer(b)
				} else {
					b.WriteByte(1)
					err = bufio.NewExtendedConn(conn).WriteBuffer(b)
				}
			} else if operation == "write" {
				_, err = conn.Write([]byte{1})
			} else {
				_, err = conn.Read(make([]byte, 1))
			}
			if !errors.Is(err, syscall.ETIMEDOUT) {
				t.Fatal(err)
			}
			select {
			case <-s.wake:
				t.Fatal("established stream failure scheduled a tunnel health check")
			default:
			}
			_, _ = conn.Read(make([]byte, 1))
			select {
			case <-s.wake:
				t.Fatal("one stream queued repeated checks")
			default:
			}
		})
	}
}

func TestStableNewDialFailureStillWakesHealth(t *testing.T) {
	primary := &stableTrafficOutbound{fallbackHealthTestOutbound: newFallbackHealthTestOutbound("primary", true)}
	primary.dial = func(context.Context, string, M.Socksaddr) (net.Conn, error) {
		return nil, syscall.ETIMEDOUT
	}
	s := stableCandidateGroup(t, fallbackCandidate{tag: primary.Tag(), outbound: primary})
	_, err := s.DialContext(context.Background(), "tcp", M.Socksaddr{Fqdn: "user.test", Port: 443})
	if !errors.Is(err, syscall.ETIMEDOUT) {
		t.Fatalf("dial error lost: %v", err)
	}
	select {
	case <-s.wake:
	default:
		t.Fatal("new dial failure no longer schedules health")
	}
}

func TestStableRoutineStreamCloseDoesNotWakeHealth(t *testing.T) {
	for _, cause := range []error{io.EOF, net.ErrClosed, context.Canceled, syscall.EAGAIN} {
		primary := &stableTrafficOutbound{fallbackHealthTestOutbound: newFallbackHealthTestOutbound("primary", true)}
		primary.dial = func(context.Context, string, M.Socksaddr) (net.Conn, error) {
			return &streamFailureTestConn{cause: cause}, nil
		}
		s := stableCandidateGroup(t, fallbackCandidate{tag: primary.Tag(), outbound: primary})
		conn, err := s.DialContext(context.Background(), "tcp", M.Socksaddr{Fqdn: "user.test", Port: 443})
		if err != nil {
			t.Fatal(err)
		}
		_, _ = conn.Read(make([]byte, 1))
		conn.Close()
		select {
		case <-s.wake:
			t.Fatalf("routine close triggered health: %v", cause)
		default:
		}
	}
}

func TestStableOldSelectedStreamCannotWakeNewMember(t *testing.T) {
	primary := &stableTrafficOutbound{fallbackHealthTestOutbound: newFallbackHealthTestOutbound("primary", true)}
	primary.dial = func(context.Context, string, M.Socksaddr) (net.Conn, error) {
		return &streamFailureTestConn{cause: syscall.ETIMEDOUT}, nil
	}
	backup := newFallbackHealthTestOutbound("backup", true)
	s := stableCandidateGroup(t, fallbackCandidate{tag: primary.Tag(), outbound: primary}, fallbackCandidate{tag: backup.Tag(), outbound: backup})
	conn, err := s.DialContext(context.Background(), "tcp", M.Socksaddr{Fqdn: "user.test", Port: 443})
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	s.access.Lock()
	s.selected = "backup"
	s.access.Unlock()
	_, _ = conn.Read(make([]byte, 1))
	select {
	case <-s.wake:
		t.Fatal("old member's stream scheduled health on the newly selected member")
	default:
	}
}
