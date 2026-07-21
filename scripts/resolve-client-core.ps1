param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestUrl,
    [Parameter(Mandatory = $true)]
    [string]$ManifestSHA256,
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [Parameter(Mandatory = $true)]
    [string]$ClientCommit,
    [Parameter(Mandatory = $true)]
    [string]$OutputDir,
    [Parameter(Mandatory = $true)]
    [string]$GitHubToken
)

$ErrorActionPreference = "Stop"

if ($ManifestSHA256 -notmatch '^[a-fA-F0-9]{64}$') {
    throw "manifest_sha256 must be a 64-character hexadecimal digest"
}
if ($ClientCommit -notmatch '^[a-fA-F0-9]{40}$') {
    throw "client_commit must be a full Git commit SHA"
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "version must be a release version without a v prefix"
}

$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$manifestPath = Join-Path $OutputDir "client-core-manifest.json"
$tag = "v$Version"
$manifestAsset = "endlessnet-client_windows_amd64.manifest.json"
$expectedManifestUrl = "https://github.com/unng-lab/endlessnet-client/releases/download/$tag/$manifestAsset"
if ($ManifestUrl -ne $expectedManifestUrl) {
    throw "client core manifest URL is not the immutable client release path"
}
$savedGitHubToken = $env:GH_TOKEN
try {
    $env:GH_TOKEN = $GitHubToken
    $releaseTarget = (& gh api "/repos/unng-lab/endlessnet-client/releases/tags/$tag" --jq ".target_commitish" | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $releaseTarget -ne $ClientCommit.ToLowerInvariant()) {
        throw "client core release target does not match client_commit"
    }
    & gh release download $tag --repo unng-lab/endlessnet-client --pattern $manifestAsset --dir $OutputDir --clobber
    if ($LASTEXITCODE -ne 0) { throw "failed to download the client core manifest" }
    Move-Item -LiteralPath (Join-Path $OutputDir $manifestAsset) -Destination $manifestPath -Force
} finally {
    $env:GH_TOKEN = $savedGitHubToken
}

$actualManifestSHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash.ToLowerInvariant()
if ($actualManifestSHA256 -ne $ManifestSHA256.ToLowerInvariant()) {
    throw "client core manifest digest mismatch"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schema_version -ne 1 -or $manifest.repository -ne "unng-lab/endlessnet-client") {
    throw "unsupported client core manifest producer or schema"
}
if ($manifest.version -ne $Version -or $manifest.commit -ne $ClientCommit.ToLowerInvariant()) {
    throw "client core manifest version or client commit mismatch"
}
if ($manifest.target -ne "windows/amd64" -or $manifest.ipc_version -ne "v1") {
    throw "client core manifest target or IPC version mismatch"
}
if ($manifest.artifacts.client.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
    $manifest.artifacts.ipc_contract.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
    throw "client core manifest has an invalid artifact digest"
}
$clientAsset = "endlessnet-client_windows_amd64.exe"
$contractAsset = "client-ipc-v1.openapi.yaml"
$expectedClientUrl = "https://github.com/unng-lab/endlessnet-client/releases/download/$tag/$clientAsset"
$expectedContractUrl = "https://github.com/unng-lab/endlessnet-client/releases/download/$tag/$contractAsset"
if ($manifest.artifacts.client.name -ne $clientAsset -or
    $manifest.artifacts.ipc_contract.name -ne $contractAsset -or
    $manifest.artifacts.client.url -ne $expectedClientUrl -or
    $manifest.artifacts.ipc_contract.url -ne $expectedContractUrl) {
    throw "client core artifacts do not use immutable client release names and paths"
}

$clientPath = Join-Path $OutputDir $clientAsset
$contractPath = Join-Path $OutputDir $contractAsset
$savedGitHubToken = $env:GH_TOKEN
try {
    $env:GH_TOKEN = $GitHubToken
    & gh release download $tag --repo unng-lab/endlessnet-client --pattern $clientAsset --pattern $contractAsset --dir $OutputDir --clobber
    if ($LASTEXITCODE -ne 0) { throw "failed to download client core artifacts" }
} finally {
    $env:GH_TOKEN = $savedGitHubToken
}
$actualClientSHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $clientPath).Hash.ToLowerInvariant()
if ($actualClientSHA256 -ne $manifest.artifacts.client.sha256.ToLowerInvariant()) {
    throw "client core executable digest mismatch"
}

$actualContractSHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $contractPath).Hash.ToLowerInvariant()
if ($actualContractSHA256 -ne $manifest.artifacts.ipc_contract.sha256.ToLowerInvariant()) {
    throw "IPC contract digest mismatch"
}

Write-Host "Manifest=$manifestPath"
Write-Host "ClientExe=$clientPath"
Write-Host "IPCContract=$contractPath"
