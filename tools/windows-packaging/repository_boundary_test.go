package packaging

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReleaseConsumesStandalonePublicClientCore(t *testing.T) {
	root := filepath.Clean(filepath.Join("..", ".."))
	files := []string{
		".github/workflows/release.yml",
		"client-core.lock.json",
		"scripts/build-windows-client-msi.ps1",
		"scripts/resolve-client-core.ps1",
		"scripts/resolve-release-idempotency.ps1",
		"scripts/resolve-ui-version.ps1",
		"scripts/write-release-provenance.ps1",
	}
	var combined strings.Builder
	for _, relative := range files {
		raw, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(relative)))
		if err != nil {
			t.Fatal(err)
		}
		combined.Write(raw)
	}
	text := combined.String()
	for _, expected := range []string{
		"client-core.lock.json",
		"CORE_VERSION",
		"UI_VERSION",
		"app\\pubspec.yaml",
		"github.token",
		"endless-net/client/releases/download",
		"client-ipc-v2.openapi.yaml",
		"client = [ordered]@{",
		"schema_version = 3",
	} {
		if !strings.Contains(text, expected) {
			t.Errorf("standalone client release boundary is missing %q", expected)
		}
	}
	for _, removed := range []string{
		"backend_commit",
		"BACKEND_RELEASE_TOKEN",
		"unng-lab/endlessnet/releases/download",
		"windows-client-ipc.openapi.yaml",
		"client-ipc-v1.openapi.yaml",
		"client_core",
		"$env:VERSION",
		"[string]$Version",
	} {
		if strings.Contains(text, removed) {
			t.Errorf("superseded backend client boundary remains: %q", removed)
		}
	}
}
