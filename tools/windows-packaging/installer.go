package packaging

import (
	"encoding/xml"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type WindowsInstallerOptions struct {
	ProductName         string
	Manufacturer        string
	Version             string
	UpgradeCode         string
	ClientExe           string
	RecoveryHelperExe   string
	WintunDLL           string
	WintunLicense       string
	AppExe              string
	AppBundleDir        string
	IconFile            string
	OutputName          string
	ResetStateOnInstall bool
	ServiceOptions      WindowsServiceOptions
}

type WindowsInstallerArtifacts struct {
	WixSourceFile string `json:"wix_source_file"`
	BuildScript   string `json:"build_script"`
	BuildFile     string `json:"build_file"`
	WixSource     string `json:"wix_source"`
}

func DefaultWindowsInstallerOptions() WindowsInstallerOptions {
	return WindowsInstallerOptions{
		ProductName:       "EndlessNet Client",
		Manufacturer:      "UNNG",
		Version:           "0.0.0",
		UpgradeCode:       "9f7a7362-64c3-4b3a-9a58-7c8fc90779e1",
		ClientExe:         `C:\Program Files\EndlessNet\endlessnet-client.exe`,
		RecoveryHelperExe: `C:\Program Files\EndlessNet\endlessnet-client-recovery-helper.exe`,
		WintunDLL:         `C:\Program Files\EndlessNet\wintun.dll`,
		WintunLicense:     `C:\Program Files\EndlessNet\wintun-LICENSE.txt`,
		AppExe:            `C:\Program Files\EndlessNet\endlessnet.exe`,
		AppBundleDir:      `C:\Program Files\EndlessNet`,
		IconFile:          filepath.Join("app", "assets", "icons", "endlessnet.ico"),
		OutputName:        "EndlessNet.Client.msi",
		ServiceOptions:    DefaultWindowsServiceOptions(),
	}
}

func RenderWindowsInstallerArtifacts(opts WindowsInstallerOptions) (WindowsInstallerArtifacts, error) {
	opts = normalizeWindowsInstallerOptions(opts)
	if err := validateWindowsInstallerOptions(opts); err != nil {
		return WindowsInstallerArtifacts{}, err
	}
	return WindowsInstallerArtifacts{
		WixSourceFile: "EndlessNet.Client.wxs",
		BuildFile:     "build-msi.ps1",
		WixSource:     renderWindowsInstallerWix(opts),
		BuildScript:   renderWindowsInstallerBuildScript(opts),
	}, nil
}

func WriteWindowsInstallerArtifacts(outputDir string, opts WindowsInstallerOptions) (WindowsInstallerArtifacts, error) {
	if strings.TrimSpace(outputDir) == "" {
		return WindowsInstallerArtifacts{}, errors.New("output directory is required")
	}
	artifacts, err := RenderWindowsInstallerArtifacts(opts)
	if err != nil {
		return artifacts, err
	}
	if err := os.MkdirAll(outputDir, 0o755); err != nil {
		return artifacts, err
	}
	wixPath := filepath.Join(outputDir, artifacts.WixSourceFile)
	buildPath := filepath.Join(outputDir, artifacts.BuildFile)
	if err := WriteFileAtomic(wixPath, []byte(artifacts.WixSource), 0o644); err != nil {
		return artifacts, err
	}
	if err := WriteFileAtomic(buildPath, []byte(artifacts.BuildScript), 0o644); err != nil {
		return artifacts, err
	}
	artifacts.WixSourceFile = wixPath
	artifacts.BuildFile = buildPath
	return artifacts, nil
}

func normalizeWindowsInstallerOptions(opts WindowsInstallerOptions) WindowsInstallerOptions {
	defaults := DefaultWindowsInstallerOptions()
	if strings.TrimSpace(opts.ProductName) == "" {
		opts.ProductName = defaults.ProductName
	}
	if strings.TrimSpace(opts.Manufacturer) == "" {
		opts.Manufacturer = defaults.Manufacturer
	}
	if strings.TrimSpace(opts.Version) == "" {
		opts.Version = defaults.Version
	}
	if strings.TrimSpace(opts.UpgradeCode) == "" {
		opts.UpgradeCode = defaults.UpgradeCode
	}
	if strings.TrimSpace(opts.ClientExe) == "" {
		opts.ClientExe = defaults.ClientExe
	}
	if strings.TrimSpace(opts.RecoveryHelperExe) == "" {
		opts.RecoveryHelperExe = defaults.RecoveryHelperExe
	}
	if strings.TrimSpace(opts.WintunDLL) == "" {
		opts.WintunDLL = defaults.WintunDLL
	}
	if strings.TrimSpace(opts.WintunLicense) == "" {
		opts.WintunLicense = defaults.WintunLicense
	}
	if strings.TrimSpace(opts.AppExe) == "" {
		opts.AppExe = defaults.AppExe
	}
	if strings.TrimSpace(opts.AppBundleDir) == "" {
		opts.AppBundleDir = firstNonEmptyInstallerString(windowsParentPath(opts.AppExe), defaults.AppBundleDir)
	}
	if strings.TrimSpace(opts.IconFile) == "" {
		opts.IconFile = defaults.IconFile
	}
	if strings.TrimSpace(opts.OutputName) == "" {
		opts.OutputName = defaults.OutputName
	}
	opts.ServiceOptions = normalizeWindowsServiceOptions(opts.ServiceOptions)
	return opts
}

func validateWindowsInstallerOptions(opts WindowsInstallerOptions) error {
	for name, value := range map[string]string{
		"product name":    opts.ProductName,
		"manufacturer":    opts.Manufacturer,
		"version":         opts.Version,
		"upgrade code":    opts.UpgradeCode,
		"client exe":      opts.ClientExe,
		"recovery helper": opts.RecoveryHelperExe,
		"wintun dll":      opts.WintunDLL,
		"wintun license":  opts.WintunLicense,
		"app exe":         opts.AppExe,
		"app bundle":      opts.AppBundleDir,
		"icon file":       opts.IconFile,
		"output name":     opts.OutputName,
		"service name":    opts.ServiceOptions.ServiceName,
		"display name":    opts.ServiceOptions.DisplayName,
		"config path":     opts.ServiceOptions.ConfigPath,
		"agent state":     opts.ServiceOptions.StatePath,
		"diagnostics":     opts.ServiceOptions.DiagnosticsDir,
		"IPC pipe":        opts.ServiceOptions.IPCPipe,
		"event source":    opts.ServiceOptions.EventLogSource,
	} {
		if strings.TrimSpace(value) == "" {
			return fmt.Errorf("%s is required", name)
		}
		if strings.ContainsAny(value, "\r\n") {
			return fmt.Errorf("%s must not contain newlines", name)
		}
	}
	if !strings.HasSuffix(strings.ToLower(opts.OutputName), ".msi") {
		return errors.New("output name must end with .msi")
	}
	if windowsParentPath(opts.ServiceOptions.ConfigPath) == "" {
		return errors.New("config path must include a parent directory")
	}
	serviceArgs := strings.Join(windowsServiceAgentArgs(opts.ServiceOptions), " ")
	if len(serviceArgs) > 255 {
		return fmt.Errorf("service arguments are %d characters; Windows Installer allows at most 255", len(serviceArgs))
	}
	return nil
}

func renderWindowsInstallerWix(opts WindowsInstallerOptions) string {
	serviceArgs := windowsServiceAgentArgs(opts.ServiceOptions)
	stateRoot := windowsParentPath(opts.ServiceOptions.ConfigPath)
	removeStatePropertyValue := ""
	if opts.ResetStateOnInstall {
		removeStatePropertyValue = ` Value="1"`
	}
	// Windows Installer requires a maintenance source with the registered MSI
	// package name. Browsers commonly rename duplicate downloads, so an ordinary
	// second /i must return success before source validation instead of failing
	// with 1603. Explicit REINSTALL remains a real repair operation.
	const idempotentInstallCondition = `Installed AND NOT REMOVE~=&quot;ALL&quot; AND NOT REINSTALL`
	// Initial installs/major upgrades have no Installed property. Explicit
	// uninstall and forced repair still need the desktop app to be closed.
	const appShutdownCondition = `NOT Installed OR REMOVE~=&quot;ALL&quot; OR REINSTALL`
	return fmt.Sprintf(`<?xml version="1.0" encoding="utf-8"?>
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs" xmlns:util="http://wixtoolset.org/schemas/v4/wxs/util">
  <Package Name="%s" Manufacturer="%s" Version="%s" UpgradeCode="{%s}" Scope="perMachine">
    <SummaryInformation Description="%s installer" Manufacturer="%s" />
    <MajorUpgrade AllowSameVersionUpgrades="yes" DowngradeErrorMessage="A newer version of EndlessNet Client is already installed." />
    <util:ExitEarlyWithSuccess />
    <SetProperty Id="NEWERVERSIONDETECTED" Value="1" Before="FindRelatedProducts" Sequence="execute" Condition="%s" />
    <Property Id="ENDLESSNET_REMOVE_STATE" Secure="yes"%s />
    <Property Id="ENDLESSNET_REMOVE_STATE_ROOT" Secure="yes" Value="%s" />
    <MediaTemplate EmbedCab="yes" />
    <UI Id="EndlessNetInstallerUI">
      <TextStyle Id="WixUI_Font_Normal" FaceName="Tahoma" Size="8" />
      <TextStyle Id="WixUI_Font_Bigger" FaceName="Tahoma" Size="12" />
      <TextStyle Id="WixUI_Font_Title" FaceName="Tahoma" Size="9" Bold="yes" />
      <Property Id="DefaultUIFont" Value="WixUI_Font_Normal" />
      <Property Id="WixUI_Mode" Value="Minimal" />
      <DialogRef Id="ErrorDlg" />
      <DialogRef Id="FatalError" />
      <DialogRef Id="FilesInUse" />
      <DialogRef Id="MsiRMFilesInUse" />
      <DialogRef Id="PrepareDlg" />
      <DialogRef Id="ProgressDlg" />
      <DialogRef Id="ResumeDlg" />
      <DialogRef Id="UserExit" />
      <DialogRef Id="WelcomeDlg" />
      <DialogRef Id="VerifyReadyDlg" />
      <DialogRef Id="ExitDialog" />
      <Publish Dialog="WelcomeDlg" Control="Next" Event="NewDialog" Value="VerifyReadyDlg" Condition="NOT Installed" />
      <Publish Dialog="VerifyReadyDlg" Control="Back" Event="NewDialog" Value="WelcomeDlg" Condition="NOT Installed" />
      <Publish Dialog="ExitDialog" Control="Finish" Event="DoAction" Value="LaunchEndlessNetApp" Order="1" Condition="WIXUI_EXITDIALOGOPTIONALCHECKBOX = 1 and NOT Installed" />
      <Publish Dialog="ExitDialog" Control="Finish" Event="EndDialog" Value="Return" Order="2" Condition="1" />
    </UI>
    <UIRef Id="WixUI_Common" />
    <Property Id="WIXUI_EXITDIALOGOPTIONALCHECKBOX" Value="1" />
    <Property Id="WIXUI_EXITDIALOGOPTIONALCHECKBOXTEXT" Value="Launch EndlessNet now" />
    <util:CloseApplication Id="CloseEndlessNetApp" Target="endlessnet.exe" Condition="%s" CloseMessage="yes" ElevatedCloseMessage="yes" TerminateProcess="1" RebootPrompt="no" Timeout="5" />
    <CustomAction Id="KillEndlessNetApp" Directory="SystemFolder" ExeCommand="&quot;[SystemFolder]taskkill.exe&quot; /F /IM endlessnet.exe /T" Execute="immediate" Return="ignore" />
    <InstallExecuteSequence>
      <Custom Action="KillEndlessNetApp" Before="InstallValidate" Condition="%s" />
    </InstallExecuteSequence>
    <CustomAction Id="LaunchEndlessNetApp" FileRef="AppExeFile" ExeCommand="--show-window --debug --debug-log-dir %s" Execute="immediate" Return="asyncNoWait" Impersonate="yes" />
    <Icon Id="EndlessNetIcon" SourceFile="$(var.IconFile)" />
    <Feature Id="ProductFeature" Title="%s" Level="1">
      <ComponentGroupRef Id="EndlessNetClientComponents" />
      <ComponentGroupRef Id="EndlessNetAppBundleFiles" />
      <ComponentGroupRef Id="EndlessNetAppDataFiles" />
      <ComponentGroupRef Id="EndlessNetShortcutComponents" />
    </Feature>
    <StandardDirectory Id="SystemFolder" />
    <StandardDirectory Id="System64Folder" />
    <StandardDirectory Id="ProgramMenuFolder">
      <Directory Id="ApplicationProgramsFolder" Name="EndlessNet" />
    </StandardDirectory>
    <StandardDirectory Id="ProgramFiles64Folder">
      <Directory Id="INSTALLFOLDER" Name="EndlessNet">
		<Directory Id="EndlessNetAppDataFolder" Name="data" />
      </Directory>
    </StandardDirectory>
    <StandardDirectory Id="CommonAppDataFolder">
      <Directory Id="ENDLESSNETPROGRAMDATA" Name="EndlessNet" />
    </StandardDirectory>
    <ComponentGroup Id="EndlessNetClientComponents" Directory="INSTALLFOLDER">
      <Component Id="ClientExecutable" Guid="*" Bitness="always64">
        <File Id="ClientExeFile" Source="$(var.ClientExe)" Name="endlessnet-client.exe" KeyPath="yes" />
        <ServiceInstall Id="EndlessNetServiceInstall" Name="%s" DisplayName="%s" Description="%s" Type="ownProcess" Start="auto" ErrorControl="normal" Account="LocalSystem" Arguments="%s">
          <util:ServiceConfig FirstFailureActionType="restart" SecondFailureActionType="restart" ThirdFailureActionType="none" RestartServiceDelayInSeconds="5" ResetPeriodInDays="1" />
        </ServiceInstall>
        <ServiceControl Id="EndlessNetServiceControl" Name="%s" Start="install" Stop="both" Remove="uninstall" Wait="yes" />
        <RegistryValue Root="HKLM" Key="Software\EndlessNet\Client" Name="Installed" Type="integer" Value="1" />
      </Component>
      <Component Id="RecoveryHelperExecutable" Guid="*" Bitness="always64">
        <File Id="RecoveryHelperExeFile" Source="$(var.RecoveryHelperExe)" Name="endlessnet-client-recovery-helper.exe" KeyPath="yes" />
      </Component>
      <Component Id="WintunLibrary" Guid="*" Bitness="always64">
        <File Id="WintunDllFile" Source="$(var.WintunDll)" Name="wintun.dll" KeyPath="yes" />
        <File Id="WintunLicenseFile" Source="$(var.WintunLicense)" Name="wintun-LICENSE.txt" />
      </Component>
      <Component Id="AppExecutable" Guid="*" Bitness="always64">
        <File Id="AppExeFile" Source="$(var.AppExe)" Name="endlessnet.exe" KeyPath="yes" />
      </Component>
      <Component Id="AppIcon" Guid="*" Bitness="always64">
        <File Id="AppIconFile" Source="$(var.IconFile)" Name="endlessnet.ico" KeyPath="yes" />
      </Component>
      <Component Id="AppAutostart" Guid="*" Bitness="always64">
        <RemoveRegistryValue Id="RemoveLegacyAutostartName" Root="HKCU" Key="Software\Microsoft\Windows\CurrentVersion\Run" Name="EndlessNet Tray" />
        <RegistryValue Root="HKCU" Key="Software\Microsoft\Windows\CurrentVersion\Run" Name="EndlessNet" Value="&quot;[INSTALLFOLDER]endlessnet.exe&quot; --debug --debug-log-dir %s" Type="string" KeyPath="yes" />
      </Component>
      <Component Id="DeepLinkProtocol" Guid="*" Bitness="always64">
        <RegistryKey Root="HKLM" Key="Software\Classes\endlessnet">
          <RegistryValue Value="URL:EndlessNet Enrollment" Type="string" KeyPath="yes" />
          <RegistryValue Name="URL Protocol" Value="" Type="string" />
          <RegistryKey Key="shell\open\command">
            <RegistryValue Value="&quot;[INSTALLFOLDER]endlessnet.exe&quot; --debug --debug-log-dir %s --enroll &quot;%%1&quot;" Type="string" />
          </RegistryKey>
        </RegistryKey>
      </Component>
      <Component Id="EventLogSource" Guid="*" Bitness="always64">
        <RegistryKey Root="HKLM" Key="SYSTEM\CurrentControlSet\Services\EventLog\Application\%s">
          <RegistryValue Name="EventMessageFile" Type="expandable" Value="[System64Folder]EventCreate.exe" KeyPath="yes" />
          <RegistryValue Name="TypesSupported" Type="integer" Value="7" />
          <RegistryValue Name="CustomSource" Type="integer" Value="1" />
        </RegistryKey>
      </Component>
      <Component Id="ProgramDataAclMarker" Directory="ENDLESSNETPROGRAMDATA" Guid="*" Bitness="always64">
        <CreateFolder>
          <PermissionEx Sddl="D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)" />
        </CreateFolder>
        <RegistryValue Root="HKLM" Key="Software\EndlessNet\Client" Name="ProgramDataPrepared" Type="integer" Value="1" KeyPath="yes" />
      </Component>
      <Component Id="RemoveStateOnUninstall" Directory="ENDLESSNETPROGRAMDATA" Guid="*" Bitness="always64">
        <RegistryValue Root="HKLM" Key="Software\EndlessNet\Client" Name="RemoveStateMarker" Type="integer" Value="1" KeyPath="yes" />
        <util:RemoveFolderEx Id="RemoveEndlessNetStateRoot" On="uninstall" Property="ENDLESSNET_REMOVE_STATE_ROOT" Condition="ENDLESSNET_REMOVE_STATE=&quot;1&quot;" />
      </Component>
      <Component Id="ResetStateBeforeInstall" Directory="ENDLESSNETPROGRAMDATA" Guid="*" Bitness="always64" Condition="ENDLESSNET_REMOVE_STATE=&quot;1&quot;">
        <RemoveFile Id="RemoveClientStateBeforeInstall" Name="client.json" On="install" />
        <RemoveFile Id="RemoveAgentStateBeforeInstall" Name="agent-state.json" On="install" />
        <RemoveFile Id="RemoveAgentLockBeforeInstall" Name="client.json.agent.lock" On="install" />
        <RegistryValue Root="HKLM" Key="Software\EndlessNet\Client" Name="StateResetMarker" Type="integer" Value="1" KeyPath="yes" />
      </Component>
    </ComponentGroup>
    <ComponentGroup Id="EndlessNetShortcutComponents" Directory="ApplicationProgramsFolder">
      <Component Id="ApplicationShortcut" Guid="*">
        <Shortcut Id="EndlessNetShortcut" Name="EndlessNet" Description="Open EndlessNet" Target="[INSTALLFOLDER]endlessnet.exe" Arguments="--show-window --debug --debug-log-dir %s" WorkingDirectory="INSTALLFOLDER" Icon="EndlessNetIcon" />
        <RemoveFolder Id="RemoveEndlessNetProgramMenuFolder" On="uninstall" />
        <RegistryValue Root="HKCU" Key="Software\EndlessNet\Client" Name="StartMenuShortcut" Type="integer" Value="1" KeyPath="yes" />
      </Component>
    </ComponentGroup>
    <ComponentGroup Id="EndlessNetAppBundleFiles" Directory="INSTALLFOLDER">
      <Files Include="$(var.AppBundleDir)\*.dll" />
      <Files Include="$(var.AppBundleDir)\native_assets.json" />
    </ComponentGroup>
    <ComponentGroup Id="EndlessNetAppDataFiles" Directory="EndlessNetAppDataFolder">
      <Files Include="$(var.AppBundleDir)\data\**" />
    </ComponentGroup>
  </Package>
</Wix>
`,
		xmlAttrEscape(opts.ProductName),
		xmlAttrEscape(opts.Manufacturer),
		xmlAttrEscape(opts.Version),
		xmlAttrEscape(opts.UpgradeCode),
		xmlAttrEscape(opts.ProductName),
		xmlAttrEscape(opts.Manufacturer),
		idempotentInstallCondition,
		removeStatePropertyValue,
		xmlAttrEscape(stateRoot),
		appShutdownCondition,
		appShutdownCondition,
		xmlAttrEscape(opts.ServiceOptions.DebugLogDir),
		xmlAttrEscape(opts.ProductName),
		xmlAttrEscape(opts.ServiceOptions.ServiceName),
		xmlAttrEscape(opts.ServiceOptions.DisplayName),
		xmlAttrEscape(opts.ServiceOptions.Description),
		xmlAttrEscape(strings.Join(serviceArgs, " ")),
		xmlAttrEscape(opts.ServiceOptions.ServiceName),
		xmlAttrEscape(opts.ServiceOptions.DebugLogDir),
		xmlAttrEscape(opts.ServiceOptions.DebugLogDir),
		xmlAttrEscape(opts.ServiceOptions.EventLogSource),
		xmlAttrEscape(opts.ServiceOptions.DebugLogDir),
	)
}

func renderWindowsInstallerBuildScript(opts WindowsInstallerOptions) string {
	return fmt.Sprintf(`param(
  [string]$ClientExe = %s,
  [string]$RecoveryHelperExe = %s,
  [string]$WintunDll = %s,
  [string]$WintunLicense = %s,
  [string]$AppExe = %s,
  [string]$AppBundleDir = %s,
  [string]$IconFile = %s,
  [string]$Output = %s,
  [string]$Version = %s,
  [string]$SignTool = $env:SIGNTOOL_EXE,
  [string]$CertificateThumbprint = $env:ENDLESSNET_CODESIGN_THUMBPRINT
)

$ErrorActionPreference = "Stop"
$utilExtension = "WixToolset.Util.wixext"
$uiExtension = "WixToolset.UI.wixext"

foreach ($path in @($ClientExe, $RecoveryHelperExe, $WintunDll, $WintunLicense, $AppExe, $IconFile)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required MSI input missing: $path"
  }
}
if ([string]::IsNullOrWhiteSpace($AppBundleDir)) {
  $AppBundleDir = Split-Path -Parent $AppExe
}
if (-not (Test-Path -LiteralPath $AppBundleDir)) {
  throw "Required MSI app bundle directory missing: $AppBundleDir"
}

$wix = Get-Command wix.exe -ErrorAction SilentlyContinue
if (-not $wix) {
  throw "WiX Toolset wix.exe is required to build EndlessNet.Client.msi"
}

$wixArgs = @(
  "build",
  "-arch", "x64",
  "-ext", $utilExtension,
  "-ext", $uiExtension,
  "-d", "ClientExe=$ClientExe",
  "-d", "RecoveryHelperExe=$RecoveryHelperExe",
  "-d", "WintunDll=$WintunDll",
  "-d", "WintunLicense=$WintunLicense",
  "-d", "AppExe=$AppExe",
  "-d", "AppBundleDir=$AppBundleDir",
  "-d", "IconFile=$IconFile",
  "-d", "ProductVersion=$Version",
  "-o", $Output,
  (Join-Path $PSScriptRoot "EndlessNet.Client.wxs")
)
& $wix.Source @wixArgs

if ($LASTEXITCODE -ne 0) {
  throw "WiX build failed with exit code $LASTEXITCODE"
}

if ($SignTool.Trim() -ne "" -and $CertificateThumbprint.Trim() -ne "") {
  & $SignTool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /sha1 $CertificateThumbprint "$Output"
  if ($LASTEXITCODE -ne 0) {
    throw "MSI signing failed with exit code $LASTEXITCODE"
  }
}
`,
		quotePowerShellSingle(opts.ClientExe),
		quotePowerShellSingle(opts.RecoveryHelperExe),
		quotePowerShellSingle(opts.WintunDLL),
		quotePowerShellSingle(opts.WintunLicense),
		quotePowerShellSingle(opts.AppExe),
		quotePowerShellSingle(opts.AppBundleDir),
		quotePowerShellSingle(opts.IconFile),
		quotePowerShellSingle(opts.OutputName),
		quotePowerShellSingle(opts.Version),
	)
}

func windowsParentPath(value string) string {
	value = strings.TrimRight(strings.TrimSpace(value), `\/`)
	if value == "" {
		return ""
	}
	idx := strings.LastIndexAny(value, `\/`)
	if idx <= 0 {
		return ""
	}
	return value[:idx]
}

func firstNonEmptyInstallerString(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func xmlAttrEscape(value string) string {
	var b strings.Builder
	_ = xml.EscapeText(&b, []byte(value))
	return strings.ReplaceAll(b.String(), `"`, "&quot;")
}
