param(
    [Parameter(Mandatory = $true)]
    [string]$UIVersion,
    [Parameter(Mandatory = $true)]
    [string]$CoreVersion,
    [Parameter(Mandatory = $true)]
    [string]$ClientExe,
    [string]$WintunDll = "",
    [string]$OutputDir = "",
    [string]$Msi = "",
    [string]$IconFile = "",
    [string]$PublicBaseUrl = "https://endlessnet.ru/downloads",
    [switch]$Sign,
    [string]$SigningMode = $env:WINDOWS_CODESIGN_MODE,
    [string]$SignTool = $env:SIGNTOOL_EXE,
    [string]$CertificateThumbprint = $env:ENDLESSNET_CODESIGN_THUMBPRINT
)

$ErrorActionPreference = "Stop"

if ($Sign -and $SigningMode -notin @("temporary-self-signed", "public-authenticode")) {
    throw "SigningMode must be temporary-self-signed or public-authenticode for signed releases"
}
if ($UIVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "UIVersion must be a stable SemVer without a v prefix"
}
if ($CoreVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "CoreVersion must be a stable SemVer without a v prefix"
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot "dist\windows-client-msi"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

if ([string]::IsNullOrWhiteSpace($Msi)) {
    $Msi = Join-Path $OutputDir "EndlessNet.Client.$UIVersion.msi"
}
$Msi = [System.IO.Path]::GetFullPath($Msi)

if ([string]::IsNullOrWhiteSpace($IconFile)) {
    $IconFile = Join-Path $repoRoot "app\assets\icons\endlessnet.ico"
}
$IconFile = [System.IO.Path]::GetFullPath($IconFile)
if (-not (Test-Path -LiteralPath $IconFile)) {
    throw "EndlessNet Windows icon is missing: $IconFile"
}

$ClientExe = [System.IO.Path]::GetFullPath($ClientExe)
if (-not (Test-Path -LiteralPath $ClientExe)) {
    throw "Verified EndlessNet Go client is missing: $ClientExe"
}

$wintunVersion = "0.14.1"
$wintunArchiveSHA256 = "07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51"
if ([string]::IsNullOrWhiteSpace($WintunDll)) {
    $wintunArchive = Join-Path $OutputDir "wintun-$wintunVersion.zip"
    $wintunExtractDir = Join-Path $OutputDir "wintun-$wintunVersion"
    Invoke-WebRequest -Uri "https://www.wintun.net/builds/wintun-$wintunVersion.zip" -OutFile $wintunArchive
    $actualArchiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $wintunArchive).Hash.ToLowerInvariant()
    if ($actualArchiveHash -ne $wintunArchiveSHA256) {
        throw "Official Wintun archive SHA-256 mismatch: got $actualArchiveHash"
    }
    if (Test-Path -LiteralPath $wintunExtractDir) {
        Remove-Item -LiteralPath $wintunExtractDir -Recurse -Force
    }
    Expand-Archive -LiteralPath $wintunArchive -DestinationPath $wintunExtractDir -Force
    $WintunDll = Join-Path $wintunExtractDir "wintun\bin\amd64\wintun.dll"
}
$WintunDll = [System.IO.Path]::GetFullPath($WintunDll)
if (-not (Test-Path -LiteralPath $WintunDll)) {
    throw "Verified Wintun DLL is missing: $WintunDll"
}
$wintunSignature = Get-AuthenticodeSignature -LiteralPath $WintunDll
if ($wintunSignature.Status -ne "Valid") {
    throw "Official Wintun Authenticode verification failed: $($wintunSignature.Status)"
}
if ($Sign -and $wintunSignature.SignerCertificate.Thumbprint -eq $CertificateThumbprint) {
    throw "Official Wintun signature must not be replaced by the EndlessNet release signer"
}
$clientVersion = (& $ClientExe version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $clientVersion -notmatch "endlessnet-client\s+$([regex]::Escape($CoreVersion))(\s|$)") {
    throw "Go client version does not match requested client-core release $CoreVersion"
}

$commit = (& git -C $repoRoot rev-parse HEAD).Trim()
$buildDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$packagedClientExe = Join-Path $OutputDir "endlessnet-client.exe"
$packagedWintunDll = Join-Path $OutputDir "wintun.dll"
$appBundleDir = Join-Path $OutputDir "app"
$appExe = Join-Path $appBundleDir "endlessnet.exe"
$renderDir = Join-Path $OutputDir "installer"
$wingetDir = Join-Path $OutputDir "winget"

