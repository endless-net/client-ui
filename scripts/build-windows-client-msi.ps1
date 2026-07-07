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
    $IconFile = Join-Path $repoRoot "assets\endlessnet\favicon.ico"
}
$IconFile = [System.IO.Path]::GetFullPath($IconFile)
if (-not (Test-Path -LiteralPath $IconFile)) {
    throw "EndlessNet Windows icon is missing: $IconFile"
}

$commit = (& git -C $repoRoot rev-parse --short HEAD).Trim()
$buildDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$commonLdflags = "-s -w -X main.version=$Version -X main.commit=$commit -X main.buildDate=$buildDate"

$clientExe = Join-Path $OutputDir "endlessnet-client.exe"
$trayExe = Join-Path $OutputDir "endlessnet-tray.exe"
$renderDir = Join-Path $OutputDir "installer"

& go build -trimpath -ldflags $commonLdflags -o $clientExe "$repoRoot\cmd\endlessnet-client"
if ($LASTEXITCODE -ne 0) {
    throw "endlessnet-client build failed with exit code $LASTEXITCODE"
}

$trayLdflags = "$commonLdflags -H=windowsgui"
& go build -trimpath -ldflags $trayLdflags -o $trayExe "$repoRoot\cmd\endlessnet-tray"
if ($LASTEXITCODE -ne 0) {
    throw "endlessnet-tray GUI build failed with exit code $LASTEXITCODE"
}

& $clientExe installer render-windows-msi `
    --output-dir $renderDir `
    --version $Version `
    --client-exe $clientExe `
    --tray-exe $trayExe `
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
