package client

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestRenderWindowsWingetArtifacts(t *testing.T) {
	opts := DefaultWindowsWingetOptions()
	opts.Version = "1.2.3"
	opts.InstallerURL = "https://endlessnet.ru/downloads/EndlessNet.Client.1.2.3.msi"
	opts.InstallerSHA256 = strings.Repeat("a", 64)
	opts.ReleaseDate = "2026-07-07"

	artifacts, err := RenderWindowsWingetArtifacts(opts)
	if err != nil {
		t.Fatal(err)
	}
	if artifacts.VersionManifestFile != "EndlessNet.Client.yaml" {
		t.Fatalf("version manifest file = %q", artifacts.VersionManifestFile)
	}
	for _, want := range []string{
		"PackageIdentifier: 'EndlessNet.Client'",
		"PackageVersion: '1.2.3'",
		"DefaultLocale: en-US",
		"ManifestType: version",
		"ManifestVersion: '1.12.0'",
	} {
		if !strings.Contains(artifacts.VersionManifest, want) {
			t.Fatalf("version manifest missing %q:\n%s", want, artifacts.VersionManifest)
		}
	}
	for _, want := range []string{
		"InstallerType: wix",
		"Scope: machine",
		"UpgradeBehavior: install",
		"- endlessnet-client",
		"- endlessnet-tray",
		"- endlessnet",
		"InstallerUrl: 'https://endlessnet.ru/downloads/EndlessNet.Client.1.2.3.msi'",
		"InstallerSha256: '" + strings.Repeat("A", 64) + "'",
		"UpgradeCode: '{9f7a7362-64c3-4b3a-9a58-7c8fc90779e1}'",
		"ReleaseDate: '2026-07-07'",
		"ManifestType: installer",
	} {
		if !strings.Contains(artifacts.InstallerManifest, want) {
			t.Fatalf("installer manifest missing %q:\n%s", want, artifacts.InstallerManifest)
		}
	}
	for _, want := range []string{
		"PackageLocale: en-US",
		"Publisher: 'UNNG'",
		"PackageName: 'EndlessNet Client'",
		"License: 'Proprietary'",
		"ShortDescription: 'EndlessNet Windows VPN client'",
		"PackageUrl: 'https://endlessnet.ru'",
		"- wireguard",
		"ManifestType: defaultLocale",
	} {
		if !strings.Contains(artifacts.LocaleManifest, want) {
			t.Fatalf("locale manifest missing %q:\n%s", want, artifacts.LocaleManifest)
		}
	}
	for _, leak := range []string{"enr_fixture_secret", "session-token", "private-key-value", "node-credential-value"} {
		if strings.Contains(artifacts.VersionManifest, leak) || strings.Contains(artifacts.InstallerManifest, leak) || strings.Contains(artifacts.LocaleManifest, leak) {
			t.Fatalf("winget artifacts leaked %q", leak)
		}
	}
}

func TestWriteWindowsWingetArtifactsComputesInstallerHash(t *testing.T) {
	outputDir := t.TempDir()
	msiPath := filepath.Join(outputDir, "EndlessNet.Client.msi")
	msiBody := []byte("fixture-msi")
	if err := os.WriteFile(msiPath, msiBody, 0o600); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(msiBody)
	wantHash := strings.ToUpper(hex.EncodeToString(sum[:]))

	opts := DefaultWindowsWingetOptions()
	opts.Version = "1.2.3"
	opts.InstallerURL = "https://endlessnet.ru/downloads/EndlessNet.Client.1.2.3.msi"
	opts.InstallerFile = msiPath
	artifacts, err := WriteWindowsWingetArtifacts(outputDir, opts)
	if err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{artifacts.VersionManifestFile, artifacts.InstallerManifestFile, artifacts.LocaleManifestFile} {
		if filepath.Dir(path) != outputDir {
			t.Fatalf("artifact path %s is outside %s", path, outputDir)
		}
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if runtime.GOOS != "windows" && info.Mode().Perm() != 0o644 {
			t.Fatalf("%s mode = %o, want 644", path, info.Mode().Perm())
		}
	}
	raw, err := os.ReadFile(artifacts.InstallerManifestFile)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), "InstallerSha256: '"+wantHash+"'") {
		t.Fatalf("installer manifest missing computed hash %s:\n%s", wantHash, raw)
	}
}

func TestRenderWindowsWingetArtifactsRejectsUnsafeValues(t *testing.T) {
	for _, tc := range []struct {
		name string
		mut  func(*WindowsWingetOptions)
		want string
	}{
		{name: "missing hash", mut: func(o *WindowsWingetOptions) { o.InstallerSHA256 = "" }, want: "installer SHA256 is required"},
		{name: "http URL", mut: func(o *WindowsWingetOptions) { o.InstallerURL = "http://example.test/client.msi" }, want: "HTTPS"},
		{name: "bad identifier", mut: func(o *WindowsWingetOptions) { o.PackageIdentifier = "EndlessNet" }, want: "dotted"},
		{name: "bad hash", mut: func(o *WindowsWingetOptions) { o.InstallerSHA256 = "not-a-hash" }, want: "64 hexadecimal"},
		{name: "newline", mut: func(o *WindowsWingetOptions) { o.Description = "client\nsecret" }, want: "newlines"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			opts := DefaultWindowsWingetOptions()
			opts.Version = "1.2.3"
			opts.InstallerURL = "https://endlessnet.ru/downloads/EndlessNet.Client.1.2.3.msi"
			opts.InstallerSHA256 = strings.Repeat("a", 64)
			tc.mut(&opts)
			_, err := RenderWindowsWingetArtifacts(opts)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("error = %v, want containing %q", err, tc.want)
			}
		})
	}
}
