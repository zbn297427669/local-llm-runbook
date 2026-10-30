<#
    Compare the conversation-cache options on the same alternating-conversation
    workload, each with a fresh engine.

    The arms answer one question: what budget does the engine actually end up
    with, and does it stop the two conversations from evicting each other?

      A  auto (no flag)                    - what it sizes for itself
      B  auto + a lower parking floor      - does the floor change the answer
      C  fixed 4096 MiB
      D  fixed 6144 MiB

    Usage:  .\bench-convcache.ps1
#>
param(
    [string]$Tier = '256k',
    [int]$Rounds = 5
)

$ErrorActionPreference = 'Continue'
$HERE = $PSScriptRoot
# STRATA_HOME = the Strata install dir (the one holding terminal\, models\, patches\).
# Set it once per shell, e.g.  $env:STRATA_HOME = 'D:\llm\Strata'
if (-not $env:STRATA_HOME) { throw 'STRATA_HOME is not set: point it at the Strata install directory.' }
$STRATA = Join-Path $env:STRATA_HOME 'terminal\current\bin\strata.cmd'
if (-not (Test-Path -LiteralPath $STRATA)) { throw "strata.cmd not found under $env:STRATA_HOME" }
$PRESET_DIR = Join-Path $env:APPDATA 'Strata\launch-presets'
$PROBE = Join-Path $HERE 'probe-alternate.py'
$env:PYTHONUTF8 = '1'

$PRESET_NAMES = @{ '32k'='IQ2_XS 32K'; '64k'='IQ2_XS 64K'; '128k'='IQ2_XS 128K'; '256k'='IQ2_XS 256K' }

$arms = [ordered]@{
    'A auto'        = @{}
    'B auto+floor'  = @{ '--conversation-cache-min-free-mib' = '1024' }
    'C fixed 4096'  = @{ '--conversation-cache-mib' = '4096' }
    'D fixed 6144'  = @{ '--conversation-cache-mib' = '6144' }
}

$results = @()

foreach ($name in $arms.Keys) {
    Write-Host ''
    Write-Host ("=== {0} ===" -f $name) -ForegroundColor Cyan

    $scratch = Join-Path $PRESET_DIR 'bench-conv.json'
    $base = Get-Content -Raw -LiteralPath (Join-Path $PRESET_DIR ("iq2_xs-{0}.json" -f $Tier)) | ConvertFrom-Json
    $base.name = 'BENCH CONV'
    $extra = [ordered]@{}
    if ($base.extra) { $base.extra.PSObject.Properties | ForEach-Object { $extra[$_.Name] = $_.Value } }
    foreach ($k in $arms[$name].Keys) { $extra[$k] = $arms[$name][$k] }
    $base.extra = $extra
    ($base | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $scratch -Encoding UTF8

    & $STRATA launch --stop 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    $null = & $STRATA launch --preset 'BENCH CONV' --restart --no-tui 2>&1 | Out-String

    $ok = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 3
        $saved = $env:HTTP_PROXY; $env:HTTP_PROXY = ''
        try { $h = Invoke-RestMethod 'http://127.0.0.1:8080/health' -TimeoutSec 4
              if ($h.status -eq 'ok' -and $h.loaded) { $ok = $true; break } } catch { }
        finally { $env:HTTP_PROXY = $saved }
    }
    if (-not $ok) { Write-Host '  engine never became ready' -ForegroundColor Red; continue }

    # What this arm actually asked for, read from THIS run's command line.
    # Two traps avoided here: a fixed --conversation-cache-mib prints no
    # "sized from the free RAM" line at all, and the log survives restarts, so
    # matching the decision line reported a previous run's budget for every arm.
    $log = Join-Path $env:LOCALAPPDATA 'Strata\launch\bench-conv.engine.log'
    $cmd = (Select-String -LiteralPath $log -Pattern 'engine started:' | Select-Object -Last 1).Line
    if ($cmd -match '--conversation-cache-mib (\d+)') {
        $decision = "fixed $($Matches[1]) MiB"
    } elseif ($cmd -match '--conversation-cache-min-free-mib (\d+)') {
        $decision = "auto, floor $($Matches[1]) MiB"
    } else {
        $decision = 'auto, default floor'
    }
    Write-Host ("  arm asked for: {0}" -f $decision)

    $out = python -I $PROBE 8080 $Rounds 2>&1 | Out-String
    $m = [regex]::Match($out, 'after warm-up: (\d+)/(\d+) reused >=95%,  (\d+)/(\d+) near-zero')
    $w = [regex]::Match($out, 'time spent re-reading in near-zero requests: ([\d.]+) s')
    if ($m.Success) {
        Write-Host ("  hit {0}/{1}, near-zero {2}/{3}, wasted {4} s" -f `
            $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value, $m.Groups[4].Value,
            $(if ($w.Success) { $w.Groups[1].Value } else { '?' })) -ForegroundColor Green
        $results += [pscustomobject]@{
            Arm = $name
            Budget = $decision
            Hit = "$($m.Groups[1].Value)/$($m.Groups[2].Value)"
            Miss = $m.Groups[3].Value
            Wasted = $(if ($w.Success) { [double]$w.Groups[1].Value } else { -1 })
        }
    } else {
        Write-Host '  probe produced no parseable result' -ForegroundColor Red
        Write-Host $out
    }
}

& $STRATA launch --stop 2>&1 | Out-Null
Remove-Item -LiteralPath (Join-Path $PRESET_DIR 'bench-conv.json') -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ('=' * 70) -ForegroundColor Green
$results | Format-Table -AutoSize | Out-String | Write-Host
