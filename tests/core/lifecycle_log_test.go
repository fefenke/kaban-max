package log

import (
	"bytes"
	"context"
	"strings"
	"testing"
	"time"
)

func TestStoppedGenerationDowngradesAnyRuntimeFailure(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var output bytes.Buffer
	f := NewDefaultFactory(ctx, Formatter{BaseTime: time.Now(), DisableColors: true}, &output, "", nil, false)
	if err := f.Start(); err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	f.SetLevel(LevelWarn)
	f.NewLogger("connection").Error("live failure")
	if !strings.Contains(output.String(), "ERROR") {
		t.Fatal("live errors disappeared")
	}
	output.Reset()
	cancel() // The run loop cancels this generation before closing its services.
	for _, tag := range []string{"connection", "dns", "outbound/fallback[test]", "endpoint/warp[test]", "other-service"} {
		logger := f.NewLogger(tag)
		logger.Error("dns router closed")
		logger.Warn("an arbitrary failure unrelated to cancellation text")
	}
	if output.Len() != 0 {
		t.Fatalf("stopping generation leaked Warn/Error: %s", output.String())
	}
	f.SetLevel(LevelDebug)
	f.NewLogger("connection").Error("arbitrary failure remains diagnosable")
	if !strings.Contains(output.String(), "DEBUG") || !strings.Contains(output.String(), "arbitrary failure remains diagnosable") {
		t.Fatalf("shutdown cause was lost: %s", output.String())
	}
}

func TestCancelledRequestDoesNotMuteRunningGeneration(t *testing.T) {
	var output bytes.Buffer
	f := NewDefaultFactory(context.Background(), Formatter{BaseTime: time.Now(), DisableColors: true}, &output, "", nil, false)
	if err := f.Start(); err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	f.SetLevel(LevelWarn)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	f.NewLogger("connection").ErrorContext(ctx, "real TLS or authentication failure")
	if !strings.Contains(output.String(), "ERROR") {
		t.Fatalf("request cancellation muted a running generation: %s", output.String())
	}
}

func TestStoppedGenerationObserverReceivesDebug(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	f := NewDefaultFactory(ctx, Formatter{BaseTime: time.Now(), DisableColors: true}, &bytes.Buffer{}, "", nil, true)
	if err := f.Start(); err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	sub, _, err := f.Subscribe()
	if err != nil {
		t.Fatal(err)
	}
	defer f.UnSubscribe(sub)
	cancel()
	f.NewLogger("dns").Error("arbitrary runtime failure")
	select {
	case entry := <-sub:
		if entry.Level != LevelDebug {
			t.Fatalf("observer saw shutdown severity %v", entry.Level)
		}
	case <-time.After(time.Second):
		t.Fatal("observer lost shutdown diagnostics")
	}
}

func TestStoppedGenerationStillPanics(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	f := NewDefaultFactory(ctx, Formatter{BaseTime: time.Now(), DisableColors: true}, &bytes.Buffer{}, "", nil, false)
	if err := f.Start(); err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	cancel()
	defer func() {
		if recover() == nil {
			t.Fatal("lifecycle logging disabled panic handling")
		}
	}()
	f.NewLogger("core").Panic("synthetic critical failure")
}
