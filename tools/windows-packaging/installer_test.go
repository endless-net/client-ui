package packaging

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
		`AllowSameVersionUpgrades="yes"`,
		`<util:ExitEarlyWithSuccess />`,
		`SetProperty Id="NEWERVERSIONDETECTED" Value="1" Before="FindRelatedProducts" Sequence="execute"`,
		`Condition="Installed AND NOT REMOVE~=&quot;ALL&quot; AND NOT REINSTALL"`,
		`Property Id="ENDLESSNET_REMOVE_STATE" Secure="yes"`,
		`Property Id="ENDLESSNET_REMOVE_STATE_ROOT" Secure="yes" Value="C:\ProgramData\EndlessNet"`,
		`Name="endlessnet-client.exe"`,
		`Name="wintun.dll"`,
		`Source="$(var.WintunDll)"`,
		`Name="wintun-LICENSE.txt"`,
		`Source="$(var.WintunLicense)"`,
		`Name="endlessnet.exe"`,
		`Name="endlessnet.ico"`,
		`UI Id="EndlessNetInstallerUI"`,
		`DialogRef Id="WelcomeDlg"`,
		`DialogRef Id="VerifyReadyDlg"`,
		`DialogRef Id="ExitDialog"`,
		`UIRef Id="WixUI_Common"`,
		`WIXUI_EXITDIALOGOPTIONALCHECKBOX`,
		`WIXUI_EXITDIALOGOPTIONALCHECKBOXTEXT" Value="Launch EndlessNet now"`,
		`CustomAction Id="LaunchEndlessNetApp"`,
		`FileRef="AppExeFile"`,
		`ExeCommand="--show-window --debug --debug-log-dir ~\.endlessnet\logs"`,
		`--debug`,
		`--debug-log-dir ~\.endlessnet\logs`,
		`Publish Dialog="ExitDialog" Control="Finish" Event="DoAction"`,
		`Publish Dialog="ExitDialog" Control="Finish" Event="EndDialog" Value="Return"`,
		`util:CloseApplication Id="CloseEndlessNetApp"`,
		`Condition="NOT Installed OR REMOVE~=&quot;ALL&quot; OR REINSTALL"`,
		`Target="endlessnet.exe"`,
		`TerminateProcess="1"`,
		`CustomAction Id="KillEndlessNetApp"`,
		`Directory="SystemFolder"`,
		`taskkill.exe`,
		`/IM endlessnet.exe`,
		`Custom Action="KillEndlessNetApp" Before="InstallValidate"`,
		`StandardDirectory Id="SystemFolder"`,
		`Directory Id="ApplicationProgramsFolder" Name="EndlessNet"`,
		`Shortcut Id="EndlessNetShortcut"`,
		`Arguments="--show-window --debug --debug-log-dir ~\.endlessnet\logs"`,
		`Icon="EndlessNetIcon"`,
		`RemoveFolder Id="RemoveEndlessNetProgramMenuFolder"`,
		`Component Id="ClientExecutable" Guid="*" Bitness="always64"`,
		`Component Id="AppExecutable" Guid="*" Bitness="always64"`,
		`Component Id="AppIcon" Guid="*" Bitness="always64"`,
		`Directory Id="EndlessNetAppDataFolder" Name="data"`,
		`ComponentGroup Id="EndlessNetAppBundleFiles" Directory="INSTALLFOLDER"`,
		`<Files Include="$(var.AppBundleDir)\*.dll" />`,
		`<Files Include="$(var.AppBundleDir)\native_assets.json" />`,
		`ComponentGroup Id="EndlessNetAppDataFiles" Directory="EndlessNetAppDataFolder"`,
		`<Files Include="$(var.AppBundleDir)\data\**" />`,
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
		`--debug-log-dir`,
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
		`Component Id="ResetStateBeforeInstall"`,
		`Condition="ENDLESSNET_REMOVE_STATE=&quot;1&quot;"`,
		`RemoveFile Id="RemoveClientStateBeforeInstall" Name="client.json" On="install"`,
		`RemoveFile Id="RemoveAgentStateBeforeInstall" Name="agent-state.json" On="install"`,
		`RemoveFile Id="RemoveAgentLockBeforeInstall" Name="client.json.agent.lock" On="install"`,
		`Condition="ENDLESSNET_REMOVE_STATE=&quot;1&quot;"`,
		`<PermissionEx Sddl="D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)" />`,
	} {
		if !strings.Contains(artifacts.WixSource, want) {
			t.Fatalf("WiX source missing %q:\n%s", want, artifacts.WixSource)
		}
	}
	if got := strings.Count(artifacts.WixSource, `Condition="NOT Installed OR REMOVE~=&quot;ALL&quot; OR REINSTALL"`); got != 2 {
		t.Fatalf("app shutdown lifecycle condition count = %d, want 2:\n%s", got, artifacts.WixSource)
	}
	if got := strings.Count(artifacts.WixSource, `Condition="ENDLESSNET_REMOVE_STATE=&quot;1&quot;"`); got != 2 {
		t.Fatalf("state removal condition count = %d, want 2:\n%s", got, artifacts.WixSource)
	}
	for _, forbidden := range []string{
		`WixUI_Minimal`,
		`LicenseAgreementDlg`,
		`WixUILicenseRtf`,
		`Lorem ipsum`,
		`WixShellExecTarget`,
		`endlessnet-tray`,
		`EndlessNetTray`,
		`TrayExe`,
		`TrayBundleDir`,
		`--output`,
		`endlessnet.conf`,
		`--userspace-wireguard`,
		`--apply-wireguard`,
		`--apply-wg-quick`,
		`--wireguard-windows`,
		`Directory Id="AppDataFolder"`,
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
		"WintunDll",
		"WintunLicense",
		"AppExe",
		"AppBundleDir",
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
