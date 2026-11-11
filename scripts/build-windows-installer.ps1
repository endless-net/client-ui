param(
    [Parameter(Mandatory)][string]$UIBundle,
    [Parameter(Mandatory)][string]$ClientBundle,
    [Parameter(Mandatory)][string]$ServiceProfile,
    [Parameter(Mandatory)][string]$UiPolicy,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$OutputDir,
    [string]$CrtDirectory,
    [switch]$Sign,
    [string]$CertificateThumbprint,
    [string]$SignTool = 'signtool.exe'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if ($Version -cnotmatch '^v?0\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw 'Expected v0.MINOR.PATCH' }
foreach ($name in 'UIBundle','ClientBundle','ServiceProfile','UiPolicy') {
    Set-Variable $name (Resolve-Path -LiteralPath (Get-Variable $name -ValueOnly)).Path
}
$output = [IO.Path]::GetFullPath($OutputDir)
if ($output.Equals($UIBundle, [StringComparison]::OrdinalIgnoreCase) -or
    $output.Equals($ClientBundle, [StringComparison]::OrdinalIgnoreCase) -or
    $output.StartsWith($UIBundle + '\', [StringComparison]::OrdinalIgnoreCase) -or
    $output.StartsWith($ClientBundle + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDir must be outside input bundles'
}
New-Item -ItemType Directory -Force -Path $output | Out-Null
$work = Join-Path ([IO.Path]::GetTempPath()) ('endlessnet-msi-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $work | Out-Null
try {
    foreach ($file in (Join-Path $ClientBundle 'client.exe'), (Join-Path $ClientBundle 'wintun.dll'), (Join-Path $UIBundle 'endlessnet_client_ui.exe')) {
        $stream = [IO.File]::OpenRead($file)
        try {
            $reader = [IO.BinaryReader]::new($stream)
            if ($reader.ReadUInt16() -ne 0x5A4D) { throw "Not a PE image: $file" }
            $stream.Position = 0x3C
            $stream.Position = $reader.ReadUInt32()
            if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) { throw "Expected Windows x64 image: $file" }
        } finally { $stream.Dispose() }
    }
    $uiVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $UIBundle 'endlessnet_client_ui.exe'))
    if ((@($uiVersion.FileMajorPart,$uiVersion.FileMinorPart,$uiVersion.FileBuildPart) -join '.') -cne $Version.TrimStart('v')) {
        throw 'UI executable version must match MSI version'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $UIBundle 'install-update.ps1'))) { throw 'Missing Windows update entrypoint' }
    $bundle = Join-Path $work 'ui'
    Copy-Item -LiteralPath $UIBundle -Destination $bundle -Recurse
    if (-not (Test-Path -LiteralPath (Join-Path $bundle 'msvcp140.dll'))) {
        if (-not $CrtDirectory) {
            $where = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
            $visualStudio = & $where -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
            $redist = Get-ChildItem -LiteralPath (Join-Path $visualStudio 'VC\Redist\MSVC') -Directory |
                Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'x64\Microsoft.VC143.CRT\msvcp140.dll')) } |
                Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
            if (-not $redist) { throw 'Visual C++ x64 app-local redistributable not found; supply CrtDirectory' }
            $CrtDirectory = Join-Path $redist.FullName 'x64\Microsoft.VC143.CRT'
        }
        Get-ChildItem -LiteralPath $CrtDirectory -Filter '*.dll' -Force | Copy-Item -Destination $bundle
    }
    foreach ($file in 'msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll') {
        if (-not (Test-Path -LiteralPath (Join-Path $bundle $file))) { throw "Missing app-local runtime: $file" }
    }

    # Validate with the actual producer binary. This mode performs no state/SCM IO.
    $settings = Get-Content -LiteralPath $ServiceProfile -Raw | ConvertFrom-Json
    $data = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'EndlessNet\Client'
    $process = [Diagnostics.ProcessStartInfo]::new((Join-Path $ClientBundle 'client.exe'), 'validate-config')
    $process.UseShellExecute = $false
    $process.CreateNoWindow = $true
    foreach ($key in @($process.EnvironmentVariables.Keys)) {
        if ($key.StartsWith('ENDLESSNET_CLIENT_', [StringComparison]::OrdinalIgnoreCase)) { $process.EnvironmentVariables.Remove($key) }
    }
    foreach ($entry in $settings.PSObject.Properties) {
        if ($entry.Value -isnot [string] -or $entry.Name -cnotmatch '^ENDLESSNET_CLIENT_[A-Z0-9_]+$') { throw 'Invalid service profile entry' }
        $process.EnvironmentVariables[$entry.Name] = $entry.Value
    }
    $process.EnvironmentVariables['ENDLESSNET_CLIENT_INSTALLATION_ID'] = '11111111-1111-4111-8111-111111111111'
    $process.EnvironmentVariables['ENDLESSNET_CLIENT_SERVICE_SID'] = 'S-1-5-18'
    $process.EnvironmentVariables['ENDLESSNET_CLIENT_STATE_DIRECTORY'] = Join-Path $data 'state'
    $process.EnvironmentVariables['ENDLESSNET_CLIENT_RUNTIME_INSTANCE_FILE'] = Join-Path $data 'runtime-instance'
    $child = [Diagnostics.Process]::Start($process)
    try { $child.WaitForExit(); if ($child.ExitCode -ne 0) { throw 'Client rejected installer configuration' } }
    finally { $child.Dispose() }
    Push-Location (Join-Path $repo 'app')
    try { & dart run tool/validate_installer_policy.dart $UiPolicy; if ($LASTEXITCODE) { throw 'UI policy validation failed' } }
    finally { Pop-Location }

    & cmake -S (Join-Path $repo 'packaging/windows') -B (Join-Path $work 'native') -A x64
    if ($LASTEXITCODE) { throw 'Native installer configure failed' }
    & cmake --build (Join-Path $work 'native') --config Release
    if ($LASTEXITCODE) { throw 'Native installer build failed' }
    $actions = Join-Path $work 'native/Release/endlessnet_installer_actions.dll'
    if ($Sign) {
        if (-not $CertificateThumbprint) { throw 'CertificateThumbprint is required for signing' }
        & $SignTool sign /sha1 $CertificateThumbprint /fd SHA256 (Join-Path $bundle 'endlessnet_client_ui.exe')
        if ($LASTEXITCODE) { throw 'UI publisher signing failed' }
        $certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$CertificateThumbprint"
        $signature = Set-AuthenticodeSignature -LiteralPath (Join-Path $bundle 'install-update.ps1') -Certificate $certificate -HashAlgorithm SHA256
        if ($signature.Status -ne 'Valid') { throw 'Update script publisher signing failed' }
    }
    & python -B (Join-Path $PSScriptRoot 'windows_installer.py') --ui $bundle --client $ClientBundle --service-profile $ServiceProfile --ui-policy $UiPolicy --actions $actions --version $Version --output $work
    if ($LASTEXITCODE) { throw 'MSI source generation failed' }
    $releaseVersion = 'v' + $Version.TrimStart('v')
    $msi = Join-Path $output "EndlessNet-$releaseVersion-windows-amd64.msi"
    & wix build (Join-Path $work 'EndlessNet.wxs') -arch x64 -o $msi
    if ($LASTEXITCODE) { throw 'MSI compilation failed' }
    if ($Sign) {
        if (-not $CertificateThumbprint) { throw 'CertificateThumbprint is required for signing' }
        & $SignTool sign /sha1 $CertificateThumbprint /fd SHA256 $msi
        if ($LASTEXITCODE) { throw 'MSI signing failed' }
    } else { Write-Warning 'Unsigned local validation MSI; not a production release.' }
    Get-FileHash -Algorithm SHA256 -LiteralPath $msi
} finally {
    # This is our generated absolute Temp directory, never an input or output bundle.
    $resolved = [IO.Path]::GetFullPath($work)
    if ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolved -Leaf).StartsWith('endlessnet-msi-')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
