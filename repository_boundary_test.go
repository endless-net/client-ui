package repository_test

import (
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestWindowsReleaseUsesUITagAndReviewedCoreLock(t *testing.T) {
	workflow := readRepositoryFile(t, ".github/workflows/release.yml")
	for _, required := range []string{
		`tags:`,
		`- "v*"`,
		`${{ github.ref_name }}`,
		`./client-core.lock.json`,
		`./scripts/resolve-client-core.ps1`,
		`windows-2025`,
		`GH_TOKEN: ${{ github.token }}`,
		`-UIVersion $env:UI_VERSION`,
		`-CoreVersion $env:CORE_VERSION`,
		`-RecoveryHelperExe "${{ steps.core.outputs.recovery_helper_exe }}"`,
		`windows-distribution-sbom.spdx.json`,
	} {
		if !strings.Contains(workflow, required) {
			t.Errorf("release workflow is missing %q", required)
		}
	}

	ci := readRepositoryFile(t, ".github/workflows/ci.yml")
	for _, workflowText := range []string{ci, workflow} {
		if !strings.Contains(workflowText, "permissions:") ||
			!strings.Contains(workflowText, "contents: read") {
			t.Error("workflow must default to read-only repository contents")
		}
	}
}

func TestActionsArePinnedToFullCommitSHAs(t *testing.T) {
	actionUse := regexp.MustCompile(`(?m)^\s*-\s+uses:\s+[^@\s]+@([^\s#]+)`)
	fullSHA := regexp.MustCompile(`^[0-9a-f]{40}$`)
	for _, path := range []string{
		".github/workflows/ci.yml",
		".github/workflows/release.yml",
	} {
		workflow := readRepositoryFile(t, path)
		matches := actionUse.FindAllStringSubmatch(workflow, -1)
		if len(matches) == 0 {
			t.Fatalf("%s has no actions to validate", path)
		}
		for _, match := range matches {
			if !fullSHA.MatchString(match[1]) {
				t.Errorf("%s contains an action not pinned to a full commit SHA: %s", path, match[0])
			}
		}
	}
}

func TestCoreResolverConsumesOnlyReviewedLock(t *testing.T) {
	resolver := readRepositoryFile(t, "scripts/resolve-client-core.ps1")
	for _, required := range []string{
		`[string]$LockFile`,
		`client-core.lock.json`,
		`$lock.schema_version -ne 1`,
		`$lock.repository -cne "endless-net/client"`,
		`$lock.tag -cne "v$($lock.version)"`,
		`/releases/tags/$($lock.tag)`,
		`/git/ref/tags/$($lock.tag)`,
		`/git/tags/$tagObjectSHA`,
		`client core tag does not resolve to the reviewed commit`,
		`$manifest.artifacts.ipc_contract.sha256`,
		`$manifest.artifacts.recovery_helper.sha256`,
		`endlessnet-client-recovery-helper_windows_amd64.exe`,
		`endlessnet-client-recovery-helper.exe`,
		`"attestation", "verify"`,
		`--signer-workflow`,
		`--source-ref`,
		`--source-digest`,
		`--deny-self-hosted-runners`,
		`checked-in IPC contract does not match`,
	} {
		if !strings.Contains(resolver, required) {
			t.Errorf("client core resolver is missing %q", required)
		}
	}

	provenance := readRepositoryFile(t, "scripts/write-release-provenance.ps1")
	for _, required := range []string{
		"schema_version = 3",
		"lock_sha256",
		"ui_source_sha256",
		"windows_distribution_sha256",
		"client = [ordered]@{",
		"recovery_helper = [ordered]@{",
	} {
		if !strings.Contains(provenance, required) {
			t.Errorf("release provenance is missing %q", required)
		}
	}
}

func TestVendoredIPCContractTracksPublishedProducerRevision(t *testing.T) {
	provenance := readRepositoryFile(t, "contracts/upstream/README.md")
	lock := readRepositoryFile(t, "client-core.lock.json")
	for _, required := range []string{
		"v0.4.1",
		"517780f5d748a241ca9975fe75d02de2cd074182",
		"client-ipc-v2.openapi.yaml",
		"996103b8bfc8ed60ec9cd5ea9407662388e48bf35e75d70f96cef3c159971eca",
		"6c9013ed51810ec65606358f81f5eb6750aeb638",
	} {
		if !strings.Contains(provenance, required) {
			t.Errorf("vendored IPC provenance is missing %q", required)
		}
	}
	for _, required := range []string{
		`"repository": "endless-net/client"`,
		`"version": "0.4.1"`,
		`"commit": "517780f5d748a241ca9975fe75d02de2cd074182"`,
	} {
		if !strings.Contains(lock, required) {
			t.Errorf("reviewed client core lock is missing %q", required)
		}
	}
}

func TestProductionTreeHasNoIPCVersion1References(t *testing.T) {
	forbidden := []string{
		strings.Join([]string{"client-ipc", "v1"}, "-"),
		strings.Join([]string{"ipc", "v1"}, "/"),
	}
	err := filepath.WalkDir(".", func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() {
			switch entry.Name() {
			case ".git", ".artifacts", ".dart_tool", "build", "dist", "ephemeral":
				return filepath.SkipDir
			default:
				return nil
			}
		}
		if strings.HasSuffix(path, "_test.go") || entry.Type()&os.ModeSymlink != 0 {
			return nil
		}
		raw, readErr := os.ReadFile(path)
		if readErr != nil {
			return readErr
		}
		text := string(raw)
		for _, removed := range forbidden {
			if strings.Contains(text, removed) {
				t.Errorf("%s retains IPC version 1 reference %q", path, removed)
			}
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}

func TestPublicTreeHasNoLegacyReleaseCoupling(t *testing.T) {
	forbidden := []string{
		strings.Join([]string{"endlessnet", "front"}, ""),
		strings.Join([]string{"FRONT", "RELEASE", "TOKEN"}, "_"),
		strings.Join([]string{"windows", "client", "ui", "published"}, "-"),
		strings.Join([]string{"CLIENT", "CORE", "RELEASE", "TOKEN"}, "_"),
		strings.Join([]string{"repository", "dispatch"}, "_"),
		strings.Join([]string{"client", "core", "published"}, "-"),
		strings.Join([]string{"private", "release"}, " "),
		strings.Join([]string{"private", "mirror"}, " "),
	}
	skipDirs := map[string]bool{
		".git":       true,
		".artifacts": true,
		".dart_tool": true,
		"build":      true,
		"dist":       true,
		"ephemeral":  true,
	}
	err := filepath.WalkDir(".", func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() && path != "." && skipDirs[entry.Name()] {
			return filepath.SkipDir
		}
		if entry.IsDir() {
			return nil
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return nil
		}
		raw, readErr := os.ReadFile(path)
		if readErr != nil {
			return readErr
		}
		lower := strings.ToLower(string(raw))
		for _, value := range forbidden {
			if strings.Contains(lower, strings.ToLower(value)) {
				t.Errorf("%s retains removed release coupling %q", path, value)
			}
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
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
