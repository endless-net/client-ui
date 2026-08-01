param(
    [Parameter(Mandatory = $true)]
    [string]$UIVersion,
    [Parameter(Mandatory = $true)]
    [string]$CoreVersion,
    [Parameter(Mandatory = $true)]
    [string]$ClientExe,
    [Parameter(Mandatory = $true)]
    [string]$RecoveryHelperExe,
    [Parameter(Mandatory = $true)]
    [string]$CoreMetadataDir,
    [Parameter(Mandatory = $true)]
    [string]$UISourceSBOM,
    [string]$WintunDll = "",
    [string]$WintunLicense = "",
    [string]$OutputDir = "",
    [string]$Msi = "",
    [string]$IconFile = "",
    [string]$PublicBaseUrl = "https://github.com/endless-net/client-ui/releases/download",
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
$CoreMetadataDir = [System.IO.Path]::GetFullPath($CoreMetadataDir)
$UISourceSBOM = [System.IO.Path]::GetFullPath($UISourceSBOM)
if (-not (Test-Path -LiteralPath $CoreMetadataDir -PathType Container)) {
    throw "Verified client-core metadata directory is missing: $CoreMetadataDir"
}
if (-not (Test-Path -LiteralPath $UISourceSBOM -PathType Leaf)) {
    throw "UI source SBOM is missing: $UISourceSBOM"
}
$uiCompliance = [ordered]@{
    license = Join-Path $repoRoot "LICENSE"
    notice = Join-Path $repoRoot "NOTICE"
    third_party_notices = Join-Path $repoRoot "THIRD_PARTY_NOTICES"
}
$coreCompliance = [ordered]@{
    license = Join-Path $CoreMetadataDir "LICENSE"
    notice = Join-Path $CoreMetadataDir "NOTICE"
    third_party_notices = Join-Path $CoreMetadataDir "THIRD_PARTY_NOTICES"
    source_sbom = Join-Path $CoreMetadataDir "source-sbom.spdx.json"
}
foreach ($path in (@($uiCompliance.Values) + @($coreCompliance.Values))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required compliance input is missing: $path"
    }
}
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
$RecoveryHelperExe = [System.IO.Path]::GetFullPath($RecoveryHelperExe)
if (-not (Test-Path -LiteralPath $RecoveryHelperExe -PathType Leaf)) {
    throw "Verified EndlessNet recovery helper is missing: $RecoveryHelperExe"
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
    $WintunLicense = Join-Path $wintunExtractDir "wintun\LICENSE.txt"
}
$WintunDll = [System.IO.Path]::GetFullPath($WintunDll)
$WintunLicense = [System.IO.Path]::GetFullPath($WintunLicense)
if (-not (Test-Path -LiteralPath $WintunDll)) {
    throw "Verified Wintun DLL is missing: $WintunDll"
}
if (-not (Test-Path -LiteralPath $WintunLicense -PathType Leaf)) {
    throw "Official Wintun prebuilt-binary license is missing: $WintunLicense"
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
$packagedRecoveryHelperExe = Join-Path $OutputDir "endlessnet-client-recovery-helper.exe"
$packagedWintunDll = Join-Path $OutputDir "wintun.dll"
$packagedWintunLicense = Join-Path $OutputDir "wintun-LICENSE.txt"
$appBundleDir = Join-Path $OutputDir "app"
$appExe = Join-Path $appBundleDir "endlessnet.exe"
$renderDir = Join-Path $OutputDir "installer"
$wingetDir = Join-Path $OutputDir "winget"

Copy-Item -LiteralPath $ClientExe -Destination $packagedClientExe -Force
Copy-Item -LiteralPath $RecoveryHelperExe -Destination $packagedRecoveryHelperExe -Force
Copy-Item -LiteralPath $WintunDll -Destination $packagedWintunDll -Force
Copy-Item -LiteralPath $WintunLicense -Destination $packagedWintunLicense -Force

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

$licensesDir = Join-Path $appBundleDir "data\licenses"
$uiLicensesDir = Join-Path $licensesDir "endlessnet-client-ui"
$coreLicensesDir = Join-Path $licensesDir "endlessnet-client"
New-Item -ItemType Directory -Path $uiLicensesDir -Force | Out-Null
New-Item -ItemType Directory -Path $coreLicensesDir -Force | Out-Null
Copy-Item -LiteralPath $uiCompliance.license -Destination (Join-Path $uiLicensesDir "LICENSE") -Force
Copy-Item -LiteralPath $uiCompliance.notice -Destination (Join-Path $uiLicensesDir "NOTICE") -Force
Copy-Item -LiteralPath $uiCompliance.third_party_notices -Destination (Join-Path $uiLicensesDir "THIRD_PARTY_NOTICES") -Force
Copy-Item -LiteralPath $UISourceSBOM -Destination (Join-Path $uiLicensesDir "source-sbom.spdx.json") -Force
Copy-Item -LiteralPath $coreCompliance.license -Destination (Join-Path $coreLicensesDir "LICENSE") -Force
Copy-Item -LiteralPath $coreCompliance.notice -Destination (Join-Path $coreLicensesDir "NOTICE") -Force
Copy-Item -LiteralPath $coreCompliance.third_party_notices -Destination (Join-Path $coreLicensesDir "THIRD_PARTY_NOTICES") -Force
Copy-Item -LiteralPath $coreCompliance.source_sbom -Destination (Join-Path $coreLicensesDir "source-sbom.spdx.json") -Force

$unsignedClientHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagedClientExe).Hash.ToLowerInvariant()
$unsignedRecoveryHelperHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagedRecoveryHelperExe).Hash.ToLowerInvariant()
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
Invoke-EndlessNetSign $packagedRecoveryHelperExe
Invoke-EndlessNetSign $appExe
$signedClientHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagedClientExe).Hash.ToLowerInvariant()
$signedRecoveryHelperHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagedRecoveryHelperExe).Hash.ToLowerInvariant()
$signedAppHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $appExe).Hash.ToLowerInvariant()

