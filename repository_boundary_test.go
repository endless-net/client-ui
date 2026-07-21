package repository_test

import (
	"os"
	"strings"
	"testing"
)

func TestWindowsReleaseConsumesStrictClientCoreDispatch(t *testing.T) {
	workflow := readRepositoryFile(t, ".github/workflows/release.yml")
	for _, required := range []string{
		"types: [client-core-published]",
		"github.event.client_payload.client_commit",
		"CLIENT_RELEASE_TOKEN",
		"client-core/client-ipc-v1.openapi.yaml",
		"existing.client.manifest_sha256",
	} {
		if !strings.Contains(workflow, required) {
			t.Errorf("release workflow is missing %q", required)
		}
	}
	for _, removed := range []string{
		"backend-client-core-published",
		"backend_commit",
		"BACKEND_COMMIT",
		"BACKEND_RELEASE_TOKEN",
		"windows-client-ipc.openapi.yaml",
	} {
		if strings.Contains(workflow, removed) {
			t.Errorf("release workflow retains legacy value %q", removed)
		}
	}
}

func TestCoreResolverPinsManifestAndArtifactsToClientRepository(t *testing.T) {
	resolver := readRepositoryFile(t, "scripts/resolve-client-core.ps1")
	for _, required := range []string{
		"[string]$ClientCommit",
		"unng-lab/endlessnet-client/releases/download/$tag/$manifestAsset",
		"--repo unng-lab/endlessnet-client",
		"/repos/unng-lab/endlessnet-client/releases/tags/$tag",
		"$contractAsset = \"client-ipc-v1.openapi.yaml\"",
		"$manifest.artifacts.ipc_contract.sha256",
		"$manifest.artifacts.ipc_contract.name -ne $contractAsset",
	} {
		if !strings.Contains(resolver, required) {
			t.Errorf("client core resolver is missing %q", required)
		}
	}
	for _, removed := range []string{
		"[string]$BackendCommit",
		"unng-lab/endlessnet/releases/download",
		"--repo unng-lab/endlessnet ",
		"windows-client-ipc.openapi.yaml",
	} {
		if strings.Contains(resolver, removed) {
			t.Errorf("client core resolver retains legacy value %q", removed)
		}
	}

	provenance := readRepositoryFile(t, "scripts/write-release-provenance.ps1")
	if !strings.Contains(provenance, "client = [ordered]@{") || strings.Contains(provenance, "backend = [ordered]@{") {
		t.Error("release provenance must identify the client producer without a backend alias")
	}
}

func readRepositoryFile(t *testing.T, path string) string {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(raw)
}
