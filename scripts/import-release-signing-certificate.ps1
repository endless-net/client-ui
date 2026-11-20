# Runs only on a clean, GitHub-hosted Windows release runner.
$ErrorActionPreference = 'Stop'
$thumbprint = $env:WINDOWS_CODESIGN_EXPECTED_THUMBPRINT
if ($thumbprint -notmatch '^[0-9a-fA-F]{40}$' -or
    [string]::IsNullOrWhiteSpace($env:WINDOWS_CODESIGN_PFX_BASE64) -or
    [string]::IsNullOrWhiteSpace($env:WINDOWS_CODESIGN_PFX_PASSWORD)) {
    throw 'Configure the publisher PFX, password and thumbprint in the GitHub release environment'
}
$signTool = Get-ChildItem -LiteralPath "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Filter signtool.exe -Recurse |
    Where-Object { $_.Directory.Name -eq 'x64' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if (-not $signTool) { throw 'Windows SDK SignTool was not found' }

$pfx = Join-Path $env:RUNNER_TEMP ("codesign-" + [guid]::NewGuid() + '.pfx')
try {
    try {
        [IO.File]::WriteAllBytes($pfx, [Convert]::FromBase64String($env:WINDOWS_CODESIGN_PFX_BASE64))
        $password = ConvertTo-SecureString $env:WINDOWS_CODESIGN_PFX_PASSWORD -AsPlainText -Force
        $certificates = @(Import-PfxCertificate -FilePath $pfx -CertStoreLocation Cert:\CurrentUser\My -Password $password)
    } catch {
        throw 'The publisher PFX could not be imported'
    }
} finally {
    if (Test-Path -LiteralPath $pfx) { Remove-Item -LiteralPath $pfx -Force }
}
$signer = @($certificates | Where-Object { $_.HasPrivateKey -and $_.Thumbprint -ieq $thumbprint })
if ($signer.Count -ne 1) { throw 'Publisher PFX does not contain the configured signing key' }
$chain = [Security.Cryptography.X509Certificates.X509Chain]::new()
try {
    [void]$chain.ChainPolicy.ApplicationPolicy.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
    if (-not $chain.Build($signer[0])) {
        throw "Publisher code-signing certificate is not trusted by Windows: $($chain.ChainStatus.Status -join ', ')"
    }
} finally { $chain.Dispose() }
"WINDOWS_SIGNTOOL=$($signTool.FullName)" >> $env:GITHUB_ENV
