[CmdletBinding()]
param(
    [string]$LockFile = (Join-Path $PSScriptRoot "..\client-core.lock.json"),
    [Parameter(Mandatory = $true)]
    [string]$OutputDir,
    [string]$ExpectedContract = (Join-Path $PSScriptRoot "..\contracts\upstream\client-ipc-v1.openapi.yaml"),
    [string]$GitHubEnv = $env:GITHUB_ENV,
    [string]$GitHubOutput = $env:GITHUB_OUTPUT,
    [string]$GitHubCLI = "gh",
    [string]$AssetSourceDir = ""
)

$ErrorActionPreference = "Stop"

function Assert-SHA256([string]$Value, [string]$Name) {
    if ($Value -cnotmatch '^[0-9a-f]{64}$') {
        throw "$Name must be a lowercase SHA-256 digest"
    }
}

function Assert-Asset(
    [object]$Asset,
    [string]$Key,
    [string]$ExpectedName,
    [string]$ExpectedBaseURL
) {
    if ($null -eq $Asset) {
        throw "client core lock is missing $Key"
    }
    if ($Asset.name -cne $ExpectedName) {
        throw "client core lock $Key has an unexpected asset name"
    }
    if ($Asset.url -cne "$ExpectedBaseURL/$ExpectedName") {
        throw "client core lock $Key does not use the immutable release URL"
    }
    Assert-SHA256 ([string]$Asset.sha256) "client core lock $Key sha256"
}

function Invoke-GitHubCLI([string[]]$Arguments) {
    $previousNativePreference = $PSNativeCommandUseErrorActionPreference
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        $output = & $GitHubCLI @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $PSNativeCommandUseErrorActionPreference = $previousNativePreference
    }
    if ($exitCode -ne 0) {
        throw "GitHub CLI failed (exit $exitCode): $($output -join [Environment]::NewLine)"
    }
    return (($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine).Trim()
}

function Copy-VerifiedAsset(
    [object]$Asset,
    [string]$Destination,
    [string]$Repository,
    [string]$Tag,
    [string]$SourceDir = ""
) {
    if ([string]::IsNullOrWhiteSpace($SourceDir)) {
        Invoke-GitHubCLI @(
            "release", "download", $Tag,
            "--repo", $Repository,
            "--pattern", $Asset.name,
            "--output", $Destination,
            "--clobber"
        ) | Out-Null
    } else {
        $source = Join-Path $SourceDir $Asset.name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "test asset source is missing $($Asset.name)"
        }
        Copy-Item -LiteralPath $source -Destination $Destination -Force
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash.ToLowerInvariant()
    if ($actual -cne $Asset.sha256) {
        throw "client core asset digest mismatch for $($Asset.name)"
    }
}

$LockFile = [System.IO.Path]::GetFullPath($LockFile)
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$ExpectedContract = [System.IO.Path]::GetFullPath($ExpectedContract)
if (-not (Test-Path -LiteralPath $LockFile -PathType Leaf)) {
    throw "client core lock was not found: $LockFile"
}
if (-not (Test-Path -LiteralPath $ExpectedContract -PathType Leaf)) {
    throw "checked-in IPC contract was not found: $ExpectedContract"
}
if (-not [string]::IsNullOrWhiteSpace($AssetSourceDir)) {
    $AssetSourceDir = [System.IO.Path]::GetFullPath($AssetSourceDir)
}

$lock = Get-Content -LiteralPath $LockFile -Raw | ConvertFrom-Json
if ($lock.schema_version -ne 1) {
    throw "unsupported client core lock schema"
}
if ($lock.repository -cne "endless-net/client") {
    throw "client core lock has an unexpected repository"
}
if ($lock.version -cnotmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
    throw "client core lock version must be a stable SemVer"
}
if ($lock.tag -cne "v$($lock.version)") {
    throw "client core lock tag does not match its version"
}
if ($lock.commit -cnotmatch '^[0-9a-f]{40}$') {
    throw "client core lock commit must be a lowercase full SHA"
}

$releaseBase = "https://github.com/$($lock.repository)/releases/download/$($lock.tag)"
Assert-Asset $lock.manifest "manifest" "endlessnet-client_windows_amd64.manifest.json" $releaseBase
Assert-Asset $lock.compliance.license "compliance.license" "LICENSE" $releaseBase
Assert-Asset $lock.compliance.notice "compliance.notice" "NOTICE" $releaseBase
Assert-Asset $lock.compliance.third_party_notices "compliance.third_party_notices" "THIRD_PARTY_NOTICES" $releaseBase
Assert-Asset $lock.compliance.source_sbom "compliance.source_sbom" "source-sbom.spdx.json" $releaseBase

