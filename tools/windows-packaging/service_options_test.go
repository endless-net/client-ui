package packaging

import (
	"strings"
	"testing"
)

func TestWindowsPackagingServiceContractIsStable(t *testing.T) {
	opts := DefaultWindowsServiceOptions()
	args := strings.Join(windowsServiceAgentArgs(opts), " ")
	for _, want := range []string{
		`"agent"`,
		`"--windows-service"`,
		`"--ipc-pipe" "\\.\pipe\endlessnet-service"`,
		`"--config" "C:\ProgramData\EndlessNet\client.json"`,
	} {
		if !strings.Contains(args, want) {
			t.Fatalf("service arguments missing %q: %s", want, args)
		}
	}
	for _, obsolete := range []string{"--userspace-wireguard", "--apply-wireguard", "--apply-wg-quick", "--wireguard-windows"} {
		if strings.Contains(args, obsolete) {
			t.Fatalf("default service arguments contain obsolete WireGuard backend selector %q: %s", obsolete, args)
		}
	}
	if strings.Contains(args, "--listen-port") {
		t.Fatalf("default service arguments contain a fixed WireGuard port: %s", args)
	}
}
