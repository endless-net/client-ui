# Import the release private key only on the GitHub-hosted publication runner.
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($env:WINDOWS_CODESIGN_PFX_BASE64) -or
    [string]::IsNullOrWhiteSpace($env:WINDOWS_CODESIGN_PFX_PASSWORD)) {
    throw 'Configure the release signing PFX and password in GitHub'
}
$pfx = Join-Path $env:RUNNER_TEMP ("codesign-" + [guid]::NewGuid() + '.pfx')
try {
    try {
        [IO.File]::WriteAllBytes($pfx, [Convert]::FromBase64String($env:WINDOWS_CODESIGN_PFX_BASE64))
        $password = ConvertTo-SecureString $env:WINDOWS_CODESIGN_PFX_PASSWORD -AsPlainText -Force
        $null = Import-PfxCertificate -FilePath $pfx -CertStoreLocation Cert:\CurrentUser\My -Password $password
    } catch {
        throw 'The Windows release signing PFX could not be imported'
    }
} finally {
    if (Test-Path -LiteralPath $pfx) { Remove-Item -LiteralPath $pfx -Force }
}
