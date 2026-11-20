param(
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$Operation
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release-signature.ps1')
Add-Type -AssemblyName System.Net.Http

function Save-Status($Code) {
    $target = Join-Path $root 'status.json'
    $pending = Join-Path $stage 'status.json'
    $previous = Join-Path $stage 'previous-status.json'
    $json = @{ operation = $Operation; version = $Version; exit_code = $Code } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($pending, $json, [Text.Encoding]::UTF8)
    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        try {
            if ([IO.File]::Exists($target)) { [IO.File]::Replace($pending, $target, $previous) }
            else { [IO.File]::Move($pending, $target) }
            return
        } catch [IO.IOException] { Start-Sleep -Milliseconds 30 }
    }
    throw 'Cannot save update status'
}

function Save-ReleaseAsset([string]$Name, [long]$Maximum) {
    $target = Join-Path $stage $Name
    $uri = [uri]"https://github.com/endless-net/client-ui/releases/download/v$Version/$Name"
    $hosts = @('github.com','release-assets.githubusercontent.com','objects.githubusercontent.com','github-releases.githubusercontent.com')
    $timeout = [Threading.CancellationTokenSource]::new([TimeSpan]::FromMinutes(2))
    try {
        for ($hop = 0; $hop -le 3; $hop++) {
            if ($uri.Scheme -ne 'https' -or $uri.Port -ne 443 -or $uri.UserInfo -or $uri.Fragment -or $uri.Host -notin $hosts) {
                throw 'Unexpected release asset URL'
            }
            $response = $http.GetAsync($uri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead, $timeout.Token).GetAwaiter().GetResult()
            try {
                $status = [int]$response.StatusCode
                if ($status -in 301,302,303,307,308 -and $response.Headers.Location -and $hop -lt 3) {
                    $uri = [uri]::new($uri, $response.Headers.Location)
                    continue
                }
                if ($status -ne 200 -or $response.Content.Headers.ContentLength -gt $Maximum) { throw 'Release asset response rejected' }
                $inputStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                $output = [IO.File]::Open($target, 'CreateNew', 'Write', 'None')
                try {
                    $buffer = [byte[]]::new(65536)
                    $total = 0L
                    while (($size = $inputStream.ReadAsync($buffer, 0, $buffer.Length, $timeout.Token).GetAwaiter().GetResult()) -gt 0) {
                        $total += $size
                        if ($total -gt $Maximum) { throw 'Release asset too large' }
                        $output.Write($buffer, 0, $size)
                    }
                } finally { $output.Dispose() }
                return $target
            } finally { $response.Dispose() }
        }
    } finally { $timeout.Dispose() }
    throw 'Too many release asset redirects'
}

function Assert-InstallerIdentity([string]$Path) {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    try {
        $db = $installer.OpenDatabase($Path, 0)
        try {
            foreach ($entry in @(@('ProductVersion', $Version), @('UpgradeCode', '{FA0F488C-9869-47EC-A2B0-F41313F40657}'))) {
                $quote = [char]96
                $query = ('SELECT {0}Value{0} FROM {0}Property{0} WHERE {0}Property{0} = ''{1}''' -f $quote, $entry[0])
                $view = $db.OpenView($query)
                try {
                    $view.Execute()
                    $record = $view.Fetch()
                    if (-not $record -or $record.StringData(1) -cne $entry[1]) { throw 'Wrong package identity' }
                } finally { $view.Close() }
            }
        } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($db) }
    } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer) }
}

if ($Version -cnotmatch '^0\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,4})$' -or $Operation -cnotmatch '^[0-9a-f]{32}$') { exit 1 }
if (-not [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) { exit 1 }
$root = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'EndlessNet\Client\updates'
try {
    $parent = [IO.DirectoryInfo]::new($root)
    while ($parent) {
        if (!$parent.Exists -or ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid update directory' }
        $parent = $parent.Parent
    }
    $lockFile = Join-Path $root 'operation.lock'
    if ([IO.File]::Exists($lockFile) -and ([IO.File]::GetAttributes($lockFile) -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid lock' }
    $hold = [IO.File]::Open($lockFile, 'OpenOrCreate', 'ReadWrite', 'None')
} catch { exit 1 }

$stage = Join-Path $root ([guid]::NewGuid().ToString('N'))
$result = 1
try {
    $null = New-Item -ItemType Directory -Path $stage
    Save-Status $null
    $exe = Join-Path $PSScriptRoot 'endlessnet_client_ui.exe'
    $v = [Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
    $current = [version](@($v.FileMajorPart,$v.FileMinorPart,$v.FileBuildPart) -join '.')
    if ([version]$Version -le $current) { throw 'Expected a newer version' }
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $http = [Net.Http.HttpClient]::new($handler)
    try {
        $http.DefaultRequestHeaders.UserAgent.ParseAdd('EndlessNet-Updater')
        $manifest = Save-ReleaseAsset 'windows-update.json' 16384
        $proof = Save-ReleaseAsset 'windows-update.p7s' 32768
        $release = Read-SignedRelease $manifest $proof
        if ($release.version -cne $Version) { throw 'Release version mismatch' }
        $package = Save-ReleaseAsset "EndlessNet-v$Version-windows-amd64.msi" $release.msi.size
    } finally { $http.Dispose() }
    $msi = [IO.File]::Open($package, 'Open', 'Read', 'Read')
    try {
        Assert-ReleasePackage $msi $release
        Assert-InstallerIdentity $package
        $arguments = @('/i', ('"' + $package + '"'), '/quiet', '/norestart')
        $child = Start-Process -FilePath (Join-Path ([Environment]::SystemDirectory) 'msiexec.exe') -ArgumentList $arguments -PassThru -Wait -WindowStyle Hidden
        try { $result = $child.ExitCode } finally { $child.Dispose() }
    } finally { $msi.Dispose() }
} finally {
    try {
        if (Test-Path -LiteralPath $stage -PathType Container) {
            try { Save-Status $result }
            finally {
                Get-ChildItem -LiteralPath $stage -File | Remove-Item -Force
                Remove-Item -LiteralPath $stage
            }
        }
    } finally { $hold.Dispose() }
}
