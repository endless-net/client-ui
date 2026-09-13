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
