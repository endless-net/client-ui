[CmdletBinding()]
param(
    [switch]$AllFlutterTests
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$workDir = Join-Path $tempRoot ("endlessnet-ui-e2e-" + [guid]::NewGuid().ToString("N"))
$emulator = Join-Path $workDir "endlessnet-service-emulator.exe"
$previousEmulator = $env:ENDLESSNET_SERVICE_EMULATOR
$hadPreviousEmulator = Test-Path Env:\ENDLESSNET_SERVICE_EMULATOR

New-Item -ItemType Directory -Path $workDir | Out-Null
try {
    Push-Location $repoRoot
    try {
        & go build -o $emulator ./tools/service-emulator/cmd/endlessnet-service-emulator
        if ($LASTEXITCODE -ne 0) {
            throw "service emulator build failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    $env:ENDLESSNET_SERVICE_EMULATOR = $emulator
    Push-Location (Join-Path $repoRoot "app")
    try {
        if ($AllFlutterTests) {
            & flutter test
        }
        else {
            & flutter test test/service_emulator_e2e_test.dart
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter service-emulator tests failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    if ($hadPreviousEmulator) {
        $env:ENDLESSNET_SERVICE_EMULATOR = $previousEmulator
    }
    else {
        Remove-Item Env:\ENDLESSNET_SERVICE_EMULATOR -ErrorAction SilentlyContinue
    }

    $resolvedWorkDir = [System.IO.Path]::GetFullPath($workDir)
    if ($resolvedWorkDir.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedWorkDir)) {
        Remove-Item -LiteralPath $resolvedWorkDir -Recurse -Force
    }
}
