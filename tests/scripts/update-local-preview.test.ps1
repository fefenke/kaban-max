$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script = Join-Path $project 'scripts/update-local-preview.ps1'
$state = Join-Path $project ('dist/router-preview-tests/' + [Guid]::NewGuid().ToString('N'))
$global:previewCalls = New-Object System.Collections.Generic.List[string]
$global:previewRunner = ''
$global:previewFailTransfer = $false
$global:previewMetadata = 'READY apk aarch64_cortex-a53 base'

function global:ssh {
    $body = $input | Out-String
    $global:previewCalls.Add('ssh:' + $body)
    $global:LASTEXITCODE = 0
    if ($body.Contains("printf 'READY")) { $global:previewMetadata }
    elseif ($body.Contains('INSTALL_EXIT=')) { 'INSTALL_EXIT=0'; 'sing-box version 1.14.4-r46'; 'running' }
}
function global:scp {
    $global:previewCalls.Add('scp')
    $runner = @($args | Where-Object { $_ -is [string] -and $_.EndsWith('.sh') -and (Test-Path -LiteralPath $_) }) | Select-Object -Last 1
    if (!$runner) { throw 'No runner script in transfer.' }
    $global:previewRunner = [IO.File]::ReadAllText($runner)
    if ($global:previewRunner.Contains("`r")) { throw 'Runner must use LF.' }
    if ($global:previewRunner -match '__[A-Z]+__') { throw 'Unexpanded runner placeholder.' }
    if ($global:previewRunner -match 'setsid sh -c') { throw 'Nested shell command returned.' }
    $global:LASTEXITCODE = 0
    if ($global:previewFailTransfer) { $global:LASTEXITCODE = 1 }
}

& $script -Routers @('192.0.2.1') -StateDirectory $state -WhatIf
if ($global:previewCalls.Count) { throw 'WhatIf accessed routers.' }
& $script -Routers @('192.0.2.1','198.51.100.2','192.0.2.1') -StateDirectory $state -DelaySeconds 0
$records = @(Get-ChildItem -LiteralPath $state -Filter '*.json')
if ($records.Count -ne 1) { throw 'Missing run state.' }
$run = Get-Content -LiteralPath $records[0].FullName -Raw | ConvertFrom-Json
if (@($run.routers).Count -ne 2 -or @($run.routers | Where-Object { $_.state -ne 'launched' }).Count) { throw 'Launch state incorrect.' }
$calls = @($global:previewCalls)
$transfers = @(0..($calls.Count-1) | Where-Object { $calls[$_] -eq 'scp' })
$launches = @(0..($calls.Count-1) | Where-Object { $calls[$_] -match 'ssh:setsid sh ' })
if ($transfers.Count -ne 2 -or $launches.Count -ne 2 -or $transfers[-1] -ge $launches[0]) { throw 'Not all packages transferred before launch.' }
if (!@($calls | Where-Object { $_.Contains('free_kb=$(df') -and $_.Contains('print $4') }).Count) { throw 'Shell quoting changed.' }
& $script -Status -StateDirectory $state

$global:previewCalls.Clear()
$global:previewMetadata='READY ipk aarch64_cortex-a53 tiny'
& $script -Routers @('192.0.2.1') -StateDirectory (Join-Path $state 'tiny') -DelaySeconds 0
if (!@($global:previewCalls | Where-Object { $_.Contains('_tiny_aarch64_cortex-a53.ipk') }).Count) { throw 'Installed tiny/IPK variant was not preserved.' }
$global:previewCalls.Clear()
$global:previewMetadata='READY apk unsupported full'
& $script -Routers @('192.0.2.1') -StateDirectory (Join-Path $state 'unsupported')
if (@($global:previewCalls | Where-Object { $_ -eq 'scp' -or $_ -match 'ssh:setsid sh ' }).Count) { throw 'Unsupported target was changed.' }
$global:previewMetadata='READY apk aarch64_cortex-a53 base'

$stateFailure = Join-Path $state 'failed'
$global:previewCalls.Clear()
$global:previewFailTransfer = $true
& $script -Routers @('192.0.2.1') -StateDirectory $stateFailure
if (@($global:previewCalls | Where-Object { $_ -match 'ssh:setsid sh ' }).Count) { throw 'Failed upload launched installer.' }
if (!@($global:previewCalls | Where-Object { $_ -match 'rm -f /root/kabanmax-pc-' }).Count) { throw 'Partial packages not cleaned.' }
$failureFile = Get-ChildItem -LiteralPath $stateFailure -Filter '*.json' | Select-Object -First 1
$failed = Get-Content -LiteralPath $failureFile.FullName -Raw | ConvertFrom-Json
if ($failed.routers[0].state -ne 'staging_failed') { throw 'Failure was not saved.' }
[IO.File]::WriteAllText((Join-Path $state 'runner.sh'), $global:previewRunner, [Text.Encoding]::ASCII)
Write-Output "PASS: preview, SHA verification, variant selection, two-phase launch, status and upload failure; runner=$state/runner.sh"
