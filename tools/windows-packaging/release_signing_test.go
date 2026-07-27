package packaging

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReleaseSigningIsIsolatedAndCleanedUp(t *testing.T) {
	root := filepath.Clean(filepath.Join("..", ".."))
	read := func(relative string) string {
		raw, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(relative)))
		if err != nil {
			t.Fatal(err)
		}
		return string(raw)
	}

	release := read(".github/workflows/release.yml")
	ci := read(".github/workflows/ci.yml")
	importScript := read("scripts/import-release-signing-certificate.ps1")
	cleanupScript := read("scripts/remove-release-signing-certificate.ps1")
	buildScript := read("scripts/build-windows-client-msi.ps1")
	provenanceScript := read("scripts/write-release-provenance.ps1")

	for _, expected := range []string{
		"environment: release",
		"temporary-self-signed",
		"WINDOWS_CODESIGN_EXPECTED_THUMBPRINT",
		"secrets.WINDOWS_CODESIGN_PFX_BASE64",
		"secrets.WINDOWS_CODESIGN_PFX_PASSWORD",
		"Remove release signing certificate and private key",
		"if: ${{ always() }}",
		"unexpected Authenticode signer",
		"official Wintun signature was replaced",
		"does not provide public Windows trust or Microsoft SmartScreen reputation",
	} {
		if !strings.Contains(release, expected) {
			t.Errorf("release workflow is missing %q", expected)
		}
	}
	for _, forbidden := range []string{
		"WINDOWS_CODESIGN_PFX_BASE64",
		"WINDOWS_CODESIGN_PFX_PASSWORD",
	} {
		if strings.Contains(ci, forbidden) {
			t.Errorf("pull-request workflow references protected release secret %q", forbidden)
		}
	}
	for _, expected := range []string{
		"Import-PfxCertificate",
		"-Exportable:$false",
		"temporary-self-signed mode requires a self-signed code-signing certificate",
		"public-authenticode mode rejects self-signed certificates",
	} {
		if !strings.Contains(importScript, expected) {
			t.Errorf("release signing import is missing %q", expected)
		}
	}
	for _, expected := range []string{
		"CngKey]::Open",
		"PersistKeyInCsp = $false",
		"Remove-TrackedCertificates Cert:\\CurrentUser\\My",
	} {
		if !strings.Contains(cleanupScript, expected) {
			t.Errorf("release signing cleanup is missing %q", expected)
		}
	}
	if strings.Contains(importScript+cleanupScript, "Cert:\\CurrentUser\\Root") {
		t.Error("temporary self-signed release must not modify the trusted root store")
	}
	for _, expected := range []string{
		"Invoke-EndlessNetSign $packagedClientExe",
		"Invoke-EndlessNetSign $appExe",
		"Invoke-EndlessNetSign $Msi",
		"Official Wintun signature must not be replaced",
		"certificate_thumbprint",
	} {
		if !strings.Contains(buildScript, expected) {
			t.Errorf("signed release build is missing %q", expected)
		}
	}
	for _, expected := range []string{
		"temporary self-signed release metadata must not claim public trust",
		"smartscreen_reputation",
		"not-provided",
		"signer_thumbprint",
	} {
		if !strings.Contains(provenanceScript, expected) {
			t.Errorf("release provenance is missing %q", expected)
		}
	}
}
