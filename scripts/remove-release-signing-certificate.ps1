param(
    [string]$StateDirectory = $env:ENDLESSNET_CODESIGN_STATE_DIR,
    [string]$GitHubEnvironmentFile = $env:GITHUB_ENV
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-TemporaryStateDirectory([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
        throw "RUNNER_TEMP is required for release signing cleanup"
    }
    $runnerTemp = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\', '/')
    $candidate = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    if (-not $candidate.StartsWith("$runnerTemp$([IO.Path]::DirectorySeparatorChar)", [StringComparison]::OrdinalIgnoreCase)) {
        throw "release signing state must be a child of RUNNER_TEMP"
    }
    return $candidate
}

function Remove-PrivateKey([Security.Cryptography.X509Certificates.X509Certificate2]$Certificate) {
    if (-not $Certificate.HasPrivateKey) {
        return
    }

    $rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
    if ($null -ne $rsa) {
        if ($rsa -is [Security.Cryptography.RSACng]) {
            $keyName = $rsa.Key.KeyName
            $provider = $rsa.Key.Provider
            $rsa.Dispose()
            $key = [Security.Cryptography.CngKey]::Open(
                $keyName,
                $provider,
                [Security.Cryptography.CngKeyOpenOptions]::UserKey)
            try {
                $key.Delete()
            } finally {
                $key.Dispose()
            }
            return
        }
        if ($rsa -is [Security.Cryptography.RSACryptoServiceProvider]) {
            $rsa.PersistKeyInCsp = $false
            $rsa.Clear()
            $rsa.Dispose()
            return
        }
        $rsa.Dispose()
        throw "unsupported RSA private-key provider for release signing certificate"
    }

    $ecdsa = [Security.Cryptography.X509Certificates.ECDsaCertificateExtensions]::GetECDsaPrivateKey($Certificate)
    if ($null -ne $ecdsa) {
        if ($ecdsa -isnot [Security.Cryptography.ECDsaCng]) {
            $ecdsa.Dispose()
            throw "unsupported ECDSA private-key provider for release signing certificate"
        }
        $keyName = $ecdsa.Key.KeyName
        $provider = $ecdsa.Key.Provider
        $ecdsa.Dispose()
        $key = [Security.Cryptography.CngKey]::Open(
            $keyName,
            $provider,
            [Security.Cryptography.CngKeyOpenOptions]::UserKey)
        try {
            $key.Delete()
        } finally {
            $key.Dispose()
        }
        return
    }

    throw "release signing certificate has an unsupported private-key algorithm"
}

function Remove-TrackedCertificates([string]$Store, [string]$StateFile, [bool]$DeletePrivateKey) {
    if (-not (Test-Path -LiteralPath $StateFile)) {
        return
    }
    foreach ($thumbprint in @(Get-Content -LiteralPath $StateFile)) {
        if ([string]::IsNullOrWhiteSpace($thumbprint)) {
            continue
        }
        if ($thumbprint -notmatch '^[a-fA-F0-9]{40}$') {
            throw "invalid certificate thumbprint in release signing cleanup state"
        }
        foreach ($certificate in @(Get-ChildItem $Store | Where-Object {
            $_.Thumbprint -eq $thumbprint
        })) {
            if ($DeletePrivateKey) {
                Remove-PrivateKey $certificate
            }
            Remove-Item -LiteralPath $certificate.PSPath -Force
        }
        if (@(Get-ChildItem $Store | Where-Object { $_.Thumbprint -eq $thumbprint }).Count -ne 0) {
            throw "release signing certificate cleanup did not remove a tracked certificate"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($StateDirectory)) {
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ATTEMPT)) {
        throw "GITHUB_RUN_ID and GITHUB_RUN_ATTEMPT are required for release signing cleanup"
    }
    $StateDirectory = Join-Path $env:RUNNER_TEMP "endlessnet-codesign-$($env:GITHUB_RUN_ID)-$($env:GITHUB_RUN_ATTEMPT)"
}
$StateDirectory = Assert-TemporaryStateDirectory $StateDirectory

if (Test-Path -LiteralPath $StateDirectory) {
    $personalStoreState = Join-Path $StateDirectory "current-user-my-thumbprints.txt"
    Remove-TrackedCertificates Cert:\CurrentUser\My $personalStoreState $true
    Remove-Item -LiteralPath $StateDirectory -Recurse -Force
}

if (-not [string]::IsNullOrWhiteSpace($GitHubEnvironmentFile)) {
    "ENDLESSNET_CODESIGN_THUMBPRINT=" >> $GitHubEnvironmentFile
    "SIGNTOOL_EXE=" >> $GitHubEnvironmentFile
}
