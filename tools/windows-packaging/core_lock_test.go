package packaging

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

type coreLockFixture struct {
	root             string
	lockPath         string
	assetsDir        string
	expectedContract string
	fakeGH           string
	commit           string
	tagObject        string
}

func TestResolveClientCoreAcceptsReviewedLock(t *testing.T) {
	fixture := newCoreLockFixture(t)
	output, err := fixture.run(t)
	if err != nil {
		t.Fatalf("resolve reviewed core lock: %v\n%s", err, output)
	}
	for _, name := range []string{
		"client-core-manifest.json",
		"endlessnet-client_windows_amd64.exe",
		"client-ipc-v1.openapi.yaml",
		"LICENSE",
		"NOTICE",
		"THIRD_PARTY_NOTICES",
		"source-sbom.spdx.json",
	} {
		if _, err := os.Stat(filepath.Join(fixture.root, "output", name)); err != nil {
			t.Errorf("resolved asset %s: %v", name, err)
		}
	}
}

func TestResolveClientCoreRejectsInvalidLockSchema(t *testing.T) {
	fixture := newCoreLockFixture(t)
	lock := readJSONMap(t, fixture.lockPath)
	lock["schema_version"] = 2
	writeJSONFixture(t, fixture.lockPath, lock)
	fixture.expectFailure(t, "unsupported client core lock schema")
}

func TestResolveClientCoreRejectsAssetHashMismatch(t *testing.T) {
	fixture := newCoreLockFixture(t)
	path := filepath.Join(fixture.assetsDir, "endlessnet-client_windows_amd64.exe")
	if err := os.WriteFile(path, []byte("tampered"), 0o600); err != nil {
		t.Fatal(err)
	}
	fixture.expectFailure(t, "client core asset digest mismatch")
}

func TestResolveClientCoreRejectsWrongTagTarget(t *testing.T) {
	fixture := newCoreLockFixture(t)
	output, err := fixture.runWithEnv(t, "FAKE_TAG_COMMIT="+strings.Repeat("f", 40))
	if err == nil {
		t.Fatalf("resolver accepted the wrong tag target:\n%s", output)
	}
	if !strings.Contains(string(output), "tag does not resolve to the reviewed commit") {
		t.Fatalf("unexpected tag-target failure:\n%s", output)
	}
}

func TestResolveClientCoreRejectsIPCMismatch(t *testing.T) {
	fixture := newCoreLockFixture(t)
	if err := os.WriteFile(fixture.expectedContract, []byte("different IPC"), 0o600); err != nil {
		t.Fatal(err)
	}
	fixture.expectFailure(t, "checked-in IPC contract does not match")
}

