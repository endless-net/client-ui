[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [Parameter(Mandatory = $true)]
    [string]$ClientCommit,
    [Parameter(Mandatory = $true)]
    [string]$CoreManifestSHA256,
    [string]$Repository = "unng-lab/endlessnet-client-ui",
    [string]$GitHubOutput = $env:GITHUB_OUTPUT,
    [string]$RunnerTemp = $env:RUNNER_TEMP,
    [string]$GitHubCLI = "gh"
)

$ErrorActionPreference = "Stop"

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "invalid release version"
}
if ($ClientCommit -notmatch '^[a-fA-F0-9]{40}$') {
    throw "client commit must be a full SHA"
}
if ($CoreManifestSHA256 -notmatch '^[a-fA-F0-9]{64}$') {
    throw "manifest digest is invalid"
}
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    throw "repository must use owner/name form"
}
if ([string]::IsNullOrWhiteSpace($GitHubOutput)) {
    throw "GitHub output path is required"
}
if ([string]::IsNullOrWhiteSpace($RunnerTemp)) {
    throw "runner temporary directory is required"
}

function Invoke-GitHubCLI {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $previousNativePreference = $PSNativeCommandUseErrorActionPreference
    try {
        # Expected non-zero native exits must be inspected below instead of
        # being promoted to terminating PowerShell errors.
        $PSNativeCommandUseErrorActionPreference = $false
        $output = & $GitHubCLI @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $PSNativeCommandUseErrorActionPreference = $previousNativePreference
    }
    $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $text
    }
}

function Write-NoopOutput {
    param([Parameter(Mandatory = $true)][bool]$Noop)

    $value = $Noop.ToString().ToLowerInvariant()
    Add-Content -LiteralPath $GitHubOutput -Value "noop=$value" -Encoding utf8
    Write-Output "noop=$value"
}

$tag = "v$Version"
$encodedTag = [Uri]::EscapeDataString($tag)
$lookup = Invoke-GitHubCLI -Arguments @(
    "api",
    "--include",
    "--method", "GET",
    "repos/$Repository/releases/tags/$encodedTag"
)

if ($lookup.ExitCode -ne 0) {
    $notFound =
        $lookup.Output -match '(?im)^HTTP/(?:1(?:\.\d)?|2(?:\.0)?)\s+404(?:\s|$)' -or
        $lookup.Output -match '(?i)\(HTTP 404\)\s*$'
    if ($notFound) {
        Write-NoopOutput -Noop $false
        exit 0
    }
    throw "failed to inspect release $tag (gh exit $($lookup.ExitCode)): $($lookup.Output)"
}

$existingDir = Join-Path $RunnerTemp ("existing-release-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $existingDir | Out-Null
$download = Invoke-GitHubCLI -Arguments @(
    "release", "download", $tag,
    "--repo", $Repository,
    "--pattern", "release-provenance.json",
    "--dir", $existingDir
)
if ($download.ExitCode -ne 0) {
    throw "release $tag exists without downloadable provenance: $($download.Output)"
}

$provenancePath = Join-Path $existingDir "release-provenance.json"
if (-not (Test-Path -LiteralPath $provenancePath -PathType Leaf)) {
    throw "release $tag exists without provenance"
}
$existing = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
if ($existing.client.manifest_sha256 -ne $CoreManifestSHA256.ToLowerInvariant()) {
    throw "release $tag already exists for a different core manifest"
}

Write-NoopOutput -Noop $true