Copy-Item -LiteralPath $ClientExe -Destination $packagedClientExe -Force
Copy-Item -LiteralPath $WintunDll -Destination $packagedWintunDll -Force

$flutterApp = Join-Path $repoRoot "app"
Push-Location $flutterApp
try {
    & flutter build windows --release `
        --build-name $UIVersion `
        --dart-define "ENDLESSNET_VERSION=$UIVersion" `
        --dart-define "ENDLESSNET_COMMIT=$commit" `
        --dart-define "ENDLESSNET_BUILD_DATE=$buildDate" `
        --dart-define "ENDLESSNET_TARGET=windows/amd64"
    if ($LASTEXITCODE -ne 0) {
        throw "EndlessNet Flutter build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
$flutterReleaseDir = Join-Path $flutterApp "build\windows\x64\runner\Release"
if (-not (Test-Path -LiteralPath (Join-Path $flutterReleaseDir "endlessnet.exe"))) {
    throw "EndlessNet Flutter release artifact is missing from $flutterReleaseDir"
}
if (Test-Path -LiteralPath $appBundleDir) {
    Remove-Item -LiteralPath $appBundleDir -Recurse -Force
}
New-Item -ItemType Directory -Path $appBundleDir -Force | Out-Null
Copy-Item -Path (Join-Path $flutterReleaseDir "*") -Destination $appBundleDir -Recurse -Force

$unsignedClientHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagedClientExe).Hash.ToLowerInvariant()
$wintunHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagedWintunDll).Hash.ToLowerInvariant()
$unsignedAppHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $appExe).Hash.ToLowerInvariant()

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
    $allowedStatuses = if ($SigningMode -eq "temporary-self-signed") {
        @("Valid", "NotTrusted", "UnknownError")
    } else {
        @("Valid")
    }
    if ($signature.Status -notin $allowedStatuses) {
        throw "Authenticode verification failed for ${Path}: $($signature.Status)"
    }
    if ($signature.SignerCertificate.Thumbprint -ne $CertificateThumbprint) {
        throw "Unexpected Authenticode signer for $Path"
    }
}

Invoke-EndlessNetSign $packagedClientExe
Invoke-EndlessNetSign $appExe
$signedClientHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagedClientExe).Hash.ToLowerInvariant()
$signedAppHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $appExe).Hash.ToLowerInvariant()

Push-Location $repoRoot
try {
    & go run ./tools/windows-packaging/cmd/endlessnet-windows-package render-msi `
        --output-dir $renderDir `
        --version $UIVersion `
        --client-exe $packagedClientExe `
        --wintun-dll $packagedWintunDll `
        --app-exe $appExe `
        --app-bundle-dir $appBundleDir `
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
$installerUrl = "$($PublicBaseUrl.TrimEnd('/'))/v$UIVersion/$([System.IO.Path]::GetFileName($Msi))"
Push-Location $repoRoot
try {
    & go run ./tools/windows-packaging/cmd/endlessnet-windows-package render-winget `
        --output-dir $wingetDir `
        --version $UIVersion `
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
    schema_version = 2
    version = $UIVersion
    ui_commit = $commit
    target = "windows/amd64"
    signed = [bool]$Sign
    signing = [ordered]@{
        mode = $(if ($Sign) { $SigningMode } else { "unsigned" })
        certificate_thumbprint = $(if ($Sign) { $CertificateThumbprint.ToUpperInvariant() } else { $null })
        publicly_trusted = [bool]($Sign -and $SigningMode -eq "public-authenticode")
    }
    client = [ordered]@{
        version = $CoreVersion
        path = $packagedClientExe
        unsigned_sha256 = $unsignedClientHash
        signed_sha256 = $signedClientHash
    }
    wintun = [ordered]@{
        version = $wintunVersion
        path = $packagedWintunDll
        archive_sha256 = $wintunArchiveSHA256
        sha256 = $wintunHash
        signer_thumbprint = $wintunSignature.SignerCertificate.Thumbprint.ToUpperInvariant()
    }
    app = [ordered]@{
        path = $appExe
        bundle_dir = $appBundleDir
        unsigned_sha256 = $unsignedAppHash
        signed_sha256 = $signedAppHash
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
Write-Host "WintunDll=$packagedWintunDll"
Write-Host "AppExe=$appExe"
Write-Host "AppBundleDir=$appBundleDir"
Write-Host "WingetDir=$wingetDir"
Write-Host "BuildOutput=$buildOutputPath"
