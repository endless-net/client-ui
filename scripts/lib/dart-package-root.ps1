function Resolve-DartPackageRootUri([string]$PackageConfig, [string]$RootUri) {
    $resolved = [Uri]$RootUri
    if (-not $resolved.IsAbsoluteUri) {
        $resolved = [Uri]::new([Uri][IO.Path]::GetFullPath($PackageConfig), $resolved)
    }
    if (-not $resolved.IsFile) {
        throw "Dart package does not use a local resolved root"
    }
    return $resolved
}
