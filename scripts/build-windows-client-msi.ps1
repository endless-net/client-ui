param(
    [string]$Version = "0.0.0",
    [string]$OutputDir = "",
    [string]$Msi = "",
    [string]$IconFile = "",
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
    $IconFile = Join-Path $repoRoot "assets\endlessnet\tray.ico"
}
$IconFile = [System.IO.Path]::GetFullPath($IconFile)
if (-not (Test-Path -LiteralPath $IconFile)) {
    throw "EndlessNet Windows icon is missing: $IconFile"
}

$commit = (& git -C $repoRoot rev-parse --short HEAD).Trim()
$buildDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$commonLdflags = "-s -w -X main.version=$Version -X main.commit=$commit -X main.buildDate=$buildDate"

$clientExe = Join-Path $OutputDir "endlessnet-client.exe"
$trayBundleDir = Join-Path $OutputDir "tray"
$trayExe = Join-Path $trayBundleDir "endlessnet-tray.exe"
$renderDir = Join-Path $OutputDir "installer"

& go build -trimpath -ldflags $commonLdflags -o $clientExe "$repoRoot\cmd\endlessnet-client"
if ($LASTEXITCODE -ne 0) {
    throw "endlessnet-client build failed with exit code $LASTEXITCODE"
}

$flutterApp = Join-Path $repoRoot "internal\windows\tray_flutter"
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

& $clientExe installer render-windows-msi `
    --output-dir $renderDir `
    --version $Version `
    --client-exe $clientExe `
    --tray-exe $trayExe `
    --tray-bundle-dir $trayBundleDir `
    --icon-file $IconFile `
    --msi $Msi
if ($LASTEXITCODE -ne 0) {
    throw "MSI artifact rendering failed with exit code $LASTEXITCODE"
}

$msiBuildArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $renderDir "build-msi.ps1")
)
if (-not [string]::IsNullOrWhiteSpace($SignTool)) {
    $msiBuildArgs += @("-SignTool", $SignTool)
}
if (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
    $msiBuildArgs += @("-CertificateThumbprint", $CertificateThumbprint)
}
& powershell.exe @msiBuildArgs
if ($LASTEXITCODE -ne 0) {
    throw "MSI build failed with exit code $LASTEXITCODE"
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Msi).Hash.ToLowerInvariant()
Write-Host "MSI=$Msi"
Write-Host "SHA256=$hash"
Write-Host "ClientExe=$clientExe"
Write-Host "TrayExe=$trayExe"
Write-Host "TrayBundleDir=$trayBundleDir"
