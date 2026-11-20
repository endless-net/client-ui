param(
    [Parameter(Mandatory)][string]$Manifest,
    [Parameter(Mandatory)][string]$Signature
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../app/windows/release-signature.ps1')
$matches = @(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object {
    $_.HasPrivateKey -and (Get-ReleaseCertificateHash $_) -ceq $ReleaseCertificateSha256
})
if ($matches.Count -ne 1) { throw 'Pinned Windows release signing key not available' }
$content = [Security.Cryptography.Pkcs.ContentInfo]::new([IO.File]::ReadAllBytes($Manifest))
$cms = [Security.Cryptography.Pkcs.SignedCms]::new($content, $true)
$signer = [Security.Cryptography.Pkcs.CmsSigner]::new($matches[0])
$signer.IncludeOption = [Security.Cryptography.X509Certificates.X509IncludeOption]::EndCertOnly
$signer.DigestAlgorithm = [Security.Cryptography.Oid]::new('2.16.840.1.101.3.4.2.1')
$cms.ComputeSignature($signer, $true)
[IO.File]::WriteAllBytes($Signature, $cms.Encode())
$null = Read-SignedRelease $Manifest $Signature
