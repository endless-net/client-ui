param(
    [Parameter(Mandatory = $true)]
    [string]$CoreManifest,
    [Parameter(Mandatory = $true)]
    [string]$CoreManifestUrl,
    [Parameter(Mandatory = $true)]
    [string]$CoreManifestSHA256,
    [Parameter(Mandatory = $true)]
    [string]$BuildOutput,
    [Parameter(Mandatory = $true)]
    [string]$Output
)

$ErrorActionPreference = "Stop"
$core = Get-Content -LiteralPath $CoreManifest -Raw | ConvertFrom-Json
$build = Get-Content -LiteralPath $BuildOutput -Raw | ConvertFrom-Json
if ($build.schema_version -ne 2) {
    throw "unsupported UI build metadata schema"
}
if ($core.version -ne $build.client.version -or $core.target -ne $build.target) {
    throw "client-core manifest and packaged client metadata do not match"
}
if ($build.version -notmatch '^\d+\.\d+\.\d+$') {
    throw "UI build metadata does not contain a stable SemVer"
}
if ($build.wintun.version -ne "0.14.1" -or
    $build.wintun.archive_sha256 -notmatch '^[0-9a-f]{64}$' -or
    $build.wintun.sha256 -notmatch '^[0-9a-f]{64}$' -or
    $build.wintun.signer_thumbprint -notmatch '^[0-9A-F]{40}$') {
    throw "build metadata does not contain verified Wintun provenance"
}
if ($build.signed -ne $true -or
    $build.signing.mode -notin @("temporary-self-signed", "public-authenticode") -or
    $build.signing.certificate_thumbprint -notmatch '^[0-9A-F]{40}$') {
    throw "build metadata does not contain a valid release-signing identity"
}
if ($build.signing.mode -eq "temporary-self-signed" -and $build.signing.publicly_trusted -ne $false) {
    throw "temporary self-signed release metadata must not claim public trust"
}

$provenance = [ordered]@{
    schema_version = 2
    version = $build.version
    target = $core.target
    ipc_version = $core.ipc_version
    client = [ordered]@{
        version = $core.version
        repository = $core.repository
        commit = $core.commit
        manifest_url = $CoreManifestUrl
        manifest_sha256 = $CoreManifestSHA256.ToLowerInvariant()
        executable_sha256 = $core.artifacts.client.sha256
        ipc_contract_sha256 = $core.artifacts.ipc_contract.sha256
    }
    ui = [ordered]@{
        version = $build.version
        repository = "endless-net/client-ui"
        commit = $build.ui_commit
    }
    signing = [ordered]@{
        mode = $build.signing.mode
        certificate_thumbprint = $build.signing.certificate_thumbprint
        publicly_trusted = $build.signing.publicly_trusted
        smartscreen_reputation = $(if ($build.signing.mode -eq "temporary-self-signed") { "not-provided" } else { "not-asserted" })
    }
    artifacts = [ordered]@{
        client = [ordered]@{
            unsigned_sha256 = $build.client.unsigned_sha256
            signed_sha256 = $build.client.signed_sha256
        }
        wintun = [ordered]@{
            version = $build.wintun.version
            archive_sha256 = $build.wintun.archive_sha256
            sha256 = $build.wintun.sha256
            signer_thumbprint = $build.wintun.signer_thumbprint
        }
        app = [ordered]@{
            unsigned_sha256 = $build.app.unsigned_sha256
            signed_sha256 = $build.app.signed_sha256
        }
        msi = [ordered]@{
            unsigned_sha256 = $build.msi.unsigned_sha256
            signed_sha256 = $build.msi.signed_sha256
        }
    }
}
$provenance | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output -Encoding utf8
