package repository_test

import (
	"os"
	"strings"
	"testing"
)

func TestNativeEmulatorCutover(t *testing.T) {
	for _, path := range []string{
		"tools/service-emulator/scenario.go",
		"tools/service-emulator/server_windows.go",
		"scripts/test-ui-with-service-emulator.ps1",
		"app/test/service_emulator_e2e_test.dart",
		"app/test/support/service_emulator.dart",
		"app/lib/named_pipe_http.dart",
		"app/lib/service_contract.dart",
		"app/test/named_pipe_http_test.dart",
		"app/test/named_pipe_live_test.dart",
		"app/test/ui_contract_e2e_test.dart",
	} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Errorf("retired emulator path must remain absent: %s", path)
		}
	}
	data, err := os.ReadFile(".github/workflows/ci.yml")
	if err != nil {
		t.Fatal(err)
	}
	workflow := string(data)
	for _, required := range []string{"ENDLESSNET_TESTSERVER:", "./cmd/client-testserver", "ac30bfe0e959f3c93ef1059495f2356fa5476b06"} {
		if !strings.Contains(workflow, required) {
			t.Errorf("CI missing native host wiring: %s", required)
		}
	}
	if strings.Contains(workflow, "ENDLESSNET_SERVICE_EMULATOR") {
		t.Fatal("CI must not use the retired HTTP emulator")
	}
}

func TestDesktopEntrypointUsesOnlyNativeSession(t *testing.T) {
	raw, err := os.ReadFile("app/lib/main.dart")
	if err != nil {
		t.Fatal(err)
	}
	source := string(raw)
	for _, retired := range []string{"EndlessNetController", "EndlessNetClientBridge", "ServiceIPC", "named_pipe_http", "service_contract"} {
		if strings.Contains(source, retired) {
			t.Errorf("entrypoint retains %s", retired)
		}
	}
	for _, required := range []string{"ClientSession(", "ClientDesktopApp(", "validateLocalEndpoint(endpoint)"} {
		if !strings.Contains(source, required) {
			t.Errorf("entrypoint missing %s", required)
		}
	}
}
