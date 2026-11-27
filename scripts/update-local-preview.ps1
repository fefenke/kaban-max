[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]]$Routers = @(),
    [switch]$Status,
    [string]$ReleaseDirectory = '',
    [Parameter(DontShow)][string]$StateDirectory = '',
    [ValidateRange(0, 3600)][int]$DelaySeconds = 120
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
if (!$ReleaseDirectory) { $ReleaseDirectory = Join-Path $project 'dist/auto-routing-r46/release' }
if (!$StateDirectory) { $StateDirectory = Join-Path $project 'dist/router-updates' }
$sshOptions = @('-o', 'ConnectTimeout=15', '-o', 'ConnectionAttempts=1', '-o', 'NumberOfPasswordPrompts=1')

function Invoke-RouterScript([string]$Router, [string]$Script) {
    $Script.Replace("`r", '') | & ssh @sshOptions "root@$Router" "tr -d '\015' | sh"
    if ($LASTEXITCODE -ne 0) { throw "SSH failed ($LASTEXITCODE): $Router" }
}

if ($Status) {
        $last = Get-ChildItem -LiteralPath $StateDirectory -Filter '*.json' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (!$last) { throw 'No saved update run found.' }
    $run = Get-Content -LiteralPath $last.FullName -Raw | ConvertFrom-Json
    foreach ($entry in $run.routers) {
        Write-Host "=== $($entry.router) [$($entry.state)] ==="
        try {
            Invoke-RouterScript $entry.router @"
if test -f $($run.prefix).exit; then printf 'INSTALL_EXIT='; cat $($run.prefix).exit; else echo NOT_STARTED_OR_RUNNING; fi
if test -f $($run.prefix).log; then tail -n 16 $($run.prefix).log; fi
/usr/bin/sing-box version 2>/dev/null | head -n 1
/etc/init.d/kabanmax status
"@
        } catch { Write-Warning $_.Exception.Message }
    }
    return
}

if (!$Routers.Count) { throw 'Specify -Routers with the target router addresses.' }
foreach ($router in $Routers) {
    if ($router -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$') { throw "Invalid router address: $router" }
}
$ReleaseDirectory = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$manifest = Get-Content -LiteralPath (Join-Path $ReleaseDirectory 'release.json') -Raw | ConvertFrom-Json
$core = Get-Content -LiteralPath (Join-Path $ReleaseDirectory 'core-release.json') -Raw | ConvertFrom-Json
if ($manifest.tag -notmatch '^\d+\.\d+\.\d+$' -or $manifest.version -ne $manifest.tag -or $core.tag -ne $manifest.tag -or $core.version -notmatch '^\d+\.\d+\.\d+-r\d+$') {
    throw 'Unexpected release metadata.'
}
$sums = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $ReleaseDirectory 'SHA256SUMS')) {
    if ($line -match '^([a-fA-F0-9]{64})\s+\*?([A-Za-z0-9_.-]+)$') { $sums[$Matches[2]] = $Matches[1] }
}
foreach ($name in $sums.Keys) {
    $path = Join-Path $ReleaseDirectory $name
    if (!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $sums[$name]) {
        throw "Artifact checksum failed: $name"
    }
}
$tag = [string]$manifest.tag
$id = [Guid]::NewGuid().ToString('N')
$prefix = "/tmp/kabanmax-pc-$id"
$stage = "/root/kabanmax-pc-$id"
$assets = "$stage/mirror/fefenke/kaban-max/releases/download/$tag"
$run = [ordered]@{release=$tag; core=$core.version; prefix=$prefix; stage=$stage; routers=@()}
$statePath = Join-Path $StateDirectory "$id.json"
if (!$WhatIfPreference) { [IO.Directory]::CreateDirectory($StateDirectory) | Out-Null }

$runner = @'
#!/bin/sh
stage='__STAGE__'
assets='__ASSETS__'
prefix='__PREFIX__'
mirror_pid=''
finish() {
    result=$?
    trap - EXIT
    printf '%s\n' "$result" > "$prefix.exit"
    test -z "$mirror_pid" || kill "$mirror_pid" 2>/dev/null || true
    rm -f "$assets/"*.apk "$assets/"*.ipk
    exit "$result"
}
trap finish EXIT
sleep __DELAY__
/usr/sbin/uhttpd -f -p 127.0.0.1:18083 -h "$stage/mirror" > "$prefix.mirror.log" 2>&1 &
mirror_pid=$!
sleep 1
kill -0 "$mirror_pid" 2>/dev/null || exit 1
KABANMAX_RELEASE=__TAG__ KABANMAX_REINSTALL=1 KABANMAX_DOWNLOAD_URL=http://127.0.0.1:18083 sh "$assets/install.sh" --lang ru --quiet
exit $?
'@
$runner = $runner.Replace('__STAGE__',$stage).Replace('__ASSETS__',$assets).Replace('__PREFIX__',$prefix).Replace('__DELAY__',[string]$DelaySeconds).Replace('__TAG__',$tag)
$runnerPath = Join-Path $StateDirectory "$id.sh"
if (!$WhatIfPreference) { [IO.File]::WriteAllText($runnerPath, $runner.Replace("`r", '') + "`n", [Text.Encoding]::ASCII) }

