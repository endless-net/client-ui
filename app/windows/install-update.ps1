param(
    [ValidateSet('Info','Install')][string]$Mode = 'Info',
    [string]$Package,
    [string]$ExpectedVersion,
    [string]$ExpectedHash
)
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'endlessnet_client_ui.exe'
try {
    $v = [Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
    $version = @($v.FileMajorPart,$v.FileMinorPart,$v.FileBuildPart) -join '.'
    if ($Mode -eq 'Info') { Write-Output $version; exit 0 }
    if ($ExpectedVersion -cnotmatch '^0\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' -or
        $ExpectedHash -cnotmatch '^[0-9a-f]{64}$' -or [version]$ExpectedVersion -le [version]$version) { throw 'Invalid update' }
    # Hold the exact package against replacement until Windows Installer finishes.
    $held = [IO.File]::Open($Package, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ((Get-FileHash -InputStream $held -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedHash) { throw 'Hash mismatch' }
        $own = Get-AuthenticodeSignature -LiteralPath $exe
        $signature = Get-AuthenticodeSignature -LiteralPath $Package
        if ($own.Status -ne 'Valid' -or $signature.Status -ne 'Valid' -or
            -not $own.SignerCertificate -or -not $signature.SignerCertificate -or
            $own.SignerCertificate.Subject -cne $signature.SignerCertificate.Subject) { throw 'Untrusted publisher' }
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $db = $installer.OpenDatabase($Package, 0)
        foreach ($entry in @(@('ProductVersion', $ExpectedVersion), @('UpgradeCode', '{FA0F488C-9869-47EC-A2B0-F41313F40657}'))) {
            $query = 'SELECT `Value` FROM `Property` WHERE `Property` = ''' + $entry[0] + ''''
            $view = $db.OpenView($query)
            try {
                $view.Execute()
                $record = $view.Fetch()
                if (-not $record -or $record.StringData(1) -cne $entry[1]) { throw 'Wrong package identity' }
            } finally { $view.Close() }
        }
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($db)
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer)
        $arguments = @('/i', ('"' + [IO.Path]::GetFullPath($Package) + '"'), '/norestart')
        $child = Start-Process -FilePath (Join-Path ([Environment]::SystemDirectory) 'msiexec.exe') -ArgumentList $arguments -PassThru -Wait
        try { $result = $child.ExitCode } finally { $child.Dispose() }
    } finally { $held.Dispose() }
    exit $result
} catch {
    # Do not print paths, certificate details or arbitrary native errors into UI.
    exit 1
}
