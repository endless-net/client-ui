[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DistributionDir,
    [Parameter(Mandatory = $true)]
    [string]$Msi
)

$ErrorActionPreference = "Stop"
$DistributionDir = [System.IO.Path]::GetFullPath($DistributionDir)
$Msi = [System.IO.Path]::GetFullPath($Msi)
if (-not (Test-Path -LiteralPath $DistributionDir -PathType Container)) {
    throw "Windows distribution directory is missing: $DistributionDir"
}
if (-not (Test-Path -LiteralPath $Msi -PathType Leaf)) {
    throw "Windows distribution MSI is missing: $Msi"
}

$requiredStagedFiles = @(
    "endlessnet-client-recovery-helper.exe",
    "wintun-LICENSE.txt",
    "app\data\flutter_assets\NOTICES.Z",
    "app\data\licenses\endlessnet-client-ui\LICENSE",
    "app\data\licenses\endlessnet-client-ui\NOTICE",
    "app\data\licenses\endlessnet-client-ui\THIRD_PARTY_NOTICES",
    "app\data\licenses\endlessnet-client-ui\source-sbom.spdx.json",
    "app\data\licenses\endlessnet-client\LICENSE",
    "app\data\licenses\endlessnet-client\NOTICE",
    "app\data\licenses\endlessnet-client\THIRD_PARTY_NOTICES",
    "app\data\licenses\endlessnet-client\source-sbom.spdx.json"
)
foreach ($relative in $requiredStagedFiles) {
    $path = Join-Path $DistributionDir $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Windows distribution is missing required compliance file: $relative"
    }
}

$wix = Get-Command wix.exe -ErrorAction Stop
$decompileRoot = Join-Path ([System.IO.Path]::GetTempPath()) "endlessnet-msi-compliance-$([guid]::NewGuid().ToString('N'))"
$decompiledSource = Join-Path $decompileRoot "product.wxs"
New-Item -ItemType Directory -Path $decompileRoot | Out-Null
try {
    & $wix.Source msi decompile -sct -sdet -sras -sui -o $decompiledSource $Msi
    if ($LASTEXITCODE -ne 0) {
        throw "WiX failed to inspect the MSI with exit code $LASTEXITCODE"
    }
    [xml]$wixSource = Get-Content -LiteralPath $decompiledSource -Raw
    $fileNames = @(
        $wixSource.SelectNodes("//*[local-name()='File']") |
            ForEach-Object { [string]$_.Name }
    )
    $requiredMSIFileCounts = [ordered]@{
        "endlessnet-client-recovery-helper.exe" = 1
        "LICENSE" = 2
        "NOTICE" = 2
        "THIRD_PARTY_NOTICES" = 2
        "source-sbom.spdx.json" = 2
        "NOTICES.Z" = 1
        "wintun-LICENSE.txt" = 1
    }
    foreach ($entry in $requiredMSIFileCounts.GetEnumerator()) {
        $actual = @($fileNames | Where-Object { $_ -ceq $entry.Key }).Count
        if ($actual -ne $entry.Value) {
            throw "MSI contains $actual copies of $($entry.Key); expected $($entry.Value)"
        }
    }
} finally {
    if (Test-Path -LiteralPath $decompileRoot) {
        Remove-Item -LiteralPath $decompileRoot -Recurse -Force
    }
}

Write-Host "Verified licenses, notices, Flutter notices, and source SBOMs inside $Msi"
