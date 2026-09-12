$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/dart-package-root.ps1")
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$config = Join-Path $repo "app/.dart_tool/package_config.json"
$expected = [IO.Path]::GetFullPath((Join-Path $repo "packages/local_client_rpc"))
foreach ($inputUri in @("../../packages/local_client_rpc/", ([Uri]$expected).AbsoluteUri)) {
    $actual = (Resolve-DartPackageRootUri $config $inputUri).LocalPath.TrimEnd([char[]]"\/")
    if ($actual -ne $expected) { throw "Dart package root resolution changed" }
}
foreach ($inputUri in @("https://example.invalid/package", "ftp://example.invalid/package")) {
    $rejected = $false
    try { $null = Resolve-DartPackageRootUri $config $inputUri } catch { $rejected = $true }
    if (-not $rejected) { throw "Non-file package URI accepted" }
}
$rootLicense = (Get-Content (Join-Path $repo "LICENSE") -Raw).Replace("`r`n", "`n").Trim()
$packageLicense = (Get-Content (Join-Path $repo "packages/local_client_rpc/LICENSE") -Raw).Replace("`r`n", "`n").Trim()
if ($rootLicense -cne $packageLicense) { throw "Local Dart package license differs from repository" }
Write-Output "Dart package root and license regression checks passed"
