//go:build e2e && windows

package e2e

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"golang.org/x/sys/windows/svc/mgr"
)

func TestWindowsClientMSIInstallUpgradeUninstall(t *testing.T) {
	if os.Getenv("ENDLESSNET_E2E_WINDOWS_MSI") != "1" {
		t.Skip("set ENDLESSNET_E2E_WINDOWS_MSI=1 on an admin Windows runner with WiX v4 to run MSI lifecycle tests")
	}
	requireWindowsAdmin(t)
	if _, err := exec.LookPath("wix.exe"); err != nil {
		t.Skip("WiX Toolset v4 wix.exe is not installed")
	}
	if windowsServiceExists("endlessnet-client") && os.Getenv("ENDLESSNET_E2E_WINDOWS_ALLOW_EXISTING") != "1" {
		t.Fatal("endlessnet-client service already exists; refusing to mutate an existing installation without ENDLESSNET_E2E_WINDOWS_ALLOW_EXISTING=1")
	}

	root := repoRoot(t)
	tmp := t.TempDir()
	clientExe := buildBinary(t, root, tmp, "endlessnet-client", "./cmd/endlessnet-client")
	trayExe := clientExe

	msiV1 := buildWindowsClientMSI(t, root, clientExe, trayExe, filepath.Join(tmp, "msi-v1"), "1.2.3")
	msiV2 := buildWindowsClientMSI(t, root, clientExe, trayExe, filepath.Join(tmp, "msi-v2"), "1.2.4")

	installMSI(t, msiV1)
	t.Cleanup(func() {
		_ = exec.Command("msiexec.exe", "/x", msiV2, "/qn", "/norestart").Run()
		_ = exec.Command("msiexec.exe", "/x", msiV1, "/qn", "/norestart").Run()
	})
	assertWindowsServiceAuto(t, "endlessnet-client")
	assertWindowsServiceFailurePolicy(t, "endlessnet-client")
	assertWindowsPathExists(t, filepath.Join(os.Getenv("ProgramFiles"), "EndlessNet", "endlessnet-client.exe"))
	assertWindowsPathExists(t, filepath.Join(os.Getenv("ProgramFiles"), "EndlessNet", "endlessnet-tray.exe"))
	assertWindowsTrayAutostart(t)
	assertWindowsStartMenuShortcut(t)
	assertWindowsDeepLinkProtocol(t)

	stateRoot := filepath.Join(os.Getenv("ProgramData"), "EndlessNet")
	assertWindowsPathExists(t, stateRoot)
	assertWindowsProgramDataACL(t, stateRoot)
	sentinel := filepath.Join(stateRoot, "client.json")
	if err := os.WriteFile(sentinel, []byte(`{"node_id":"node_msi_e2e"}`), 0o600); err != nil {
		t.Fatal(err)
	}

	installMSI(t, msiV2)
	assertWindowsServiceAuto(t, "endlessnet-client")
	assertWindowsServiceFailurePolicy(t, "endlessnet-client")
	assertWindowsTrayAutostart(t)
	assertWindowsStartMenuShortcut(t)
	assertWindowsDeepLinkProtocol(t)
	assertWindowsProgramDataACL(t, stateRoot)
	if raw, err := os.ReadFile(sentinel); err != nil || !strings.Contains(string(raw), "node_msi_e2e") {
		t.Fatalf("MSI upgrade did not preserve client state: raw=%q err=%v", raw, err)
	}

	// Browsers rename duplicate downloads. Re-running the already installed
	// package from that renamed path must stay a successful no-op maintenance
	// operation and must not invoke deferred tray shutdown/source repair.
	renameDir := filepath.Join(tmp, "renamed-rerun")
	if err := os.MkdirAll(renameDir, 0o755); err != nil {
		t.Fatal(err)
	}
	renamedMSI := filepath.Join(renameDir, "EndlessNet.Client (1).msi")
	copyWindowsMSIFixture(t, msiV2, renamedMSI)
	installMSI(t, renamedMSI)
	assertWindowsServiceAuto(t, "endlessnet-client")
	if raw, err := os.ReadFile(sentinel); err != nil || !strings.Contains(string(raw), "node_msi_e2e") {
		t.Fatalf("renamed MSI maintenance did not preserve client state: raw=%q err=%v", raw, err)
	}
	repairMSI(t, msiV2)
	assertWindowsServiceAuto(t, "endlessnet-client")
	if raw, err := os.ReadFile(sentinel); err != nil || !strings.Contains(string(raw), "node_msi_e2e") {
		t.Fatalf("forced MSI repair did not preserve client state: raw=%q err=%v", raw, err)
	}

	uninstallMSI(t, msiV2)
	if windowsServiceExists("endlessnet-client") {
		t.Fatal("endlessnet-client service still exists after MSI uninstall")
	}
	assertWindowsPathMissing(t, filepath.Join(os.Getenv("ProgramFiles"), "EndlessNet", "endlessnet-client.exe"))
	assertWindowsPathMissing(t, filepath.Join(os.Getenv("ProgramFiles"), "EndlessNet", "endlessnet-tray.exe"))
	assertWindowsStartMenuShortcutRemoved(t)
	assertWindowsDeepLinkProtocolRemoved(t)
	if _, err := os.Stat(sentinel); err != nil {
		t.Fatalf("default MSI uninstall removed preserved state %s: %v", sentinel, err)
	}

	installMSI(t, msiV2)
	if err := os.WriteFile(sentinel, []byte(`{"node_id":"node_remove_state_e2e"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	uninstallMSIRemoveState(t, msiV2)
	if windowsServiceExists("endlessnet-client") {
		t.Fatal("endlessnet-client service still exists after remove-state MSI uninstall")
	}
	assertWindowsPathMissing(t, filepath.Join(os.Getenv("ProgramFiles"), "EndlessNet", "endlessnet-client.exe"))
	assertWindowsPathMissing(t, filepath.Join(os.Getenv("ProgramFiles"), "EndlessNet", "endlessnet-tray.exe"))
	assertWindowsStartMenuShortcutRemoved(t)
	assertWindowsPathMissing(t, stateRoot)
}

func buildWindowsClientMSI(t *testing.T, root, clientExe, trayExe, outputDir, version string) string {
	t.Helper()
	if err := os.MkdirAll(outputDir, 0o755); err != nil {
		t.Fatal(err)
	}
	msi := filepath.Join(outputDir, "EndlessNet.Client."+version+".msi")
	trayBundleDir := prepareWindowsTrayBundleFixture(t, outputDir)
	render := exec.Command(clientExe,
		"installer", "render-windows-msi",
		"--output-dir", outputDir,
		"--version", version,
		"--client-exe", clientExe,
		"--tray-exe", trayExe,
		"--tray-bundle-dir", trayBundleDir,
		"--icon-file", filepath.Join(root, "assets", "endlessnet", "tray.ico"),
		"--msi", msi,
	)
	render.Dir = root
	if out, err := render.CombinedOutput(); err != nil {
		t.Fatalf("render Windows MSI %s: %v\n%s", version, err, out)
	}
	build := exec.Command("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", filepath.Join(outputDir, "build-msi.ps1"))
	build.Dir = outputDir
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build Windows MSI %s: %v\n%s", version, err, out)
	}
	return msi
}

func prepareWindowsTrayBundleFixture(t *testing.T, parent string) string {
	t.Helper()
	bundle := filepath.Join(parent, "tray-bundle")
	for _, path := range []string{
		filepath.Join(bundle, "flutter_windows.dll"),
		filepath.Join(bundle, "tray_manager_plugin.dll"),
		filepath.Join(bundle, "native_assets.json"),
		filepath.Join(bundle, "data", "icudtl.dat"),
		filepath.Join(bundle, "data", "app.so"),
		filepath.Join(bundle, "data", "flutter_assets", "AssetManifest.json"),
	} {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("fixture"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return bundle
}

func copyWindowsMSIFixture(t *testing.T, source, destination string) {
	t.Helper()
	raw, err := os.ReadFile(source)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(destination, raw, 0o600); err != nil {
		t.Fatal(err)
	}
}

func installMSI(t *testing.T, msi string) {
	t.Helper()
	runMSI(t, "install", msi, "/i", msi, "/qn", "/norestart")
}

func repairMSI(t *testing.T, msi string) {
	t.Helper()
	runMSI(t, "repair", msi, "/i", msi, "/qn", "/norestart", "REINSTALL=ALL", "REINSTALLMODE=vomus")
}

func uninstallMSI(t *testing.T, msi string) {
	t.Helper()
	runMSI(t, "uninstall", msi, "/x", msi, "/qn", "/norestart")
}

func uninstallMSIRemoveState(t *testing.T, msi string) {
	t.Helper()
	runMSI(t, "uninstall-remove-state", msi, "/x", msi, "/qn", "/norestart", "ENDLESSNET_REMOVE_STATE=1")
}

func runMSI(t *testing.T, label, msi string, args ...string) {
	t.Helper()
	logPath := filepath.Join(filepath.Dir(msi), label+"-"+strings.TrimSuffix(filepath.Base(msi), filepath.Ext(msi))+".log")
	args = append(args, "/l*v", logPath)
	out, err := exec.Command("msiexec.exe", args...).CombinedOutput()
	if err != nil {
		logRaw, readErr := os.ReadFile(logPath)
		if readErr != nil {
			t.Fatalf("%s MSI %s: %v\n%s\nread MSI log %s: %v", label, msi, err, out, logPath, readErr)
		}
		t.Fatalf("%s MSI %s: %v\n%s\nMSI log %s:\n%s", label, msi, err, out, logPath, logRaw)
	}
}

func requireWindowsAdmin(t *testing.T) {
	t.Helper()
	if out, err := exec.Command("net.exe", "session").CombinedOutput(); err != nil {
		t.Skipf("Windows admin privileges are required: %v\n%s", err, out)
	}
}

func windowsServiceExists(name string) bool {
	return exec.Command("sc.exe", "query", name).Run() == nil
}

func assertWindowsServiceAuto(t *testing.T, name string) {
	t.Helper()
	out, err := exec.Command("powershell.exe", "-NoProfile", "-Command", "(Get-CimInstance Win32_Service -Filter \"Name='"+name+"'\").StartMode").CombinedOutput()
	if err != nil {
		t.Fatalf("query service %s: %v\n%s", name, err, out)
	}
	if !strings.Contains(strings.ToLower(string(out)), "auto") {
		t.Fatalf("service %s start mode = %q, want Auto", name, out)
	}
}

func assertWindowsServiceFailurePolicy(t *testing.T, name string) {
	t.Helper()
	manager, err := mgr.Connect()
	if err != nil {
		t.Fatalf("connect service manager: %v", err)
	}
	defer manager.Disconnect()
	service, err := manager.OpenService(name)
	if err != nil {
		t.Fatalf("open service %s: %v", name, err)
	}
	defer service.Close()
	actions, err := service.RecoveryActions()
	if err != nil {
		t.Fatalf("query service failure policy %s: %v", name, err)
	}
	if len(actions) < 2 {
		t.Fatalf("service %s failure policy actions = %#v, want at least two restart actions", name, actions)
	}
	for i := 0; i < 2; i++ {
		if actions[i].Type != mgr.ServiceRestart || actions[i].Delay != 5*time.Second {
			t.Fatalf("service %s failure action %d = %#v, want restart after 5s; all actions=%#v", name, i, actions[i], actions)
		}
	}
}

func assertWindowsPathExists(t *testing.T, path string) {
	t.Helper()
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("expected path %s to exist: %v", path, err)
	}
}

func assertWindowsPathMissing(t *testing.T, path string) {
	t.Helper()
	if _, err := os.Stat(path); err == nil {
		t.Fatalf("expected path %s to be removed", path)
	} else if !os.IsNotExist(err) {
		t.Fatalf("stat %s: %v", path, err)
	}
}

func assertWindowsTrayAutostart(t *testing.T) {
	t.Helper()
	out, err := exec.Command("powershell.exe", "-NoProfile", "-Command", `(Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'EndlessNet Tray').'EndlessNet Tray'`).CombinedOutput()
	if err != nil {
		t.Fatalf("query tray autostart: %v\n%s", err, out)
	}
	want := filepath.Join(os.Getenv("ProgramFiles"), "EndlessNet", "endlessnet-tray.exe")
	if !strings.Contains(strings.ToLower(string(out)), strings.ToLower(want)) {
		t.Fatalf("tray autostart = %q, want %s", out, want)
	}
}

func assertWindowsStartMenuShortcut(t *testing.T) {
	t.Helper()
	for _, path := range windowsStartMenuShortcutPaths() {
		if _, err := os.Stat(path); err == nil {
			return
		}
	}
	t.Fatalf("EndlessNet Start Menu shortcut is missing; checked %s", strings.Join(windowsStartMenuShortcutPaths(), ", "))
}

func assertWindowsStartMenuShortcutRemoved(t *testing.T) {
	t.Helper()
	for _, path := range windowsStartMenuShortcutPaths() {
		if _, err := os.Stat(path); err == nil {
			t.Fatalf("EndlessNet Start Menu shortcut still exists: %s", path)
		} else if !os.IsNotExist(err) {
			t.Fatalf("stat Start Menu shortcut %s: %v", path, err)
		}
	}
}

func windowsStartMenuShortcutPaths() []string {
	paths := make([]string, 0, 2)
	if programData := os.Getenv("ProgramData"); programData != "" {
		paths = append(paths, filepath.Join(programData, "Microsoft", "Windows", "Start Menu", "Programs", "EndlessNet", "EndlessNet.lnk"))
	}
	if appData := os.Getenv("APPDATA"); appData != "" {
		paths = append(paths, filepath.Join(appData, "Microsoft", "Windows", "Start Menu", "Programs", "EndlessNet", "EndlessNet.lnk"))
	}
	return paths
}

func assertWindowsDeepLinkProtocol(t *testing.T) {
	t.Helper()
	script := `
$key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('Software\Classes\endlessnet')
if ($null -eq $key) {
  Write-Error 'endlessnet protocol key is missing'
  exit 1
}
$commandKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('Software\Classes\endlessnet\shell\open\command')
if ($null -eq $commandKey) {
  Write-Error 'endlessnet protocol command is missing'
  exit 1
}
$protocolName = [string]$key.GetValue('')
$urlProtocol = [string]$key.GetValue('URL Protocol')
$command = [string]$commandKey.GetValue('')
if ($protocolName -ne 'URL:EndlessNet Enrollment') {
  Write-Error "protocol name = $protocolName"
  exit 1
}
if ($urlProtocol -ne '') {
  Write-Error "URL Protocol marker = $urlProtocol"
  exit 1
}
if ($command -notmatch 'endlessnet-tray\.exe' -or $command -notmatch '--enroll' -or $command -notmatch '%1') {
  Write-Error "protocol command = $command"
  exit 1
}
`
	out, err := exec.Command("powershell.exe", "-NoProfile", "-Command", script).CombinedOutput()
	if err != nil {
		t.Fatalf("query EndlessNet deep link protocol: %v\n%s", err, out)
	}
}

func assertWindowsDeepLinkProtocolRemoved(t *testing.T) {
	t.Helper()
	script := `
if ([Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('Software\Classes\endlessnet')) {
  Write-Error 'endlessnet protocol key still exists'
  exit 1
}
`
	out, err := exec.Command("powershell.exe", "-NoProfile", "-Command", script).CombinedOutput()
	if err != nil {
		t.Fatalf("EndlessNet deep link protocol still exists after uninstall: %v\n%s", err, out)
	}
}

func assertWindowsProgramDataACL(t *testing.T, path string) {
	t.Helper()
	script := `
$targetPath = $env:ENDLESSNET_E2E_ACL_PATH
if ([string]::IsNullOrWhiteSpace($targetPath)) {
  Write-Error "ENDLESSNET_E2E_ACL_PATH is required"
  exit 1
}
$acl = Get-Acl -LiteralPath $targetPath
if (-not $acl.AreAccessRulesProtected) {
  Write-Error "inheritance is enabled"
  exit 1
}
$writeRights = [System.Security.AccessControl.FileSystemRights]::Write -bor
  [System.Security.AccessControl.FileSystemRights]::Modify -bor
  [System.Security.AccessControl.FileSystemRights]::FullControl -bor
  [System.Security.AccessControl.FileSystemRights]::CreateFiles -bor
  [System.Security.AccessControl.FileSystemRights]::CreateDirectories -bor
  [System.Security.AccessControl.FileSystemRights]::WriteData
$bad = @($acl.Access | Where-Object {
  $_.AccessControlType -eq 'Allow' -and
  (($_.IdentityReference.Value -match '(^|\\)(Users|Everyone|Authenticated Users)$') -or ($_.IdentityReference.Value -match '^Everyone$')) -and
  (($_.FileSystemRights -band $writeRights) -ne 0)
})
if ($bad.Count -gt 0) {
  $bad | Format-List | Out-String | Write-Error
  exit 1
}
`
	cmd := exec.Command("powershell.exe", "-NoProfile", "-Command", script)
	cmd.Env = append(os.Environ(), "ENDLESSNET_E2E_ACL_PATH="+path)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("ProgramData ACL allows broad writes or inherited access: %v\n%s", err, out)
	}
}
