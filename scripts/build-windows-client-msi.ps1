param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [Parameter(Mandatory = $true)]
    [string]$ClientExe,
    [string]$OutputDir = "",
    [string]$Msi = "",
    [string]$IconFile = "",
    [string]$PublicBaseUrl = "https://endlessnet.ru/downloads",
    [switch]$Sign,
    [string]$SignTool = $env:SIGNTOOL_EXE,
    [string]$CertificateThumbprint = $env:ENDLESSNET_CODESIGN_THUMBPRINT
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot "dist\windows-client-msi"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

if ([string]::IsNullOrWhiteSpace($Msi)) {
    $Msi = Join-Path $OutputDir "EndlessNet.Client.$Version.msi"
}
$Msi = [System.IO.Path]::GetFullPath($Msi)

if ([string]::IsNullOrWhiteSpace($IconFile)) {
    $IconFile = Join-Path $repoRoot "app\assets\icons\tray.ico"
}
$IconFile = [System.IO.Path]::GetFullPath($IconFile)
if (-not (Test-Path -LiteralPath $IconFile)) {
    throw "EndlessNet Windows icon is missing: $IconFile"
}

$ClientExe = [System.IO.Path]::GetFullPath($ClientExe)
if (-not (Test-Path -LiteralPath $ClientExe)) {
    throw "Verified EndlessNet Go client is missing: $ClientExe"
}
$clientVersion = (& $ClientExe version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $clientVersion -notmatch "endlessnet-client\s+$([regex]::Escape($Version))(\s|$)") {
    throw "Go client version does not match requested release $Version"
}

$commit = (& git -C $repoRoot rev-parse HEAD).Trim()
$buildDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$packagedClientExe = Join-Path $OutputDir "endlessnet-client.exe"
$trayBundleDir = Join-Path $OutputDir "tray"
$trayExe = Join-Path $trayBundleDir "endlessnet-tray.exe"
$renderDir = Join-Path $OutputDir "installer"
$wingetDir = Join-Path $OutputDir "winget"

Copy-Item -LiteralPath $ClientExe -Destination $packagedClientExe -Force

$flutterApp = Join-Path $repoRoot "app"
Push-Location $flutterApp
try {
    & flutter build windows --release `
        --dart-define "ENDLESSNET_VERSION=$Version" `
        --dart-define "ENDLESSNET_COMMIT=$commit" `
        --dart-define "ENDLESSNET_BUILD_DATE=$buildDate" `
        --dart-define "ENDLESSNET_TARGET=windows/amd64"
    if ($LASTEXITCODE -ne 0) {
        throw "endlessnet-tray Flutter build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
$flutterReleaseDir = Join-Path $flutterApp "build\windows\x64\runner\Release"
if (-not (Test-Path -LiteralPath (Join-Path $flutterReleaseDir "endlessnet-tray.exe"))) {
    throw "endlessnet-tray Flutter release artifact is missing from $flutterReleaseDir"
}
if (Test-Path -LiteralPath $trayBundleDir) {
    Remove-Item -LiteralPath $trayBundleDir -Recurse -Force
}
New-Item -ItemType Directory -Path $trayBundleDir -Force | Out-Null
Copy-Item -Path (Join-Path $flutterReleaseDir "*") -Destination $trayBundleDir -Recurse -Force

$unsignedClientHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagedClientExe).Hash.ToLowerInvariant()
$unsignedTrayHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $trayExe).Hash.ToLowerInvariant()

function Invoke-EndlessNetSign([string]$Path) {
    if (-not $Sign) {
        return
    }
    if ([string]::IsNullOrWhiteSpace($SignTool) -or [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
        throw "SIGNTOOL_EXE and ENDLESSNET_CODESIGN_THUMBPRINT are required for signed releases"
    }
    & $SignTool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /sha1 $CertificateThumbprint $Path
    if ($LASTEXITCODE -ne 0) {
        throw "Authenticode signing failed for $Path with exit code $LASTEXITCODE"
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne "Valid") {
        throw "Authenticode verification failed for ${Path}: $($signature.Status)"
    }
}

Invoke-EndlessNetSign $packagedClientExe
Invoke-EndlessNetSign $trayExe
$signedClientHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagedClientExe).Hash.ToLowerInvariant()
$signedTrayHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $trayExe).Hash.ToLowerInvariant()

Push-Location $repoRoot
try {
    & go run ./tools/windows-packaging/cmd/endlessnet-windows-package render-msi `
        --output-dir $renderDir `
        --version $Version `
        --client-exe $packagedClientExe `
        --tray-exe $trayExe `
        --tray-bundle-dir $trayBundleDir `
        --icon-file $IconFile `
        --msi $Msi
    if ($LASTEXITCODE -ne 0) {
        throw "MSI artifact rendering failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$savedSignTool = $env:SIGNTOOL_EXE
$savedThumbprint = $env:ENDLESSNET_CODESIGN_THUMBPRINT
try {
    $env:SIGNTOOL_EXE = ""
    $env:ENDLESSNET_CODESIGN_THUMBPRINT = ""
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $renderDir "build-msi.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "MSI build failed with exit code $LASTEXITCODE"
    }
} finally {
    $env:SIGNTOOL_EXE = $savedSignTool
    $env:ENDLESSNET_CODESIGN_THUMBPRINT = $savedThumbprint
}

$unsignedMsiHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Msi).Hash.ToLowerInvariant()
Invoke-EndlessNetSign $Msi

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Msi).Hash.ToLowerInvariant()
$checksumFile = "$Msi.sha256"
Set-Content -LiteralPath $checksumFile -Value "$hash  $([System.IO.Path]::GetFileName($Msi))" -Encoding ascii
$installerUrl = "$($PublicBaseUrl.TrimEnd('/'))/v$Version/$([System.IO.Path]::GetFileName($Msi))"
Push-Location $repoRoot
try {
    & go run ./tools/windows-packaging/cmd/endlessnet-windows-package render-winget `
        --output-dir $wingetDir `
        --version $Version `
        --installer-file $Msi `
        --installer-url $installerUrl `
        --release-date ((Get-Date).ToUniversalTime().ToString("yyyy-MM-dd"))
    if ($LASTEXITCODE -ne 0) {
        throw "WinGet manifest generation failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$buildOutput = [ordered]@{
    schema_version = 1
    version = $Version
    ui_commit = $commit
    target = "windows/amd64"
    signed = [bool]$Sign
    client = [ordered]@{
        path = $packagedClientExe
        unsigned_sha256 = $unsignedClientHash
        signed_sha256 = $signedClientHash
    }
    tray = [ordered]@{
        path = $trayExe
        bundle_dir = $trayBundleDir
        unsigned_sha256 = $unsignedTrayHash
        signed_sha256 = $signedTrayHash
    }
    msi = [ordered]@{
        path = $Msi
        unsigned_sha256 = $unsignedMsiHash
        signed_sha256 = $hash
        checksum_path = $checksumFile
    }
    winget_dir = $wingetDir
}
$buildOutputPath = Join-Path $OutputDir "build-output.json"
$buildOutput | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $buildOutputPath -Encoding utf8

Write-Host "MSI=$Msi"
Write-Host "SHA256=$hash"
Write-Host "Checksum=$checksumFile"
Write-Host "ClientExe=$packagedClientExe"
Write-Host "TrayExe=$trayExe"
Write-Host "TrayBundleDir=$trayBundleDir"
Write-Host "WingetDir=$wingetDir"
Write-Host "BuildOutput=$buildOutputPath"
