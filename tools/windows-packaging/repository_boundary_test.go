package packaging

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReleaseConsumesStandaloneClientCore(t *testing.T) {
	root := filepath.Clean(filepath.Join("..", ".."))
	files := []string{
		".github/workflows/release.yml",
		"scripts/resolve-client-core.ps1",
		"scripts/resolve-release-idempotency.ps1",
		"scripts/write-release-provenance.ps1",
	}
	combined := strings.Builder{}
	for _, relative := range files {
		raw, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(relative)))
		if err != nil {
			t.Fatal(err)
		}
		combined.Write(raw)
	}
	text := combined.String()
	for _, expected := range []string{
		"client-core-published",
		"client_commit",
		"CLIENT_CORE_RELEASE_TOKEN",
		"unng-lab/endlessnet-client/releases/download",
		"client-ipc-v1.openapi.yaml",
		"client = [ordered]@{",
	} {
		if !strings.Contains(text, expected) {
			t.Errorf("standalone client release boundary is missing %q", expected)
		}
	}
	for _, removed := range []string{
		"backend-client-core-published",
		"backend_commit",
		"BACKEND_RELEASE_TOKEN",
		"unng-lab/endlessnet/releases/download",
		"windows-client-ipc.openapi.yaml",
		"client_core",
	} {
		if strings.Contains(text, removed) {
			t.Errorf("superseded backend client release boundary remains: %q", removed)
		}
	}
}
