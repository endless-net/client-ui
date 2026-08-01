package packaging

import (
	"strings"
	"testing"
	"time"
)

func TestWindowsPackagingServiceContractIsStable(t *testing.T) {
	opts := DefaultWindowsServiceOptions()
	args := strings.Join(windowsServiceAgentArgs(opts), " ")
	for _, want := range []string{
		`"agent"`,
		`"--windows-service"`,
		`"--config" "C:\ProgramData\EndlessNet\client.json"`,
		`"--state-output" "C:\ProgramData\EndlessNet\agent-state.json"`,
		`"--diagnostics-dir" "C:\ProgramData\EndlessNet\Diagnostics"`,
		`"--timeout" "10s"`,
		`"--debug"`,
	} {
		if !strings.Contains(args, want) {
			t.Fatalf("service arguments missing %q: %s", want, args)
		}
	}
	for _, forbidden := range []string{
		"--output",
		"endlessnet.conf",
		"--ipc-pipe",
		"--interval",
		"--stun-timeout",
		"--reconnect-max-delay",
		"--reconnect-jitter",
		"--event-log-source",
		"--debug-log-dir",
		"--userspace-wireguard",
		"--apply-wireguard",
		"--apply-wg-quick",
		"--wireguard-windows",
	} {
		if strings.Contains(args, forbidden) {
			t.Fatalf("default service arguments contain redundant or unsupported flag %q: %s", forbidden, args)
		}
	}
	if strings.Contains(args, "--listen-port") {
		t.Fatalf("default service arguments contain a fixed WireGuard port: %s", args)
	}
	if len(args) > 255 {
		t.Fatalf("default service arguments are %d characters, want at most 255: %s", len(args), args)
	}
}

func TestWindowsPackagingServiceContractIncludesNonDefaultOverrides(t *testing.T) {
	opts := DefaultWindowsServiceOptions()
	opts.Interval = time.Minute
	opts.STUNTimeout = 3 * time.Second
	opts.ReconnectMaxDelay = 10 * time.Minute
	opts.ReconnectJitter = 0.5
	opts.IPCPipe = `\\.\pipe\endlessnet-custom`
	opts.EventLogSource = "EndlessNet Custom"
	opts.DebugLogDir = `C:\ProgramData\EndlessNet\Logs`
	opts.ListenPort = 51820

	args := strings.Join(windowsServiceAgentArgs(opts), " ")
	for _, want := range []string{
		`"--interval" "1m0s"`,
		`"--stun-timeout" "3s"`,
		`"--reconnect-max-delay" "10m0s"`,
		`"--reconnect-jitter" "0.5"`,
		`"--ipc-pipe" "\\.\pipe\endlessnet-custom"`,
		`"--event-log-source" "EndlessNet Custom"`,
		`"--debug-log-dir" "C:\ProgramData\EndlessNet\Logs"`,
		`"--listen-port" "51820"`,
	} {
		if !strings.Contains(args, want) {
			t.Fatalf("service arguments missing non-default override %q: %s", want, args)
		}
	}
}
