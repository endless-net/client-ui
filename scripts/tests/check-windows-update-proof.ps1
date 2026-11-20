$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../app/windows/release-signature.ps1')

function Assert-Rejected([scriptblock]$Action) {
    try { & $Action | Out-Null }
    catch { return }
    throw 'Invalid release proof was accepted'
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('endlessnet-proof-' + [guid]::NewGuid())
$null = New-Item -ItemType Directory -Path $fixture
$rsa = [Security.Cryptography.RSA]::Create(2048)
try {
    $certRequest = [Security.Cryptography.X509Certificates.CertificateRequest]::new(
        'CN=EndlessNet Test', $rsa, [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $cert = $certRequest.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-1), [DateTimeOffset]::UtcNow.AddHours(1))
    try {
        $payload = Join-Path $fixture 'windows-update.json'
        $proof = Join-Path $fixture 'windows-update.p7s'
        $package = Join-Path $fixture 'update.msi'
        [IO.File]::WriteAllBytes($package, [byte[]]@(1, 2, 3))
        $info = @{
            schema = 1; repository = 'endless-net/client-ui'; version = '0.9.0'; commit = 'a' * 40
            msi = @{ sha256 = (Get-FileHash -LiteralPath $package).Hash.ToLowerInvariant(); size = 3 }
        } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($payload, $info)
        $content = [Security.Cryptography.Pkcs.ContentInfo]::new([IO.File]::ReadAllBytes($payload))
        $signature = [Security.Cryptography.Pkcs.SignedCms]::new($content, $true)
        $signer = [Security.Cryptography.Pkcs.CmsSigner]::new($cert)
        $signer.DigestAlgorithm = [Security.Cryptography.Oid]::new('2.16.840.1.101.3.4.2.1')
        $signer.IncludeOption = [Security.Cryptography.X509Certificates.X509IncludeOption]::EndCertOnly
        $signature.ComputeSignature($signer)
        [IO.File]::WriteAllBytes($proof, $signature.Encode())

        Assert-Rejected { Read-SignedRelease $payload $proof }
        $ReleaseCertificateSha256 = Get-ReleaseCertificateHash $cert
        $verified = Read-SignedRelease $payload $proof
        if ($verified.version -cne '0.9.0') { throw 'Verified release version was lost' }
        $stream = [IO.File]::OpenRead($package)
        try { Assert-ReleasePackage $stream $verified }
        finally { $stream.Dispose() }
        [IO.File]::WriteAllBytes($package, [byte[]]@(1, 9, 3))
        $stream = [IO.File]::OpenRead($package)
        try { Assert-Rejected { Assert-ReleasePackage $stream $verified } }
        finally { $stream.Dispose() }
        [IO.File]::AppendAllText($payload, ' ')
        Assert-Rejected { Read-SignedRelease $payload $proof }
        Remove-Item -LiteralPath $proof
        Assert-Rejected { Read-SignedRelease $payload $proof }
    } finally { $cert.Dispose() }
} finally {
    $rsa.Dispose()
    Get-ChildItem -LiteralPath $fixture -File | Remove-Item -Force
    Remove-Item -LiteralPath $fixture
}
'Release proof checks passed'