try {
    # Finish every transfer before starting any installer.
    foreach ($router in ($Routers | Select-Object -Unique)) {
        if (!$PSCmdlet.ShouldProcess($router, "Stage and autonomously install local $tag / $($core.version)")) { continue }
        $entry = [ordered]@{router=$router; state='preflight'}
        $run.routers += $entry
        $stagedDirectory = $false
        try {
            $info = Invoke-RouterScript $router @'
set -eu
command -v setsid >/dev/null
command -v uhttpd >/dev/null
if command -v apk >/dev/null; then pm=apk; arch=$(cat /etc/apk/arch); else pm=ipk; arch=$(opkg print-architecture | awk '$1=="arch" && $2!="all" && $2!="noarch" && $3+0>p {p=$3+0;a=$2} END{print a}'); fi
variant=$(cat /usr/share/sing-box-kabanmax/variant)
printf 'READY %s %s %s\n' "$pm" "$arch" "$variant"
'@
            $ready = @($info | Where-Object { $_ -match '^READY (apk|ipk) ([A-Za-z0-9_-]+) (base|tiny)$' })
            if (!$ready.Count -or $ready[-1] -notmatch '^READY (apk|ipk) ([A-Za-z0-9_-]+) (base|tiny)$') { throw 'Unsupported architecture, package manager or installed core variant.' }
            $pm=$Matches[1]; $arch=$Matches[2]; $variant=$Matches[3]
            $names = @("kabanmax_${tag}_all.$pm", "luci-app-kabanmax_${tag}_all.$pm", "luci-i18n-kabanmax-ru_${tag}_all.$pm", "sing-box-kabanmax_$($core.version)_${variant}_$arch.$pm", 'install.sh', 'release.json', 'core-release.json', 'SHA256SUMS')
            $files = @($names | ForEach-Object { $path=Join-Path $ReleaseDirectory $_; if (!(Test-Path -LiteralPath $path)) { throw "No local artifact: $_" }; if ($_ -ne 'SHA256SUMS' -and !$sums.ContainsKey($_)) { throw "No checksum: $_" }; $path })
            $needed = [int][Math]::Ceiling((($files | Get-Item | Measure-Object Length -Sum).Sum + 1048576) / 1024)
            Invoke-RouterScript $router "set -e; free_kb=`$(df -k /root | awk 'NR==2{print `$4}'); test `"`$free_kb`" -ge $needed; test ! -e $stage; mkdir -p $assets" | Out-Null
            $stagedDirectory = $true
            & scp -O @sshOptions @files $runnerPath "root@${router}:$assets/"
            if ($LASTEXITCODE -ne 0) { throw 'Package transfer failed.' }
            $verify = @($names | Where-Object { $_ -ne 'SHA256SUMS' } | ForEach-Object { "test `"`$(sha256sum $assets/$_ | cut -d ' ' -f 1)`" = '$($sums[$_])'" }) -join "`n"
            Invoke-RouterScript $router "set -e`n$verify`nmv $assets/$id.sh $stage/run.sh" | Out-Null
            $entry.state='staged'
            Write-Host "Staged: $router ($variant/$arch)"
        } catch {
            $entry.state='staging_failed'
            Write-Warning "$router : $($_.Exception.Message)"
            if ($stagedDirectory) {
                try { Invoke-RouterScript $router "test ! -d $assets || rm -f $assets/*.apk $assets/*.ipk" | Out-Null }
                catch { Write-Warning "$router : could not clean partial staging packages at $assets" }
            }
        }
        $run | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8
    }
    foreach ($entry in $run.routers) {
        if ($entry.state -ne 'staged') { continue }
        try {
            Invoke-RouterScript $entry.router "setsid sh $stage/run.sh </dev/null >$prefix.log 2>&1 &" | Out-Null
            $entry.state='launched'
            Write-Host "Launched: $($entry.router); installer starts in $DelaySeconds seconds"
        } catch {
            $entry.state='launch_unconfirmed'
            Write-Warning "$($entry.router): launch not confirmed; use -Status before retrying."
        }
        $run | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8
    }
} finally {
    if (Test-Path -LiteralPath $runnerPath) { Remove-Item -LiteralPath $runnerPath -Force }
}
if (!$WhatIfPreference) { Write-Host ('Status: powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& ''{0}'' -Status"' -f $PSCommandPath.Replace("'", "''")) }
