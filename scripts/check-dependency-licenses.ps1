[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [string]$DartPackageConfig = (Join-Path $PSScriptRoot "..\app\.dart_tool\package_config.json"),
    [string]$Output = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
$DartPackageConfig = [System.IO.Path]::GetFullPath($DartPackageConfig)
$allowed = @("Apache-2.0", "MIT", "BSD-2-Clause", "BSD-3-Clause")

function Find-LicenseFile([string]$Root, [string]$StopAt = "") {
    $current = [System.IO.Path]::GetFullPath($Root)
    $stop = if ([string]::IsNullOrWhiteSpace($StopAt)) { "" } else { [System.IO.Path]::GetFullPath($StopAt) }
    for ($depth = 0; $depth -lt 8; $depth++) {
        $candidate = Get-ChildItem -LiteralPath $current -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^(LICENSE|COPYING)(\..*)?$' } |
            Sort-Object Name |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
        if ($current -eq $stop) {
            break
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
            break
        }
        $current = $parent
    }
    return ""
}

function Resolve-License([string]$Path) {
    $text = Get-Content -LiteralPath $Path -Raw
    if ($text -match 'Apache License\s+Version 2\.0') {
        return "Apache-2.0"
    }
    if ($text -match 'MIT License' -or $text -match 'Permission is hereby granted, free of charge') {
        return "MIT"
    }
    if ($text -match 'Redistribution and use in source and binary forms, with or without') {
        if ($text -match 'Neither the name|names of its contributors may be used to endorse') {
            return "BSD-3-Clause"
        }
        return "BSD-2-Clause"
    }
    return "UNKNOWN"
}

$records = [Collections.Generic.List[object]]::new()

Push-Location $RepoRoot
try {
    $moduleRows = & go list -m -f '{{if not .Main}}{{.Path}}|{{.Version}}|{{.Dir}}{{end}}' all
    if ($LASTEXITCODE -ne 0) {
        throw "go list -m failed"
    }
} finally {
    Pop-Location
}
foreach ($row in $moduleRows) {
    if ([string]::IsNullOrWhiteSpace($row)) {
        continue
    }
    $parts = $row -split '\|', 3
    if ($parts.Count -ne 3 -or [string]::IsNullOrWhiteSpace($parts[2])) {
        throw "Go module metadata is incomplete: $row"
    }
    $licenseFile = Find-LicenseFile $parts[2] $parts[2]
    if ([string]::IsNullOrWhiteSpace($licenseFile)) {
        throw "Go module $($parts[0]) has no license file"
    }
    $license = Resolve-License $licenseFile
    if ($license -notin $allowed) {
        throw "Go module $($parts[0]) uses unsupported license $license"
    }
    $records.Add([pscustomobject]@{
        ecosystem = "go"
        name = $parts[0]
        version = $parts[1]
        license = $license
        license_file = Split-Path -Leaf $licenseFile
    })
}

if (-not (Test-Path -LiteralPath $DartPackageConfig -PathType Leaf)) {
    throw "Dart package configuration is missing; run flutter pub get first"
}
$packageConfig = Get-Content -LiteralPath $DartPackageConfig -Raw | ConvertFrom-Json
$flutterRoot = ([Uri]$packageConfig.flutterRoot).LocalPath
$dartVersions = @{}
Push-Location (Join-Path $RepoRoot "app")
try {
    $dartDeps = (& flutter pub deps --json | ConvertFrom-Json).packages
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub deps failed"
    }
    foreach ($dependency in $dartDeps) {
        $dartVersions[$dependency.name] = $dependency.version
    }
} finally {
    Pop-Location
}

foreach ($package in $packageConfig.packages) {
    if ($package.name -eq "endlessnet") {
        continue
    }
    $rootUri = [Uri]$package.rootUri
    if (-not $rootUri.IsAbsoluteUri -or -not $rootUri.IsFile) {
        throw "Dart package $($package.name) does not use a local resolved root"
    }
    $root = $rootUri.LocalPath
    $stopAt = if ($root.StartsWith($flutterRoot, [StringComparison]::OrdinalIgnoreCase)) { $flutterRoot } else { $root }
    $licenseFile = Find-LicenseFile $root $stopAt
    if ([string]::IsNullOrWhiteSpace($licenseFile)) {
        throw "Dart package $($package.name) has no license file"
    }
    $license = Resolve-License $licenseFile
    if ($license -notin $allowed) {
        throw "Dart package $($package.name) uses unsupported license $license"
    }
    $records.Add([pscustomobject]@{
        ecosystem = "dart"
        name = $package.name
        version = [string]$dartVersions[$package.name]
        license = $license
        license_file = Split-Path -Leaf $licenseFile
    })
}

$ordered = @($records | Sort-Object ecosystem, name)
if (-not [string]::IsNullOrWhiteSpace($Output)) {
    $Output = [System.IO.Path]::GetFullPath($Output)
    $parent = Split-Path -Parent $Output
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $ordered | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Output -Encoding utf8
}

$summary = $ordered | Group-Object license | Sort-Object Name |
    ForEach-Object { "$($_.Name)=$($_.Count)" }
Write-Host "Validated $($ordered.Count) dependency licenses: $($summary -join ', ')"
