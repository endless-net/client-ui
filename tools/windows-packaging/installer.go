package client

import (
	"encoding/xml"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type WindowsInstallerOptions struct {
	ProductName    string
	Manufacturer   string
	Version        string
	UpgradeCode    string
	ClientExe      string
	TrayExe        string
	TrayBundleDir  string
	IconFile       string
	OutputName     string
	ServiceOptions WindowsServiceOptions
}

type WindowsInstallerArtifacts struct {
	WixSourceFile string `json:"wix_source_file"`
	BuildScript   string `json:"build_script"`
	BuildFile     string `json:"build_file"`
	WixSource     string `json:"wix_source"`
}

func DefaultWindowsInstallerOptions() WindowsInstallerOptions {
	return WindowsInstallerOptions{
		ProductName:    "EndlessNet Client",
		Manufacturer:   "UNNG",
		Version:        "0.0.0",
		UpgradeCode:    "9f7a7362-64c3-4b3a-9a58-7c8fc90779e1",
		ClientExe:      `C:\Program Files\EndlessNet\endlessnet-client.exe`,
		TrayExe:        `C:\Program Files\EndlessNet\endlessnet-tray.exe`,
		TrayBundleDir:  `C:\Program Files\EndlessNet`,
		IconFile:       filepath.Join("assets", "endlessnet", "tray.ico"),
		OutputName:     "EndlessNet.Client.msi",
		ServiceOptions: DefaultWindowsServiceOptions(),
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
	if strings.TrimSpace(opts.TrayExe) == "" {
		opts.TrayExe = defaults.TrayExe
	}
	if strings.TrimSpace(opts.TrayBundleDir) == "" {
		opts.TrayBundleDir = firstNonEmptyInstallerString(windowsParentPath(opts.TrayExe), defaults.TrayBundleDir)
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
		"product name": opts.ProductName,
		"manufacturer": opts.Manufacturer,
		"version":      opts.Version,
		"upgrade code": opts.UpgradeCode,
		"client exe":   opts.ClientExe,
		"tray exe":     opts.TrayExe,
		"tray bundle":  opts.TrayBundleDir,
		"icon file":    opts.IconFile,
		"output name":  opts.OutputName,
		"service name": opts.ServiceOptions.ServiceName,
		"display name": opts.ServiceOptions.DisplayName,
		"config path":  opts.ServiceOptions.ConfigPath,
		"wg config":    opts.ServiceOptions.WGConfigPath,
		"agent state":  opts.ServiceOptions.StatePath,
		"diagnostics":  opts.ServiceOptions.DiagnosticsDir,
		"event source": opts.ServiceOptions.EventLogSource,
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
	return nil
}

func renderWindowsInstallerWix(opts WindowsInstallerOptions) string {
	serviceArgs := windowsServiceAgentArgs(opts.ServiceOptions)
	stateRoot := windowsParentPath(opts.ServiceOptions.ConfigPath)
	return fmt.Sprintf(`<?xml version="1.0" encoding="utf-8"?>
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs" xmlns:util="http://wixtoolset.org/schemas/v4/wxs/util">
  <Package Name="%s" Manufacturer="%s" Version="%s" UpgradeCode="{%s}" Scope="perMachine">
    <SummaryInformation Description="%s installer" Manufacturer="%s" />
    <MajorUpgrade AllowSameVersionUpgrades="yes" DowngradeErrorMessage="A newer version of EndlessNet Client is already installed." />
    <Property Id="ENDLESSNET_REMOVE_STATE" Secure="yes" />
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
      <Publish Dialog="ExitDialog" Control="Finish" Event="DoAction" Value="LaunchEndlessNetTray" Order="1" Condition="WIXUI_EXITDIALOGOPTIONALCHECKBOX = 1 and NOT Installed" />
      <Publish Dialog="ExitDialog" Control="Finish" Event="EndDialog" Value="Return" Order="2" Condition="1" />
    </UI>
    <UIRef Id="WixUI_Common" />
    <Property Id="WIXUI_EXITDIALOGOPTIONALCHECKBOX" Value="1" />
    <Property Id="WIXUI_EXITDIALOGOPTIONALCHECKBOXTEXT" Value="Launch EndlessNet now" />
    <util:CloseApplication Id="CloseEndlessNetTray" Target="endlessnet-tray.exe" CloseMessage="yes" ElevatedCloseMessage="yes" TerminateProcess="1" RebootPrompt="no" Timeout="5" />
    <CustomAction Id="KillEndlessNetTray" Directory="SystemFolder" ExeCommand="&quot;[SystemFolder]taskkill.exe&quot; /F /IM endlessnet-tray.exe /T" Execute="immediate" Return="ignore" />
    <InstallExecuteSequence>
      <Custom Action="KillEndlessNetTray" Before="InstallValidate" />
    </InstallExecuteSequence>
    <CustomAction Id="LaunchEndlessNetTray" FileRef="TrayExeFile" ExeCommand="--show-window --debug --debug-log-dir %s" Execute="immediate" Return="asyncNoWait" Impersonate="yes" />
    <Icon Id="EndlessNetTrayIcon" SourceFile="$(var.IconFile)" />
    <Feature Id="ProductFeature" Title="%s" Level="1">
      <ComponentGroupRef Id="EndlessNetClientComponents" />
      <ComponentGroupRef Id="EndlessNetTrayBundleFiles" />
      <ComponentGroupRef Id="EndlessNetTrayDataFiles" />
    </Feature>
    <StandardDirectory Id="SystemFolder" />
    <StandardDirectory Id="ProgramMenuFolder">
      <Directory Id="ApplicationProgramsFolder" Name="EndlessNet" />
    </StandardDirectory>
    <StandardDirectory Id="ProgramFiles64Folder">
      <Directory Id="INSTALLFOLDER" Name="EndlessNet">
        <Directory Id="TrayDataFolder" Name="data" />
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
      <Component Id="TrayExecutable" Guid="*" Bitness="always64">
        <File Id="TrayExeFile" Source="$(var.TrayExe)" Name="endlessnet-tray.exe" KeyPath="yes" />
        <Shortcut Id="EndlessNetTrayShortcut" Directory="ApplicationProgramsFolder" Name="EndlessNet" Description="Open EndlessNet" Target="[INSTALLFOLDER]endlessnet-tray.exe" Arguments="--show-window --debug --debug-log-dir %s" WorkingDirectory="INSTALLFOLDER" Icon="EndlessNetTrayIcon" />
        <RemoveFolder Id="RemoveEndlessNetProgramMenuFolder" Directory="ApplicationProgramsFolder" On="uninstall" />
      </Component>
      <Component Id="TrayIcon" Guid="*" Bitness="always64">
        <File Id="TrayIconFile" Source="$(var.IconFile)" Name="endlessnet.ico" KeyPath="yes" />
      </Component>
      <Component Id="TrayAutostart" Guid="*" Bitness="always64">
        <RegistryValue Root="HKCU" Key="Software\Microsoft\Windows\CurrentVersion\Run" Name="EndlessNet Tray" Value="&quot;[INSTALLFOLDER]endlessnet-tray.exe&quot; --debug --debug-log-dir %s" Type="string" KeyPath="yes" />
      </Component>
      <Component Id="DeepLinkProtocol" Guid="*" Bitness="always64">
        <RegistryKey Root="HKLM" Key="Software\Classes\endlessnet">
          <RegistryValue Value="URL:EndlessNet Enrollment" Type="string" KeyPath="yes" />
          <RegistryValue Name="URL Protocol" Value="" Type="string" />
          <RegistryKey Key="shell\open\command">
            <RegistryValue Value="&quot;[INSTALLFOLDER]endlessnet-tray.exe&quot; --debug --debug-log-dir %s --enroll &quot;%%1&quot;" Type="string" />
          </RegistryKey>
        </RegistryKey>
      </Component>
      <Component Id="EventLogSource" Guid="*" Bitness="always64">
        <RegistryKey Root="HKLM" Key="SYSTEM\CurrentControlSet\Services\EventLog\Application\%s">
          <RegistryValue Name="EventMessageFile" Type="expandable" Value="[SystemFolder]EventCreate.exe" KeyPath="yes" />
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
    </ComponentGroup>
    <ComponentGroup Id="EndlessNetTrayBundleFiles" Directory="INSTALLFOLDER">
      <Files Include="$(var.TrayBundleDir)\*.dll" />
      <Files Include="$(var.TrayBundleDir)\native_assets.json" />
    </ComponentGroup>
    <ComponentGroup Id="EndlessNetTrayDataFiles" Directory="TrayDataFolder">
      <Files Include="$(var.TrayBundleDir)\data\**" />
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
		xmlAttrEscape(stateRoot),
		xmlAttrEscape(opts.ServiceOptions.DebugLogDir),
		xmlAttrEscape(opts.ProductName),
		xmlAttrEscape(opts.ServiceOptions.ServiceName),
		xmlAttrEscape(opts.ServiceOptions.DisplayName),
		xmlAttrEscape(opts.ServiceOptions.Description),
		xmlAttrEscape(strings.Join(serviceArgs, " ")),
		xmlAttrEscape(opts.ServiceOptions.ServiceName),
		xmlAttrEscape(opts.ServiceOptions.DebugLogDir),
		xmlAttrEscape(opts.ServiceOptions.DebugLogDir),
		xmlAttrEscape(opts.ServiceOptions.DebugLogDir),
		xmlAttrEscape(opts.ServiceOptions.EventLogSource),
	)
}

func renderWindowsInstallerBuildScript(opts WindowsInstallerOptions) string {
	return fmt.Sprintf(`param(
  [string]$ClientExe = %s,
  [string]$TrayExe = %s,
  [string]$TrayBundleDir = %s,
  [string]$IconFile = %s,
  [string]$Output = %s,
  [string]$Version = %s,
  [string]$SignTool = $env:SIGNTOOL_EXE,
  [string]$CertificateThumbprint = $env:ENDLESSNET_CODESIGN_THUMBPRINT
)

$ErrorActionPreference = "Stop"
$utilExtension = "WixToolset.Util.wixext"
$uiExtension = "WixToolset.UI.wixext"

foreach ($path in @($ClientExe, $TrayExe, $IconFile)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required MSI input missing: $path"
  }
}
if ([string]::IsNullOrWhiteSpace($TrayBundleDir)) {
  $TrayBundleDir = Split-Path -Parent $TrayExe
}
if (-not (Test-Path -LiteralPath $TrayBundleDir)) {
  throw "Required MSI tray bundle directory missing: $TrayBundleDir"
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
  "-d", "TrayExe=$TrayExe",
  "-d", "TrayBundleDir=$TrayBundleDir",
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
		quotePowerShellSingle(opts.TrayExe),
		quotePowerShellSingle(opts.TrayBundleDir),
		quotePowerShellSingle(opts.IconFile),
		quotePowerShellSingle(opts.OutputName),
		quotePowerShellSingle(opts.Version),
	)
}

func windowsServiceAgentArgs(opts WindowsServiceOptions) []string {
	args := []string{
		"agent",
		"--windows-service",
		"--config", opts.ConfigPath,
		"--output", opts.WGConfigPath,
		"--state-output", opts.StatePath,
		"--diagnostics-dir", opts.DiagnosticsDir,
		"--interval", opts.Interval.String(),
		"--timeout", opts.Timeout.String(),
		"--stun-timeout", opts.STUNTimeout.String(),
		"--reconnect-max-delay", opts.ReconnectMaxDelay.String(),
		"--reconnect-jitter", fmt.Sprintf("%g", opts.ReconnectJitter),
		"--ipc-pipe", opts.IPCPipe,
		"--event-log-source", opts.EventLogSource,
	}
	if opts.Debug {
		args = append(args, "--debug", "--debug-log-dir", opts.DebugLogDir)
	}
	if opts.ApplyWireGuard {
		args = append(args, "--apply-wireguard", "--wireguard-windows", opts.WireGuardWindowsPath)
	}
	if opts.ListenPort > 0 {
		args = append(args, "--listen-port", fmt.Sprintf("%d", opts.ListenPort))
	}
	return quoteWindowsServiceArguments(args)
}

func quoteWindowsServiceArguments(args []string) []string {
	out := make([]string, 0, len(args))
	for _, arg := range args {
		out = append(out, `"`+strings.ReplaceAll(arg, `"`, `\"`)+`"`)
	}
	return out
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
