package packaging

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

type WindowsWingetOptions struct {
	PackageIdentifier string
	PackageName       string
	Publisher         string
	Version           string
	InstallerURL      string
	InstallerSHA256   string
	InstallerFile     string
	Homepage          string
	License           string
	Description       string
	ShortDescription  string
	ReleaseDate       string
	ManifestVersion   string
	Architecture      string
	UpgradeCode       string
}

type WindowsWingetArtifacts struct {
	VersionManifestFile   string `json:"version_manifest_file"`
	InstallerManifestFile string `json:"installer_manifest_file"`
	LocaleManifestFile    string `json:"locale_manifest_file"`
	VersionManifest       string `json:"version_manifest"`
	InstallerManifest     string `json:"installer_manifest"`
	LocaleManifest        string `json:"locale_manifest"`
}

var (
	wingetPackageIdentifierPattern = regexp.MustCompile(`^[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)+$`)
	wingetVersionPattern           = regexp.MustCompile(`^[0-9A-Za-z][0-9A-Za-z._+-]*$`)
	wingetSHA256Pattern            = regexp.MustCompile(`^[A-Fa-f0-9]{64}$`)
)

func DefaultWindowsWingetOptions() WindowsWingetOptions {
	installerDefaults := DefaultWindowsInstallerOptions()
	return WindowsWingetOptions{
		PackageIdentifier: "EndlessNet.Client",
		PackageName:       "EndlessNet Client",
		Publisher:         "UNNG",
		Version:           installerDefaults.Version,
		Homepage:          "https://endlessnet.ru",
		License:           "Proprietary",
		Description:       "EndlessNet desktop and server client for private WireGuard-style networks.",
		ShortDescription:  "EndlessNet Windows VPN client",
		ManifestVersion:   "1.12.0",
		Architecture:      "x64",
		UpgradeCode:       installerDefaults.UpgradeCode,
	}
}

func RenderWindowsWingetArtifacts(opts WindowsWingetOptions) (WindowsWingetArtifacts, error) {
	opts, err := normalizeWindowsWingetOptions(opts)
	if err != nil {
		return WindowsWingetArtifacts{}, err
	}
	if err := validateWindowsWingetOptions(opts); err != nil {
		return WindowsWingetArtifacts{}, err
	}
	baseName := opts.PackageIdentifier
	return WindowsWingetArtifacts{
		VersionManifestFile:   baseName + ".yaml",
		InstallerManifestFile: baseName + ".installer.yaml",
		LocaleManifestFile:    baseName + ".locale.en-US.yaml",
		VersionManifest:       renderWindowsWingetVersionManifest(opts),
		InstallerManifest:     renderWindowsWingetInstallerManifest(opts),
		LocaleManifest:        renderWindowsWingetLocaleManifest(opts),
	}, nil
}

func WriteWindowsWingetArtifacts(outputDir string, opts WindowsWingetOptions) (WindowsWingetArtifacts, error) {
	if strings.TrimSpace(outputDir) == "" {
		return WindowsWingetArtifacts{}, errors.New("output directory is required")
	}
	artifacts, err := RenderWindowsWingetArtifacts(opts)
	if err != nil {
		return artifacts, err
	}
	if err := os.MkdirAll(outputDir, 0o755); err != nil {
		return artifacts, err
	}
	files := []struct {
		path string
		body string
	}{
		{filepath.Join(outputDir, artifacts.VersionManifestFile), artifacts.VersionManifest},
		{filepath.Join(outputDir, artifacts.InstallerManifestFile), artifacts.InstallerManifest},
		{filepath.Join(outputDir, artifacts.LocaleManifestFile), artifacts.LocaleManifest},
	}
	for _, file := range files {
		if err := WriteFileAtomic(file.path, []byte(file.body), 0o644); err != nil {
			return artifacts, err
		}
	}
	artifacts.VersionManifestFile = files[0].path
	artifacts.InstallerManifestFile = files[1].path
	artifacts.LocaleManifestFile = files[2].path
	return artifacts, nil
}

func normalizeWindowsWingetOptions(opts WindowsWingetOptions) (WindowsWingetOptions, error) {
	defaults := DefaultWindowsWingetOptions()
	if strings.TrimSpace(opts.PackageIdentifier) == "" {
		opts.PackageIdentifier = defaults.PackageIdentifier
	}
	if strings.TrimSpace(opts.PackageName) == "" {
		opts.PackageName = defaults.PackageName
	}
	if strings.TrimSpace(opts.Publisher) == "" {
		opts.Publisher = defaults.Publisher
	}
	if strings.TrimSpace(opts.Version) == "" {
		opts.Version = defaults.Version
	}
	if strings.TrimSpace(opts.Homepage) == "" {
		opts.Homepage = defaults.Homepage
	}
	if strings.TrimSpace(opts.License) == "" {
		opts.License = defaults.License
	}
	if strings.TrimSpace(opts.Description) == "" {
		opts.Description = defaults.Description
	}
	if strings.TrimSpace(opts.ShortDescription) == "" {
		opts.ShortDescription = defaults.ShortDescription
	}
	if strings.TrimSpace(opts.ManifestVersion) == "" {
		opts.ManifestVersion = defaults.ManifestVersion
	}
	if strings.TrimSpace(opts.Architecture) == "" {
		opts.Architecture = defaults.Architecture
	}
	if strings.TrimSpace(opts.UpgradeCode) == "" {
		opts.UpgradeCode = defaults.UpgradeCode
	}
	if strings.TrimSpace(opts.InstallerSHA256) == "" && strings.TrimSpace(opts.InstallerFile) != "" {
		hash, err := fileSHA256(opts.InstallerFile)
		if err != nil {
			return opts, err
		}
		opts.InstallerSHA256 = hash
	}
	opts.InstallerSHA256 = strings.ToUpper(strings.TrimSpace(opts.InstallerSHA256))
	return opts, nil
}

