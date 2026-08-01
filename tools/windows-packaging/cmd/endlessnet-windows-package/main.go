package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"

	packaging "github.com/endless-net/client-ui/tools/windows-packaging"
)

func main() {
	if len(os.Args) < 2 {
		fail("command requires render-msi or render-winget")
	}
	var err error
	switch os.Args[1] {
	case "render-msi":
		err = renderMSI(os.Args[2:])
	case "render-winget":
		err = renderWinget(os.Args[2:])
	default:
		err = fmt.Errorf("unknown command %q", os.Args[1])
	}
	if err != nil {
		fail(err.Error())
	}
}

func renderMSI(args []string) error {
	defaults := packaging.DefaultWindowsInstallerOptions()
	fs := flag.NewFlagSet("render-msi", flag.ContinueOnError)
	outputDir := fs.String("output-dir", "", "directory for WiX source and build script")
	version := fs.String("version", "", "MSI product version")
	clientExe := fs.String("client-exe", "", "path to the verified Go client executable")
	recoveryHelperExe := fs.String("recovery-helper-exe", "", "path to the verified recovery helper executable")
	wintunDLL := fs.String("wintun-dll", "", "path to the verified official Wintun DLL")
	wintunLicense := fs.String("wintun-license", "", "path to the official Wintun prebuilt-binary license")
	appExe := fs.String("app-exe", "", "path to the Flutter application executable")
	appBundleDir := fs.String("app-bundle-dir", "", "path to the Flutter Windows release bundle")
	iconFile := fs.String("icon-file", defaults.IconFile, "path to the application icon")
	msi := fs.String("msi", "", "final MSI output path")
	resetStateOnInstall := fs.Bool("reset-state-on-install", false, "delete existing client state before starting the installed service")
	if err := fs.Parse(args); err != nil {
		return err
	}
	for name, value := range map[string]string{
		"output-dir":          *outputDir,
		"version":             *version,
		"client-exe":          *clientExe,
		"recovery-helper-exe": *recoveryHelperExe,
		"wintun-dll":          *wintunDLL,
		"wintun-license":      *wintunLicense,
		"app-exe":             *appExe,
		"app-bundle-dir":      *appBundleDir,
		"msi":                 *msi,
	} {
		if strings.TrimSpace(value) == "" {
			return fmt.Errorf("--%s is required", name)
		}
	}
	artifacts, err := packaging.WriteWindowsInstallerArtifacts(*outputDir, packaging.WindowsInstallerOptions{
		ProductName:         defaults.ProductName,
		Manufacturer:        defaults.Manufacturer,
		Version:             *version,
		UpgradeCode:         defaults.UpgradeCode,
		ClientExe:           *clientExe,
		RecoveryHelperExe:   *recoveryHelperExe,
		WintunDLL:           *wintunDLL,
		WintunLicense:       *wintunLicense,
		AppExe:              *appExe,
		AppBundleDir:        *appBundleDir,
		IconFile:            *iconFile,
		OutputName:          *msi,
		ResetStateOnInstall: *resetStateOnInstall,
		ServiceOptions:      packaging.DefaultWindowsServiceOptions(),
	})
	if err != nil {
		return err
	}
	return writeJSON(map[string]string{
		"wix_source_file": artifacts.WixSourceFile,
		"build_file":      artifacts.BuildFile,
	})
}

func renderWinget(args []string) error {
	fs := flag.NewFlagSet("render-winget", flag.ContinueOnError)
	outputDir := fs.String("output-dir", "", "directory for WinGet manifests")
	version := fs.String("version", "", "package version")
	installerFile := fs.String("installer-file", "", "signed MSI used to calculate SHA-256")
	installerURL := fs.String("installer-url", "", "immutable public MSI URL")
	releaseDate := fs.String("release-date", "", "release date in YYYY-MM-DD")
	if err := fs.Parse(args); err != nil {
		return err
	}
	for name, value := range map[string]string{
		"output-dir":     *outputDir,
		"version":        *version,
		"installer-file": *installerFile,
		"installer-url":  *installerURL,
	} {
		if strings.TrimSpace(value) == "" {
			return fmt.Errorf("--%s is required", name)
		}
	}
	opts := packaging.DefaultWindowsWingetOptions()
	opts.Version = *version
	opts.InstallerFile = *installerFile
	opts.InstallerURL = *installerURL
	opts.ReleaseDate = *releaseDate
	artifacts, err := packaging.WriteWindowsWingetArtifacts(*outputDir, opts)
	if err != nil {
		return err
	}
	return writeJSON(map[string]string{
		"version_manifest_file":   artifacts.VersionManifestFile,
		"installer_manifest_file": artifacts.InstallerManifestFile,
		"locale_manifest_file":    artifacts.LocaleManifestFile,
	})
}

func writeJSON(value any) error {
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetEscapeHTML(false)
	return encoder.Encode(value)
}

func fail(message string) {
	fmt.Fprintln(os.Stderr, message)
	os.Exit(1)
}
