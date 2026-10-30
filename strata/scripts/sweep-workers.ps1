<#
    Sweep --pool-workers and record both the decode speed and how badly the
    machine's scheduler suffers while the engine is busy.

    The second number is the point: at the default (one worker per physical
    core) the run queue reached 131 and a trivial thread waited 187 ms, which
    is what makes typing and scrolling stall. Fewer workers leave cores free.

    Usage:  .\sweep-workers.ps1
#>
param(
    [int[]]$Counts = @(4, 6, 8, 10, 12, 15),
    [string]$Tier = '256k'
)

$ErrorActionPreference = 'Continue'
$HERE = $PSScriptRoot
# STRATA_HOME = the Strata install dir (the one holding terminal\, models\, patches\).
# Set it once per shell, e.g.  $env:STRATA_HOME = 'D:\llm\Strata'
if (-not $env:STRATA_HOME) { throw 'STRATA_HOME is not set: point it at the Strata install directory.' }
$STRATA = Join-Path $env:STRATA_HOME 'terminal\current\bin\strata.cmd'
if (-not (Test-Path -LiteralPath $STRATA)) { throw "strata.cmd not found under $env:STRATA_HOME" }
$PRESET_DIR = Join-Path $env:APPDATA 'Strata\launch-presets'
$SCRATCH = Join-Path $PRESET_DIR 'bench-workers.json'
$PROBE = Join-Path $HERE 'bench-ui-lag.py'
$env:PYTHONUTF8 = '1'

$rows = @()
foreach ($n in $Counts) {
    $base = Get-Content -Raw -LiteralPath (Join-Path $PRESET_DIR ("iq2_xs-{0}.json" -f $Tier)) | ConvertFrom-Json
    $base.name = 'BENCH WORKERS'
    $extra = [ordered]@{}
    if ($base.extra) { $base.extra.PSObject.Properties | ForEach-Object { $extra[$_.Name] = $_.Value } }
    $extra['--pool-workers'] = "$n"
    $base.extra = $extra
    ($base | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $SCRATCH -Encoding UTF8

    & $STRATA launch --stop 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    $null = & $STRATA launch --preset 'BENCH WORKERS' --restart --no-tui 2>&1 | Out-String

    $ok = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 3
        $saved = $env:HTTP_PROXY; $env:HTTP_PROXY = ''
        try { $h = Invoke-RestMethod 'http://127.0.0.1:8080/health' -TimeoutSec 4
              if ($h.status -eq 'ok' -and $h.loaded) { $ok = $true; break } } catch { }
        finally { $env:HTTP_PROXY = $saved }
    }
    if (-not $ok) { Write-Host "workers $n : engine never became ready" -ForegroundColor Red; continue }

    $out = python -I $PROBE "$n workers" 8080 2>&1 | Out-String
    $lat  = [regex]::Match($out, 'probe median ([\d.]+) ms  max')
    $busy = [regex]::Match($out, 'busy:   queue ([\d.]+).*probe median ([\d.]+) ms')
    $tps  = [regex]::Match($out, 'decode ([\d.]+) tok/s')
    $wall = [regex]::Match($out, 'tok in ([\d.]+) s')
    if ($busy.Success) {
        $row = [pscustomobject]@{
            Workers = $n
            Queue   = [double]$busy.Groups[1].Value
            Latency = [double]$busy.Groups[2].Value
            Decode  = if ($tps.Success) { [double]$tps.Groups[1].Value } else { 0 }
            Wall    = if ($wall.Success) { [double]$wall.Groups[1].Value } else { 0 }
        }
        $rows += $row
        Write-Host ("  workers {0,2}  queue {1,7:N1}  probe {2,7:N1} ms  decode {3,5:N1} t/s  {4,5:N1} s" -f `
            $n, $row.Queue, $row.Latency, $row.Decode, $row.Wall) -ForegroundColor Cyan
    } else {
        Write-Host "  workers $n : probe produced no parseable result" -ForegroundColor Red
        Write-Host $out
    }
}

& $STRATA launch --stop 2>&1 | Out-Null
Remove-Item -LiteralPath $SCRATCH -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ('=' * 72) -ForegroundColor Green
$rows | Format-Table -AutoSize | Out-String | Write-Host
