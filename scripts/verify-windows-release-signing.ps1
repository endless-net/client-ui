param(
    [Parameter(Mandatory)][string]$Thumbprint,
    [Parameter(Mandatory)][string]$Installer,
    [Parameter(Mandatory)][string]$Bundle
)
$ErrorActionPreference = 'Stop'
foreach ($file in $Installer, (Join-Path $Bundle 'endlessnet_client_ui.exe'), (Join-Path $Bundle 'install-update.ps1')) {
    $signature = Get-AuthenticodeSignature -LiteralPath $file
    if ($signature.Status -ne 'Valid' -or $signature.SignatureType -ne 'Authenticode' -or
        $signature.SignerCertificate.Thumbprint -ine $Thumbprint) {
        throw "Authenticode verification failed for $(Split-Path $file -Leaf): $($signature.Status)"
    }
}
