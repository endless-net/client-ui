[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$HostExecutable,
    [switch]$AllFlutterTests
)

$ErrorActionPreference = 'Stop'
$nativeHost = (Resolve-Path -LiteralPath $HostExecutable).ProviderPath
if (-not (Test-Path -LiteralPath $nativeHost -PathType Leaf)) {
    throw 'A built producer client-testserver executable is required'
}
$previousHost = $env:ENDLESSNET_TESTSERVER
$hadPreviousHost = Test-Path Env:\ENDLESSNET_TESTSERVER
try {
    $env:ENDLESSNET_TESTSERVER = $nativeHost
    Push-Location (Join-Path (Split-Path -Parent $PSScriptRoot) 'app')
    try {
        if ($AllFlutterTests) {
            & flutter test --no-pub
        } else {
            & flutter test --no-pub test/client_session_process_test.dart
        }
        if ($LASTEXITCODE -ne 0) { throw 'Native client UI tests failed' }
    } finally { Pop-Location }
} finally {
    if ($hadPreviousHost) {
        $env:ENDLESSNET_TESTSERVER = $previousHost
    } else {
        Remove-Item Env:\ENDLESSNET_TESTSERVER -ErrorAction SilentlyContinue
    }
}
