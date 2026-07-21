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
		"CORE_VERSION: ${{ github.event.client_payload.version }}",
		"./scripts/resolve-ui-version.ps1",
		"-UIVersion $env:UI_VERSION",
		"-CoreVersion $env:CORE_VERSION",
		"client_version = $env:CORE_VERSION",
		"CLIENT_CORE_RELEASE_TOKEN",
		"client-core/client-ipc-v1.openapi.yaml",
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
		"CLIENT_RELEASE_TOKEN",
		"windows-client-ipc.openapi.yaml",
		"\n      VERSION: ${{ github.event.client_payload.version }}",
		"$env:VERSION",
		"EndlessNet.Client.${{ github.event.client_payload.version }}.msi",
	} {
		if strings.Contains(workflow, removed) {
			t.Errorf("release workflow retains legacy value %q", removed)
		}
	}
}

func TestCoreResolverPinsManifestAndArtifactsToClientRepository(t *testing.T) {
	resolver := readRepositoryFile(t, "scripts/resolve-client-core.ps1")
	for _, required := range []string{
		"[string]$CoreVersion",
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
		"[string]$Version",
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
	for _, required := range []string{
		"version = $build.version",
		"version = $core.version",
		"$core.version -ne $build.client.version",
	} {
		if !strings.Contains(provenance, required) {
			t.Errorf("release provenance does not separate UI/core version via %q", required)
		}
	}

	build := readRepositoryFile(t, "scripts/build-windows-client-msi.ps1")
	for _, required := range []string{
		"[string]$UIVersion",
		"[string]$CoreVersion",
		"--version $UIVersion",
		"ENDLESSNET_VERSION=$UIVersion",
		"version = $CoreVersion",
	} {
		if !strings.Contains(build, required) {
			t.Errorf("Windows build does not separate UI/core version via %q", required)
		}
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