$releaseTarget = Invoke-GitHubCLI @(
    "api",
    "/repos/$($lock.repository)/releases/tags/$($lock.tag)",
    "--jq", ".target_commitish"
)
if ($releaseTarget -cne $lock.commit) {
    throw "client core release target does not match the reviewed lock"
}
$tagObject = Invoke-GitHubCLI @(
    "api",
    "/repos/$($lock.repository)/git/ref/tags/$($lock.tag)",
    "--jq", '.object.type + "|" + .object.sha'
)
$tagObjectParts = $tagObject -split '\|', 2
if ($tagObjectParts.Count -ne 2) {
    throw "client core tag reference is malformed"
}
$tagObjectType = $tagObjectParts[0]
$tagObjectSHA = $tagObjectParts[1]
if ($tagObjectType -eq "tag") {
    $tagObject = Invoke-GitHubCLI @(
        "api",
        "/repos/$($lock.repository)/git/tags/$tagObjectSHA",
        "--jq", '.object.type + "|" + .object.sha'
    )
    $tagObjectParts = $tagObject -split '\|', 2
    if ($tagObjectParts.Count -ne 2) {
        throw "client core annotated tag is malformed"
    }
    $tagObjectType = $tagObjectParts[0]
    $tagObjectSHA = $tagObjectParts[1]
}
if ($tagObjectType -cne "commit" -or $tagObjectSHA -cne $lock.commit) {
    throw "client core tag does not resolve to the reviewed commit"
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$manifestPath = Join-Path $OutputDir "client-core-manifest.json"
Copy-VerifiedAsset $lock.manifest $manifestPath $lock.repository $lock.tag $AssetSourceDir

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schema_version -ne 1 -or $manifest.repository -cne $lock.repository) {
    throw "unsupported client core manifest producer or schema"
}
if ($manifest.version -cne $lock.version -or $manifest.commit -cne $lock.commit) {
    throw "client core manifest does not match the reviewed lock"
}
if ($manifest.target -cne "windows/amd64" -or $manifest.ipc_version -cne "v1") {
    throw "client core manifest target or IPC version mismatch"
}

$clientAsset = [pscustomobject]@{
    name = "endlessnet-client_windows_amd64.exe"
    url = "$releaseBase/endlessnet-client_windows_amd64.exe"
    sha256 = [string]$manifest.artifacts.client.sha256
}
$contractAsset = [pscustomobject]@{
    name = "client-ipc-v1.openapi.yaml"
    url = "$releaseBase/client-ipc-v1.openapi.yaml"
    sha256 = [string]$manifest.artifacts.ipc_contract.sha256
}
Assert-Asset $clientAsset "manifest.artifacts.client" $clientAsset.name $releaseBase
Assert-Asset $contractAsset "manifest.artifacts.ipc_contract" $contractAsset.name $releaseBase
if ($manifest.artifacts.client.name -cne $clientAsset.name -or
    $manifest.artifacts.client.url -cne $clientAsset.url -or
    $manifest.artifacts.ipc_contract.name -cne $contractAsset.name -or
    $manifest.artifacts.ipc_contract.url -cne $contractAsset.url) {
    throw "client core manifest contains unexpected artifact metadata"
}

$clientPath = Join-Path $OutputDir $clientAsset.name
$contractPath = Join-Path $OutputDir $contractAsset.name
Copy-VerifiedAsset $clientAsset $clientPath $lock.repository $lock.tag $AssetSourceDir
Copy-VerifiedAsset $contractAsset $contractPath $lock.repository $lock.tag $AssetSourceDir

$checkedInContract = [System.IO.File]::ReadAllText($ExpectedContract).Replace("`r`n", "`n")
$releasedContract = [System.IO.File]::ReadAllText($contractPath).Replace("`r`n", "`n")
if ($checkedInContract -cne $releasedContract) {
    throw "checked-in IPC contract does not match the reviewed client core release"
}

$compliancePaths = [ordered]@{}
foreach ($entry in @(
    @{ Key = "license"; Asset = $lock.compliance.license },
    @{ Key = "notice"; Asset = $lock.compliance.notice },
    @{ Key = "third_party_notices"; Asset = $lock.compliance.third_party_notices },
    @{ Key = "source_sbom"; Asset = $lock.compliance.source_sbom }
)) {
    $destination = Join-Path $OutputDir $entry.Asset.name
    Copy-VerifiedAsset $entry.Asset $destination $lock.repository $lock.tag $AssetSourceDir
    $compliancePaths[$entry.Key] = $destination
}

$outputs = [ordered]@{
    core_version = $lock.version
    client_commit = $lock.commit
    manifest_url = $lock.manifest.url
    manifest_sha256 = $lock.manifest.sha256
    manifest = $manifestPath
    client_exe = $clientPath
    ipc_contract = $contractPath
    license = $compliancePaths.license
    notice = $compliancePaths.notice
    third_party_notices = $compliancePaths.third_party_notices
    source_sbom = $compliancePaths.source_sbom
}

if (-not [string]::IsNullOrWhiteSpace($GitHubEnv)) {
    foreach ($entry in @(
        "CORE_VERSION=$($outputs.core_version)",
        "CLIENT_COMMIT=$($outputs.client_commit)",
        "CORE_MANIFEST_URL=$($outputs.manifest_url)",
        "CORE_MANIFEST_SHA256=$($outputs.manifest_sha256)"
    )) {
        Add-Content -LiteralPath $GitHubEnv -Value $entry -Encoding utf8
    }
}
if (-not [string]::IsNullOrWhiteSpace($GitHubOutput)) {
    foreach ($entry in $outputs.GetEnumerator()) {
        Add-Content -LiteralPath $GitHubOutput -Value "$($entry.Key)=$($entry.Value)" -Encoding utf8
    }
}

Write-Host "CoreVersion=$($outputs.core_version)"
Write-Host "ClientCommit=$($outputs.client_commit)"
Write-Host "Manifest=$manifestPath"
Write-Host "ClientExe=$clientPath"
Write-Host "IPCContract=$contractPath"
Write-Host "Compliance=$OutputDir"
