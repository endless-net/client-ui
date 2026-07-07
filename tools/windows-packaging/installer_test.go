package client

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestRenderWindowsInstallerArtifacts(t *testing.T) {
	opts := DefaultWindowsInstallerOptions()
	opts.Version = "1.2.3"
	artifacts, err := RenderWindowsInstallerArtifacts(opts)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		`<Package Name="EndlessNet Client"`,
		`xmlns:util="http://wixtoolset.org/schemas/v4/wxs/util"`,
		`Version="1.2.3"`,
		`UpgradeCode="{9f7a7362-64c3-4b3a-9a58-7c8fc90779e1}"`,
		`<MajorUpgrade`,
		`Property Id="ENDLESSNET_REMOVE_STATE" Secure="yes"`,
		`Property Id="ENDLESSNET_REMOVE_STATE_ROOT" Secure="yes" Value="C:\ProgramData\EndlessNet"`,
		`Name="endlessnet-client.exe"`,
		`Name="endlessnet-tray.exe"`,
		`Name="endlessnet.ico"`,
		`UI Id="EndlessNetInstallerUI"`,
		`DialogRef Id="WelcomeDlg"`,
		`DialogRef Id="VerifyReadyDlg"`,
		`DialogRef Id="ExitDialog"`,
		`UIRef Id="WixUI_Common"`,
		`WIXUI_EXITDIALOGOPTIONALCHECKBOX`,
		`WIXUI_EXITDIALOGOPTIONALCHECKBOXTEXT" Value="Launch EndlessNet now"`,
		`CustomAction Id="LaunchEndlessNetTray"`,
		`FileRef="TrayExeFile"`,
		`ExeCommand="--show-window"`,
		`Publish Dialog="ExitDialog" Control="Finish"`,
		`Directory Id="ApplicationProgramsFolder" Name="EndlessNet"`,
		`Shortcut Id="EndlessNetTrayShortcut"`,
		`Arguments="--show-window"`,
		`Icon="EndlessNetTrayIcon"`,
		`RemoveFolder Id="RemoveEndlessNetProgramMenuFolder"`,
		`Component Id="ClientExecutable" Guid="*" Bitness="always64"`,
		`Component Id="TrayExecutable" Guid="*" Bitness="always64"`,
		`Component Id="TrayIcon" Guid="*" Bitness="always64"`,
		`Component Id="DeepLinkProtocol" Guid="*" Bitness="always64"`,
		`Software\Microsoft\Windows\CurrentVersion\Run`,
		`Component Id="DeepLinkProtocol"`,
		`Software\Classes\endlessnet`,
		`URL:EndlessNet Enrollment`,
		`Name="URL Protocol"`,
		`--enroll &quot;%1&quot;`,
		`<ServiceInstall`,
		`Name="endlessnet-client"`,
		`--windows-service`,
		`--ipc-pipe`,
		`--diagnostics-dir`,
		`--event-log-source`,
		`--apply-wireguard`,
		`<util:ServiceConfig`,
		`FirstFailureActionType="restart"`,
		`SecondFailureActionType="restart"`,
		`ThirdFailureActionType="none"`,
		`RestartServiceDelayInSeconds="5"`,
		`ResetPeriodInDays="1"`,
		`<ServiceControl`,
		`Start="install"`,
		`<Component Id="EventLogSource"`,
		`SYSTEM\CurrentControlSet\Services\EventLog\Application\EndlessNet Client`,
		`EventMessageFile`,
		`TypesSupported`,
		`Component Id="RemoveStateOnUninstall"`,
		`util:RemoveFolderEx Id="RemoveEndlessNetStateRoot"`,
		`On="uninstall"`,
		`Condition="ENDLESSNET_REMOVE_STATE=&quot;1&quot;"`,
		`<PermissionEx Sddl="D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)" />`,
	} {
		if !strings.Contains(artifacts.WixSource, want) {
			t.Fatalf("WiX source missing %q:\n%s", want, artifacts.WixSource)
		}
	}
	for _, forbidden := range []string{
		`WixUI_Minimal`,
		`LicenseAgreementDlg`,
		`WixUILicenseRtf`,
		`Lorem ipsum`,
		`WixShellExecTarget`,
	} {
		if strings.Contains(artifacts.WixSource, forbidden) {
			t.Fatalf("WiX source contains forbidden placeholder/license marker %q:\n%s", forbidden, artifacts.WixSource)
		}
	}
	for _, want := range []string{
		"WiX Toolset wix.exe is required",
		"wix.exe",
		`"-arch", "x64"`,
		"WixToolset.Util.wixext",
		"WixToolset.UI.wixext",
		"ClientExe",
		"TrayExe",
		"IconFile",
		"ENDLESSNET_CODESIGN_THUMBPRINT",
		"SignTool",
	} {
		if !strings.Contains(artifacts.BuildScript, want) {
			t.Fatalf("build script missing %q:\n%s", want, artifacts.BuildScript)
		}
	}
	for _, leak := range []string{"enr_fixture_secret", "session-token", "private-key-value", "node-credential-value"} {
		if strings.Contains(artifacts.WixSource, leak) || strings.Contains(artifacts.BuildScript, leak) {
			t.Fatalf("installer artifacts leaked %q", leak)
		}
	}
}

func TestWriteWindowsInstallerArtifacts(t *testing.T) {
	outputDir := t.TempDir()
	artifacts, err := WriteWindowsInstallerArtifacts(outputDir, DefaultWindowsInstallerOptions())
	if err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{artifacts.WixSourceFile, artifacts.BuildFile} {
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
}

func TestRenderWindowsInstallerArtifactsUsesConfiguredStateRoot(t *testing.T) {
	opts := DefaultWindowsInstallerOptions()
	opts.ServiceOptions.ConfigPath = `D:\EndlessNetState\client.json`
	artifacts, err := RenderWindowsInstallerArtifacts(opts)
	if err != nil {
		t.Fatal(err)
	}
	want := `Property Id="ENDLESSNET_REMOVE_STATE_ROOT" Secure="yes" Value="D:\EndlessNetState"`
	if !strings.Contains(artifacts.WixSource, want) {
		t.Fatalf("WiX source missing configured state root %q:\n%s", want, artifacts.WixSource)
	}
}