func validateWindowsWingetOptions(opts WindowsWingetOptions) error {
	for name, value := range map[string]string{
		"package identifier": opts.PackageIdentifier,
		"package name":       opts.PackageName,
		"publisher":          opts.Publisher,
		"version":            opts.Version,
		"installer URL":      opts.InstallerURL,
		"installer SHA256":   opts.InstallerSHA256,
		"homepage":           opts.Homepage,
		"license":            opts.License,
		"description":        opts.Description,
		"short description":  opts.ShortDescription,
		"manifest version":   opts.ManifestVersion,
		"architecture":       opts.Architecture,
		"upgrade code":       opts.UpgradeCode,
	} {
		if strings.TrimSpace(value) == "" {
			return fmt.Errorf("%s is required", name)
		}
		if strings.ContainsAny(value, "\r\n") {
			return fmt.Errorf("%s must not contain newlines", name)
		}
	}
	if strings.ContainsAny(opts.ReleaseDate, "\r\n") {
		return errors.New("release date must not contain newlines")
	}
	if !wingetPackageIdentifierPattern.MatchString(opts.PackageIdentifier) {
		return errors.New("package identifier must be a dotted winget identifier")
	}
	if !wingetVersionPattern.MatchString(opts.Version) {
		return errors.New("version must be winget-safe")
	}
	if !strings.HasPrefix(strings.ToLower(opts.InstallerURL), "https://") {
		return errors.New("installer URL must be an HTTPS URL")
	}
	if !wingetSHA256Pattern.MatchString(opts.InstallerSHA256) {
		return errors.New("installer SHA256 must be 64 hexadecimal characters")
	}
	return nil
}

func renderWindowsWingetVersionManifest(opts WindowsWingetOptions) string {
	return strings.Join([]string{
		"PackageIdentifier: " + yamlScalar(opts.PackageIdentifier),
		"PackageVersion: " + yamlScalar(opts.Version),
		"DefaultLocale: en-US",
		"ManifestType: version",
		"ManifestVersion: " + yamlScalar(opts.ManifestVersion),
		"",
	}, "\n")
}

func renderWindowsWingetInstallerManifest(opts WindowsWingetOptions) string {
	lines := []string{
		"PackageIdentifier: " + yamlScalar(opts.PackageIdentifier),
		"PackageVersion: " + yamlScalar(opts.Version),
		"InstallerType: wix",
		"Scope: machine",
		"UpgradeBehavior: install",
		"Commands:",
		"- endlessnet-client",
		"- endlessnet-tray",
		"Protocols:",
		"- endlessnet",
		"Installers:",
		"- Architecture: " + yamlScalar(opts.Architecture),
		"  InstallerUrl: " + yamlScalar(opts.InstallerURL),
		"  InstallerSha256: " + yamlScalar(opts.InstallerSHA256),
		"  AppsAndFeaturesEntries:",
		"  - DisplayName: " + yamlScalar(opts.PackageName),
		"    Publisher: " + yamlScalar(opts.Publisher),
		"    InstallerType: wix",
		"    UpgradeCode: " + yamlScalar("{"+strings.Trim(opts.UpgradeCode, "{}")+"}"),
	}
	if strings.TrimSpace(opts.ReleaseDate) != "" {
		lines = append(lines, "  ReleaseDate: "+yamlScalar(opts.ReleaseDate))
	}
	lines = append(lines,
		"ManifestType: installer",
		"ManifestVersion: "+yamlScalar(opts.ManifestVersion),
		"",
	)
	return strings.Join(lines, "\n")
}

func renderWindowsWingetLocaleManifest(opts WindowsWingetOptions) string {
	return strings.Join([]string{
		"PackageIdentifier: " + yamlScalar(opts.PackageIdentifier),
		"PackageVersion: " + yamlScalar(opts.Version),
		"PackageLocale: en-US",
		"Publisher: " + yamlScalar(opts.Publisher),
		"PackageName: " + yamlScalar(opts.PackageName),
		"License: " + yamlScalar(opts.License),
		"ShortDescription: " + yamlScalar(opts.ShortDescription),
		"Description: " + yamlScalar(opts.Description),
		"PackageUrl: " + yamlScalar(opts.Homepage),
		"Tags:",
		"- vpn",
		"- wireguard",
		"- private-network",
		"ManifestType: defaultLocale",
		"ManifestVersion: " + yamlScalar(opts.ManifestVersion),
		"",
	}, "\n")
}

func yamlScalar(value string) string {
	return "'" + strings.ReplaceAll(strings.TrimSpace(value), "'", "''") + "'"
}

func fileSHA256(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}
	return strings.ToUpper(hex.EncodeToString(hash.Sum(nil))), nil
}
