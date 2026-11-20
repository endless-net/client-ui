# Trust anchor for the Windows release channel. Keep the private signing key outside the repository.
$ReleaseCertificateSha256 = 'C7EC509B1041DC8DD369274BD4BE1CB69D8A9C4E64490A96AB863E83CB3379D1'
Add-Type -AssemblyName System.Security

function Get-ReleaseCertificateHash($Certificate) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($Certificate.RawData)).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Read-SignedRelease([string]$Manifest, [string]$Signature) {
    if ((Get-Item -LiteralPath $Manifest).Length -gt 16384 -or
        (Get-Item -LiteralPath $Signature).Length -gt 32768) { throw 'Release proof is too large' }
    $bytes = [IO.File]::ReadAllBytes($Manifest)
    $content = [Security.Cryptography.Pkcs.ContentInfo]::new($bytes)
    $cms = [Security.Cryptography.Pkcs.SignedCms]::new($content, $true)
    $cms.Decode([IO.File]::ReadAllBytes($Signature))
    if ($cms.SignerInfos.Count -ne 1) { throw 'Expected exactly one release signer' }
    $signer = $cms.SignerInfos[0]
    if ($signer.DigestAlgorithm.Value -ne '2.16.840.1.101.3.4.2.1' -or
        -not $signer.Certificate -or (Get-ReleaseCertificateHash $signer.Certificate) -cne $ReleaseCertificateSha256) {
        throw 'Unexpected release signer or digest algorithm'
    }
    $cms.CheckSignature($true)
    $release = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
    if ($release.schema -cne 1 -or $release.repository -cne 'endless-net/client-ui' -or
        $release.version -cnotmatch '^0\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,4})$' -or
        $release.commit -cnotmatch '^[0-9a-f]{40}$' -or
        $release.msi.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        ($release.msi.size -isnot [int] -and $release.msi.size -isnot [long]) -or $release.msi.size -lt 1 -or $release.msi.size -gt 1GB) {
        throw 'Invalid Windows release manifest'
    }
    return $release
}

function Assert-ReleasePackage([IO.Stream]$Stream, $Release) {
    if ($Stream.Length -ne $Release.msi.size -or
        (Get-FileHash -InputStream $Stream -Algorithm SHA256).Hash -ine $Release.msi.sha256) {
        throw 'Package bytes differ from signed release'
    }
}
