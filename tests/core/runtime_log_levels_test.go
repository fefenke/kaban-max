package log

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestWarnThresholdKeepsWarnErrorAndPanic(t *testing.T) {
	var output bytes.Buffer
	f := NewDefaultFactory(context.Background(), Formatter{DisableColors: true}, &output, "", nil, false)
	if err := f.Start(); err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	f.SetLevel(LevelWarn)
	logger := f.NewLogger("test")
	logger.Trace("hidden trace")
	logger.Debug("hidden debug")
	logger.Info("hidden info")
	logger.Warn("visible warning")
	logger.Error("visible error")
	func() {
		defer func() {
			if recover() == nil {
				t.Fatal("panic was suppressed")
			}
		}()
		logger.Panic("visible panic")
	}()
	got := output.String()
	if strings.Contains(got, "hidden") || !strings.Contains(got, "WARN") || !strings.Contains(got, "ERROR") {
		t.Fatalf("warn threshold incorrect: %s", got)
	}
}

func TestWarnThresholdKeepsFatalAfterGenerationCancellation(t *testing.T) {
	if os.Getenv("KABANMAX_TEST_FATAL_CHILD") == "1" {
		ctx, cancel := context.WithCancel(context.Background())
		f := NewDefaultFactory(ctx, Formatter{DisableColors: true}, os.Stdout, "", nil, false)
		if err := f.Start(); err != nil {
			panic(err)
		}
		f.SetLevel(LevelWarn)
		cancel()
		f.NewLogger("test").Fatal("visible fatal")
		return
	}
	cmd := exec.Command(os.Args[0], "-test.run=^TestWarnThresholdKeepsFatalAfterGenerationCancellation$")
	cmd.Env = append(os.Environ(), "KABANMAX_TEST_FATAL_CHILD=1")
	output, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(output), "FATAL") || !strings.Contains(string(output), "visible fatal") {
		t.Fatalf("fatal was suppressed: err=%v output=%s", err, output)
	}
}
