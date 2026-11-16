param([string]$BrowserPath = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe')
$ErrorActionPreference = 'Stop'
$uiRoot = Split-Path $PSScriptRoot -Parent
$uiAudit = Join-Path $uiRoot '.local/audit/ui-v2'
New-Item -ItemType Directory -Force -Path $uiAudit | Out-Null
Push-Location (Join-Path $uiRoot 'fe-app-kabanmax')
try {
    & node node_modules/esbuild/bin/esbuild ./tests/browser/formUx.browser.ts --bundle "--outfile=$uiAudit/formUx.browser.js"
    if ($LASTEXITCODE -ne 0) { throw 'Browser fixture build failed' }
} finally { Pop-Location }
Set-Content -LiteralPath (Join-Path $uiAudit 'formUx.html') -Encoding UTF8 -Value '<!doctype html><meta charset="utf-8"><script>window._=s=>s</script><script defer src="formUx.browser.js"></script>'
foreach ($uiCase in @('320','375','768','1280','dark')) {
    $uiWidth = if ($uiCase -eq 'dark') { 375 } else { [int]$uiCase }
    $uiOutput = Join-Path $uiAudit "browser-$uiCase.txt"
    $uiArguments = @('--headless','--disable-gpu','--no-first-run','--disable-background-networking','--disable-extensions','--disable-sync',
        ('"--user-data-dir=' + (Join-Path $uiAudit "edge-$uiCase") + '"'),
        '--dump-dom','--virtual-time-budget=10000',"--window-size=$uiWidth,800",('"' + (Join-Path $uiAudit 'formUx.html') + '"'))
    if ($uiCase -eq 'dark') { $uiArguments += '--force-dark-mode' }
    Start-Process -FilePath $BrowserPath -ArgumentList $uiArguments -WindowStyle Hidden -Wait -RedirectStandardOutput $uiOutput -RedirectStandardError (Join-Path $uiAudit "browser-$uiCase-error.txt")
    if (-not (Select-String -LiteralPath $uiOutput -SimpleMatch '<pre id="result">PASS</pre>' -Quiet)) { throw "Browser case $uiCase failed: $uiOutput" }
    Write-Output "Browser $uiCase PASS"
}
