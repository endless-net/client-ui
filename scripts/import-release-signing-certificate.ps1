param(
    [string]$Mode = $env:WINDOWS_CODESIGN_MODE,
    [string]$PfxBase64 = $env:WINDOWS_CODESIGN_PFX_BASE64,
    [string]$PfxPassword = $env:WINDOWS_CODESIGN_PFX_PASSWORD,
    [string]$ExpectedThumbprint = $env:WINDOWS_CODESIGN_EXPECTED_THUMBPRINT,
    [string]$StateDirectory = $env:ENDLESSNET_CODESIGN_STATE_DIR,
    [string]$GitHubEnvironmentFile = $env:GITHUB_ENV
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-TemporaryStateDirectory([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
        throw "RUNNER_TEMP is required for release signing state"
    }
    $runnerTemp = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\', '/')
    $candidate = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    if (-not $candidate.StartsWith("$runnerTemp$([IO.Path]::DirectorySeparatorChar)", [StringComparison]::OrdinalIgnoreCase)) {
        throw "release signing state must be a child of RUNNER_TEMP"
    }
    return $candidate
}

if ($Mode -notin @("temporary-self-signed", "public-authenticode")) {
    throw "WINDOWS_CODESIGN_MODE must be temporary-self-signed or public-authenticode"
}
if ([string]::IsNullOrWhiteSpace($PfxBase64) -or [string]::IsNullOrWhiteSpace($PfxPassword)) {
    throw "release signing PFX and password are not configured in the release environment"
}
if ([string]::IsNullOrWhiteSpace($ExpectedThumbprint) -or $ExpectedThumbprint -notmatch '^[a-fA-F0-9]{40}$') {
    throw "WINDOWS_CODESIGN_EXPECTED_THUMBPRINT must contain the stable release certificate SHA-1 thumbprint"
}
if ([string]::IsNullOrWhiteSpace($StateDirectory)) {
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ATTEMPT)) {
        throw "GITHUB_RUN_ID and GITHUB_RUN_ATTEMPT are required for release signing state"
    }
    $StateDirectory = Join-Path $env:RUNNER_TEMP "endlessnet-codesign-$($env:GITHUB_RUN_ID)-$($env:GITHUB_RUN_ATTEMPT)"
}
if ([string]::IsNullOrWhiteSpace($GitHubEnvironmentFile)) {
    throw "GITHUB_ENV is required for release signing"
}

$StateDirectory = Assert-TemporaryStateDirectory $StateDirectory
$ExpectedThumbprint = $ExpectedThumbprint.ToUpperInvariant()
$pfxPath = Join-Path $StateDirectory "release-signing.pfx"
$personalStoreState = Join-Path $StateDirectory "current-user-my-thumbprints.txt"
$importedCertificates = @()

try {
    New-Item -ItemType Directory -Path $StateDirectory -Force | Out-Null
    try {
        $pfxBytes = [Convert]::FromBase64String($PfxBase64)
    } catch {
        throw "WINDOWS_CODESIGN_PFX_BASE64 is not valid Base64"
    }
    [IO.File]::WriteAllBytes($pfxPath, $pfxBytes)
    $pfxBytes = $null

    $password = ConvertTo-SecureString $PfxPassword -AsPlainText -Force
    try {
        $importedCertificates = @(Import-PfxCertificate `
            -FilePath $pfxPath `
            -CertStoreLocation Cert:\CurrentUser\My `
            -Password $password `
            -Exportable:$false)
    } finally {
        $password.Dispose()
        $password = $null
    }
    if ($importedCertificates.Count -eq 0) {
        throw "release signing PFX did not import any certificates"
    }
    $importedCertificates.Thumbprint | Set-Content -LiteralPath $personalStoreState -Encoding ascii

    $codeSigningCertificates = @()
    foreach ($importedCertificate in $importedCertificates) {
        $codeSigningEkus = @($importedCertificate.Extensions |
            Where-Object { $_.Oid.Value -eq "2.5.29.37" } |
            ForEach-Object { $_.EnhancedKeyUsages } |
            Where-Object { $_.Value -eq "1.3.6.1.5.5.7.3.3" })
        if ($importedCertificate.HasPrivateKey -and $codeSigningEkus.Count -gt 0) {
            $codeSigningCertificates += $importedCertificate
        }
    }
    if ($codeSigningCertificates.Count -ne 1) {
        throw "release signing PFX must contain exactly one code-signing certificate with a private key"
    }
    $certificate = $codeSigningCertificates[0]
    if ($certificate.Thumbprint.ToUpperInvariant() -ne $ExpectedThumbprint) {
        throw "release signing certificate does not match WINDOWS_CODESIGN_EXPECTED_THUMBPRINT"
    }
    $now = Get-Date
    if ($now -lt $certificate.NotBefore -or $now -ge $certificate.NotAfter) {
        throw "release signing certificate is not currently valid"
    }

    $subjectName = [Convert]::ToHexString($certificate.SubjectName.RawData)
    $issuerName = [Convert]::ToHexString($certificate.IssuerName.RawData)
    $isSelfSigned = $subjectName -eq $issuerName
    if ($Mode -eq "temporary-self-signed" -and -not $isSelfSigned) {
        throw "temporary-self-signed mode requires a self-signed code-signing certificate"
    }
    if ($Mode -eq "public-authenticode" -and $isSelfSigned) {
        throw "public-authenticode mode rejects self-signed certificates"
    }

    $signTool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Recurse -Filter signtool.exe |
        Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($null -eq $signTool) {
        throw "signtool.exe was not found"
    }

    "ENDLESSNET_CODESIGN_THUMBPRINT=$($certificate.Thumbprint.ToUpperInvariant())" >> $GitHubEnvironmentFile
    "SIGNTOOL_EXE=$($signTool.FullName)" >> $GitHubEnvironmentFile
} catch {
    try {
        & (Join-Path $PSScriptRoot "remove-release-signing-certificate.ps1") -StateDirectory $StateDirectory
    } catch {
        Write-Warning "release signing import failed and emergency certificate cleanup also failed"
    }
    throw
} finally {
    $PfxBase64 = $null
    $PfxPassword = $null
    if (Test-Path -LiteralPath $pfxPath) {
        Remove-Item -LiteralPath $pfxPath -Force
    }
}
