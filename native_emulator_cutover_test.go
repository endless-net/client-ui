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
	for _, required := range []string{"ENDLESSNET_TESTSERVER:", "./cmd/client-testserver", "80d9cdc16241ca03200381b6b1b04fa5acca1987"} {
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

func TestNativeConsumerCIDiscoversEveryFlutterTest(t *testing.T) {
	raw, err := os.ReadFile(".github/workflows/contract-consumer.yml")
	if err != nil {
		t.Fatal(err)
	}
	workflow := strings.ReplaceAll(string(raw), "\r\n", "\n")
	for _, required := range []string{
		"os: [ubuntu-latest, windows-latest, macos-latest]",
		"flutter pub get --enforce-lockfile",
		"ENDLESSNET_TESTSERVER: ${{ github.workspace }}/client-testserver.exe\n        run: flutter test --no-pub\n",
	} {
		if !strings.Contains(workflow, required) {
			t.Errorf("native consumer CI missing full-suite contract: %s", required)
		}
	}
	if strings.Contains(workflow, "run: flutter test --no-pub test/") {
		t.Fatal("explicit test file allowlists silently omit new native regression tests")
	}
}
