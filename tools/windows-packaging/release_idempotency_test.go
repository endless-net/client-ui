package packaging

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestReleaseIdempotencyTreatsOnlyNotFoundAsMissing(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("release workflow uses the Windows PowerShell runner")
	}
	pwsh, err := exec.LookPath("pwsh.exe")
	if err != nil {
		t.Skip("pwsh.exe is not installed")
	}

	workingDir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	script := filepath.Clean(filepath.Join(workingDir, "..", "..", "scripts", "resolve-release-idempotency.ps1"))
	if _, err := os.Stat(script); err != nil {
		t.Fatal(err)
	}

	fakeGH := filepath.Join(t.TempDir(), "gh.cmd")
	fakeBody := `@echo off
setlocal EnableDelayedExpansion
if /I "%FAKE_GH_MODE%"=="missing" (
  echo HTTP/2.0 404 Not Found
  1>&2 echo gh: Not Found ^(HTTP 404^)
  exit /b 1
)
if /I "%FAKE_GH_MODE%"=="error" (
  echo HTTP/2.0 503 Service Unavailable
  1>&2 echo gh: service unavailable ^(HTTP 503^)
  exit /b 1
)
if /I "%FAKE_GH_MODE%"=="existing" (
  if /I "%~1"=="api" (
    echo HTTP/2.0 200 OK
    echo {"tag_name":"v0.2.0"}
    exit /b 0
  )
  goto existing_download
)
1>&2 echo unexpected fake gh mode
exit /b 2

:existing_download
set "TARGET_DIR="
:parse_existing_args
if "%~1"=="" goto write_provenance
if /I "%~1"=="--dir" (
  set "TARGET_DIR=%~2"
  shift
)
shift
goto parse_existing_args

:write_provenance
if "!TARGET_DIR!"=="" exit /b 3
if not exist "!TARGET_DIR!" mkdir "!TARGET_DIR!"
>"!TARGET_DIR!\release-provenance.json" echo {"client":{"manifest_sha256":"%FAKE_MANIFEST_SHA%"}}
exit /b 0
`
	if err := os.WriteFile(fakeGH, []byte(fakeBody), 0o600); err != nil {
		t.Fatal(err)
	}

	t.Run("missing release continues the owning workflow", func(t *testing.T) {
		outputPath := filepath.Join(t.TempDir(), "github-output.txt")
		cmd := releaseIdempotencyCommand(pwsh, script, fakeGH, outputPath, t.TempDir())
		cmd.Env = append(os.Environ(), "FAKE_GH_MODE=missing")
		output, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("resolve missing release: %v\n%s", err, output)
		}
		raw, err := os.ReadFile(outputPath)
		if err != nil {
			t.Fatal(err)
		}
		if strings.TrimSpace(string(raw)) != "noop=false" {
			t.Fatalf("GitHub output = %q, want noop=false", raw)
		}
	})

	t.Run("real API error fails the owning workflow", func(t *testing.T) {
		outputPath := filepath.Join(t.TempDir(), "github-output.txt")
		cmd := releaseIdempotencyCommand(pwsh, script, fakeGH, outputPath, t.TempDir())
		cmd.Env = append(os.Environ(), "FAKE_GH_MODE=error")
		output, err := cmd.CombinedOutput()
		if err == nil {
			t.Fatalf("resolve release unexpectedly succeeded:\n%s", output)
		}
		if !strings.Contains(string(output), "HTTP 503") {
			t.Fatalf("failure did not retain the API status:\n%s", output)
		}
		if raw, readErr := os.ReadFile(outputPath); readErr == nil && strings.Contains(string(raw), "noop=") {
			t.Fatalf("failed lookup wrote an idempotency result: %q", raw)
		}
	})

	t.Run("matching existing release is an idempotent no-op", func(t *testing.T) {
		outputPath := filepath.Join(t.TempDir(), "github-output.txt")
		cmd := releaseIdempotencyCommand(pwsh, script, fakeGH, outputPath, t.TempDir())
		cmd.Env = append(
			os.Environ(),
			"FAKE_GH_MODE=existing",
			"FAKE_MANIFEST_SHA="+strings.Repeat("a", 64),
		)
		output, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("resolve existing release: %v\n%s", err, output)
		}
		raw, err := os.ReadFile(outputPath)
		if err != nil {
			t.Fatal(err)
		}
		if strings.TrimSpace(string(raw)) != "noop=true" {
			t.Fatalf("GitHub output = %q, want noop=true", raw)
		}
	})

	t.Run("different existing provenance fails", func(t *testing.T) {
		outputPath := filepath.Join(t.TempDir(), "github-output.txt")
		cmd := releaseIdempotencyCommand(pwsh, script, fakeGH, outputPath, t.TempDir())
		cmd.Env = append(
			os.Environ(),
			"FAKE_GH_MODE=existing",
			"FAKE_MANIFEST_SHA="+strings.Repeat("c", 64),
		)
		output, err := cmd.CombinedOutput()
		if err == nil {
			t.Fatalf("mismatched provenance unexpectedly succeeded:\n%s", output)
		}
		if !strings.Contains(string(output), "different core manifest") {
			t.Fatalf("unexpected mismatch failure:\n%s", output)
		}
	})
}

func releaseIdempotencyCommand(pwsh, script, fakeGH, outputPath, runnerTemp string) *exec.Cmd {
	return exec.Command(
		pwsh,
		"-NoLogo", "-NoProfile", "-File", script,
		"-Version", "0.2.0",
		"-ClientCommit", strings.Repeat("b", 40),
		"-CoreManifestSHA256", strings.Repeat("a", 64),
		"-GitHubOutput", outputPath,
		"-RunnerTemp", runnerTemp,
		"-GitHubCLI", fakeGH,
	)
}
