[CmdletBinding()]
param(
    [string]$Pubspec = (Join-Path $PSScriptRoot "..\app\pubspec.yaml"),
    [string]$GitHubEnv = $env:GITHUB_ENV,
    [string]$GitHubOutput = $env:GITHUB_OUTPUT
)

$ErrorActionPreference = "Stop"

$Pubspec = [System.IO.Path]::GetFullPath($Pubspec)
if (-not (Test-Path -LiteralPath $Pubspec -PathType Leaf)) {
    throw "Flutter pubspec was not found: $Pubspec"
}

$raw = Get-Content -LiteralPath $Pubspec -Raw
$matches = [regex]::Matches(
    $raw,
    '(?m)^version:\s*(?<version>(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))(?:\+(?<build>(?:0|[1-9]\d*)))?\s*$'
)
if ($matches.Count -ne 1) {
    throw "app/pubspec.yaml must contain exactly one stable SemVer version (major.minor.patch with optional numeric build metadata)"
}

$uiVersion = $matches[0].Groups['version'].Value
$uiBuildNumber = $matches[0].Groups['build'].Value

if (-not [string]::IsNullOrWhiteSpace($GitHubEnv)) {
    Add-Content -LiteralPath $GitHubEnv -Value "UI_VERSION=$uiVersion" -Encoding utf8
    Add-Content -LiteralPath $GitHubEnv -Value "UI_BUILD_NUMBER=$uiBuildNumber" -Encoding utf8
}
if (-not [string]::IsNullOrWhiteSpace($GitHubOutput)) {
    Add-Content -LiteralPath $GitHubOutput -Value "version=$uiVersion" -Encoding utf8
    Add-Content -LiteralPath $GitHubOutput -Value "build_number=$uiBuildNumber" -Encoding utf8
}

Write-Output "UI_VERSION=$uiVersion"
Write-Output "UI_BUILD_NUMBER=$uiBuildNumber"
