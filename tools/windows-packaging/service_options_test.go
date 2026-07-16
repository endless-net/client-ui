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
		`"--apply-wireguard"`,
	} {
		if !strings.Contains(args, want) {
			t.Fatalf("service arguments missing %q: %s", want, args)
		}
	}
}