func newCoreLockFixture(t *testing.T) coreLockFixture {
	t.Helper()
	root := t.TempDir()
	assetsDir := filepath.Join(root, "assets")
	if err := os.MkdirAll(assetsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	commit := strings.Repeat("a", 40)
	tagObject := strings.Repeat("b", 40)
	releaseBase := "https://github.com/endless-net/client/releases/download/v0.3.1"
	assetContents := map[string][]byte{
		"endlessnet-client_windows_amd64.exe": []byte("test client executable"),
		"client-ipc-v1.openapi.yaml":          []byte("openapi: 3.1.0\ninfo:\n  title: fixture\n"),
		"LICENSE":                             []byte("Apache License\nVersion 2.0, January 2004\n"),
		"NOTICE":                              []byte("EndlessNet fixture notice\n"),
		"THIRD_PARTY_NOTICES":                 []byte("Fixture dependency notices\n"),
		"source-sbom.spdx.json":               []byte(`{"spdxVersion":"SPDX-2.3"}`),
	}
	for name, content := range assetContents {
		if err := os.WriteFile(filepath.Join(assetsDir, name), content, 0o600); err != nil {
			t.Fatal(err)
		}
	}

	manifest := map[string]any{
		"schema_version": 1,
		"repository":     "endless-net/client",
		"version":        "0.3.1",
		"commit":         commit,
		"target":         "windows/amd64",
		"ipc_version":    "v1",
		"artifacts": map[string]any{
			"client": map[string]any{
				"name":   "endlessnet-client_windows_amd64.exe",
				"url":    releaseBase + "/endlessnet-client_windows_amd64.exe",
				"sha256": testSHA256(assetContents["endlessnet-client_windows_amd64.exe"]),
			},
			"ipc_contract": map[string]any{
				"name":   "client-ipc-v1.openapi.yaml",
				"url":    releaseBase + "/client-ipc-v1.openapi.yaml",
				"sha256": testSHA256(assetContents["client-ipc-v1.openapi.yaml"]),
			},
		},
	}
	manifestPath := filepath.Join(assetsDir, "endlessnet-client_windows_amd64.manifest.json")
	writeJSONFixture(t, manifestPath, manifest)
	manifestRaw, err := os.ReadFile(manifestPath)
	if err != nil {
		t.Fatal(err)
	}

	compliance := map[string]any{}
	for _, entry := range []struct {
		key  string
		name string
	}{
		{"license", "LICENSE"},
		{"notice", "NOTICE"},
		{"third_party_notices", "THIRD_PARTY_NOTICES"},
		{"source_sbom", "source-sbom.spdx.json"},
	} {
		compliance[entry.key] = map[string]any{
			"name":   entry.name,
			"url":    releaseBase + "/" + entry.name,
			"sha256": testSHA256(assetContents[entry.name]),
		}
	}
	lock := map[string]any{
		"schema_version": 1,
		"repository":     "endless-net/client",
		"version":        "0.3.1",
		"tag":            "v0.3.1",
		"commit":         commit,
		"manifest": map[string]any{
			"name":   "endlessnet-client_windows_amd64.manifest.json",
			"url":    releaseBase + "/endlessnet-client_windows_amd64.manifest.json",
			"sha256": testSHA256(manifestRaw),
		},
		"compliance": compliance,
	}
	lockPath := filepath.Join(root, "client-core.lock.json")
	writeJSONFixture(t, lockPath, lock)
	expectedContract := filepath.Join(root, "client-ipc-v1.openapi.yaml")
	if err := os.WriteFile(expectedContract, assetContents["client-ipc-v1.openapi.yaml"], 0o600); err != nil {
		t.Fatal(err)
	}
	fakeGH := filepath.Join(root, "fake-gh.ps1")
	fakeGHBody := `$endpoint = $args[1]
if ($endpoint -like "*/releases/tags/*") {
    Write-Output $env:FAKE_RELEASE_TARGET
    exit 0
}
if ($endpoint -like "*/git/ref/tags/*") {
    Write-Output "tag|$env:FAKE_TAG_OBJECT"
    exit 0
}
if ($endpoint -like "*/git/tags/*") {
    Write-Output "commit|$env:FAKE_TAG_COMMIT"
    exit 0
}
Write-Error "unexpected API endpoint: $endpoint"
exit 2
`
	if err := os.WriteFile(fakeGH, []byte(fakeGHBody), 0o600); err != nil {
		t.Fatal(err)
	}
	return coreLockFixture{
		root:             root,
		lockPath:         lockPath,
		assetsDir:        assetsDir,
		expectedContract: expectedContract,
		fakeGH:           fakeGH,
		commit:           commit,
		tagObject:        tagObject,
	}
}

func (fixture coreLockFixture) run(t *testing.T) ([]byte, error) {
	t.Helper()
	return fixture.runWithEnv(t)
}

func (fixture coreLockFixture) runWithEnv(t *testing.T, overrides ...string) ([]byte, error) {
	t.Helper()
	pwsh := releasePowerShell(t)
	root := filepath.Clean(filepath.Join("..", ".."))
	script := filepath.Join(root, "scripts", "resolve-client-core.ps1")
	cmd := exec.Command(
		pwsh,
		"-NoLogo", "-NoProfile", "-File", script,
		"-LockFile", fixture.lockPath,
		"-OutputDir", filepath.Join(fixture.root, "output"),
		"-ExpectedContract", fixture.expectedContract,
		"-GitHubEnv", "",
		"-GitHubOutput", "",
		"-GitHubCLI", fixture.fakeGH,
		"-AssetSourceDir", fixture.assetsDir,
	)
	env := append(
		os.Environ(),
		"FAKE_RELEASE_TARGET="+fixture.commit,
		"FAKE_TAG_OBJECT="+fixture.tagObject,
		"FAKE_TAG_COMMIT="+fixture.commit,
	)
	cmd.Env = append(env, overrides...)
	return cmd.CombinedOutput()
}

func (fixture coreLockFixture) expectFailure(t *testing.T, want string) {
	t.Helper()
	output, err := fixture.run(t)
	if err == nil {
		t.Fatalf("resolver unexpectedly succeeded:\n%s", output)
	}
	if !strings.Contains(string(output), want) {
		t.Fatalf("resolver failure does not contain %q:\n%s", want, output)
	}
}

func testSHA256(raw []byte) string {
	return fmt.Sprintf("%x", sha256.Sum256(raw))
}

func readJSONMap(t *testing.T, path string) map[string]any {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var value map[string]any
	if err := json.Unmarshal(raw, &value); err != nil {
		t.Fatal(err)
	}
	return value
}