Push-Location $repoRoot
try {
    & go run ./tools/windows-packaging/cmd/endlessnet-windows-package render-msi `
        --output-dir $renderDir `
        --version $UIVersion `
        --client-exe $packagedClientExe `
        --recovery-helper-exe $packagedRecoveryHelperExe `
        --wintun-dll $packagedWintunDll `
        --wintun-license $packagedWintunLicense `
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
    recovery_helper = [ordered]@{
        path = $packagedRecoveryHelperExe
        installed_name = "endlessnet-client-recovery-helper.exe"
        unsigned_sha256 = $unsignedRecoveryHelperHash
        signed_sha256 = $signedRecoveryHelperHash
    }
    wintun = [ordered]@{
        version = $wintunVersion
        path = $packagedWintunDll
        archive_sha256 = $wintunArchiveSHA256
        sha256 = $wintunHash
        signer_thumbprint = $wintunSignature.SignerCertificate.Thumbprint.ToUpperInvariant()
        license_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagedWintunLicense).Hash.ToLowerInvariant()
    }
    compliance = [ordered]@{
        ui_source_sbom_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $UISourceSBOM).Hash.ToLowerInvariant()
        core_source_sbom_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $coreCompliance.source_sbom).Hash.ToLowerInvariant()
        ui_license_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $uiCompliance.license).Hash.ToLowerInvariant()
        core_license_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $coreCompliance.license).Hash.ToLowerInvariant()
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
Write-Host "RecoveryHelperExe=$packagedRecoveryHelperExe"
Write-Host "WintunDll=$packagedWintunDll"
Write-Host "WintunLicense=$packagedWintunLicense"
Write-Host "AppExe=$appExe"
Write-Host "AppBundleDir=$appBundleDir"
Write-Host "WingetDir=$wingetDir"
Write-Host "BuildOutput=$buildOutputPath"
