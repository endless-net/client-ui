param(
    [ValidateSet('Info','Request')][string]$Mode = 'Info',
    [string]$Version
)
$ErrorActionPreference = 'Stop'
try {
    if ($Mode -eq 'Info') {
        $exe = Join-Path $PSScriptRoot 'endlessnet_client_ui.exe'
        $v = [Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
        Write-Output (@($v.FileMajorPart,$v.FileMinorPart,$v.FileBuildPart) -join '.')
        exit 0
    }
    if ($Version -cnotmatch '^0\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,4})$') { throw 'Invalid version' }
    $operation = [guid]::NewGuid().ToString('N')
    $reply = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'EndlessNet\Client\updates\status.json'
    & (Join-Path ([Environment]::SystemDirectory) 'sc.exe') start endlessnet-updater $Version $operation | Out-Null
    if ($LASTEXITCODE) { throw 'Cannot request service' }
    $elapsed = [Diagnostics.Stopwatch]::StartNew()
    $accepted = $false
    while ($elapsed.Elapsed.TotalMinutes -lt 20) {
        if (Test-Path -LiteralPath $reply) {
            try { $status = Get-Content -LiteralPath $reply -Raw | ConvertFrom-Json }
            catch { $status = $null }
            if ($status -and $status.operation -ceq $operation) {
                $accepted = $true
                if ($null -ne $status.exit_code) { exit ([int]$status.exit_code) }
            }
        }
        if (-not $accepted -and $elapsed.Elapsed.TotalSeconds -gt 10) { throw 'Update request not accepted' }
        Start-Sleep -Milliseconds 500
    }
} catch {
    exit 1
}
exit 1
