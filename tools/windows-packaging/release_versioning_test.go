package packaging

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestResolveUIVersionUsesPubspecSemVer(t *testing.T) {
	pwsh := releasePowerShell(t)
	root := filepath.Clean(filepath.Join("..", ".."))
	script := filepath.Join(root, "scripts", "resolve-ui-version.ps1")
	pubspec := filepath.Join(t.TempDir(), "pubspec.yaml")
	githubEnv := filepath.Join(t.TempDir(), "github-env.txt")
	githubOutput := filepath.Join(t.TempDir(), "github-output.txt")
	if err := os.WriteFile(pubspec, []byte("name: endlessnet\nversion: 2.3.4+17\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	cmd := exec.Command(
		pwsh,
		"-NoLogo", "-NoProfile", "-File", script,
		"-Pubspec", pubspec,
		"-GitHubEnv", githubEnv,
		"-GitHubOutput", githubOutput,
	)
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("resolve UI version: %v\n%s", err, output)
	}

	envRaw, err := os.ReadFile(githubEnv)
	if err != nil {
		t.Fatal(err)
	}
	outputRaw, err := os.ReadFile(githubOutput)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"UI_VERSION=2.3.4", "UI_BUILD_NUMBER=17"} {
		if !strings.Contains(string(envRaw), want) {
			t.Errorf("GitHub environment is missing %q: %s", want, envRaw)
		}
	}
	for _, want := range []string{"version=2.3.4", "build_number=17"} {
		if !strings.Contains(string(outputRaw), want) {
			t.Errorf("GitHub output is missing %q: %s", want, outputRaw)
		}
	}
}

func TestReleaseProvenanceKeepsUIAndCoreVersionsIndependent(t *testing.T) {
	pwsh := releasePowerShell(t)
	root := filepath.Clean(filepath.Join("..", ".."))
	script := filepath.Join(root, "scripts", "write-release-provenance.ps1")
	temp := t.TempDir()
	corePath := filepath.Join(temp, "core.json")
	buildPath := filepath.Join(temp, "build.json")
	outputPath := filepath.Join(temp, "release-provenance.json")

	core := map[string]any{
		"version":     "0.2.0",
		"target":      "windows/amd64",
		"ipc_version": "v1",
		"repository":  "unng-lab/endlessnet-client",
		"commit":      strings.Repeat("a", 40),
		"artifacts": map[string]any{
			"client":       map[string]any{"sha256": strings.Repeat("b", 64)},
			"ipc_contract": map[string]any{"sha256": strings.Repeat("c", 64)},
		},
	}
	build := map[string]any{
		"schema_version": 2,
		"version":        "1.4.0",
		"ui_commit":      strings.Repeat("d", 40),
		"target":         "windows/amd64",
		"signed":         true,
		"signing": map[string]any{
			"mode":                   "temporary-self-signed",
			"certificate_thumbprint": strings.Repeat("A", 40),
			"publicly_trusted":       false,
		},
		"client": map[string]any{
			"version":         "0.2.0",
			"unsigned_sha256": strings.Repeat("e", 64),
			"signed_sha256":   strings.Repeat("f", 64),
		},
		"wintun": map[string]any{
			"version":           "0.14.1",
			"archive_sha256":    strings.Repeat("1", 64),
			"sha256":            strings.Repeat("2", 64),
			"signer_thumbprint": strings.Repeat("B", 40),
		},
		"app": map[string]any{
			"unsigned_sha256": strings.Repeat("3", 64),
			"signed_sha256":   strings.Repeat("4", 64),
		},
		"msi": map[string]any{
			"unsigned_sha256": strings.Repeat("5", 64),
			"signed_sha256":   strings.Repeat("6", 64),
		},
	}
	writeJSONFixture(t, corePath, core)
	writeJSONFixture(t, buildPath, build)

	cmd := exec.Command(
		pwsh,
		"-NoLogo", "-NoProfile", "-File", script,
		"-CoreManifest", corePath,
		"-CoreManifestUrl", "https://example.test/core-manifest.json",
		"-CoreManifestSHA256", strings.Repeat("7", 64),
		"-BuildOutput", buildPath,
		"-Output", outputPath,
	)
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("write release provenance: %v\n%s", err, output)
	}

	raw, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatal(err)
	}
	var provenance map[string]any
	if err := json.Unmarshal(raw, &provenance); err != nil {
		t.Fatal(err)
	}
	client := provenance["client"].(map[string]any)
	ui := provenance["ui"].(map[string]any)
	if provenance["version"] != "1.4.0" || ui["version"] != "1.4.0" {
		t.Fatalf("UI provenance version is not independent: %#v", provenance)
	}
	if client["version"] != "0.2.0" {
		t.Fatalf("client-core provenance version = %v, want 0.2.0", client["version"])
	}
}

func releasePowerShell(t *testing.T) string {
	t.Helper()
	if runtime.GOOS != "windows" {
		t.Skip("release workflow uses the Windows PowerShell runner")
	}
	pwsh, err := exec.LookPath("pwsh.exe")
	if err != nil {
		t.Skip("pwsh.exe is not installed")
	}
	return pwsh
}

func writeJSONFixture(t *testing.T, path string, value any) {
	t.Helper()
	raw, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, raw, 0o600); err != nil {
		t.Fatal(err)
	}
}
