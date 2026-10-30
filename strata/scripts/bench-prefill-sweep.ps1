<#
    Sweep prompt-chunk sizes against the 256K preset, measuring only the
    prefill ("read in") speed on a fresh 8K prompt.

    Why a scratch preset: `strata launch` writes the preset's `extra` args into
    the engine command line, so varying one of them means varying the preset.
    The original 256K preset is never modified - a copy named BENCH PREFILL is
    written, used, and removed at the end.

    Why the same prompt each time: a differing prompt would change the expert
    routing per chunk and add noise. The bench script appends a nonce, so the
    prefix cache cannot serve it and every run reads the whole prompt.

    Usage:  .\bench-prefill-sweep.ps1                    2048, 4096, 8192
            .\bench-prefill-sweep.ps1 -Chunks 2048,8192,16384
            .\bench-prefill-sweep.ps1 -ExtraEnv @{STRATA_EMB_REUSE_ACCOUNT='1'}
#>
param(
    [int[]]$Chunks = @(2048, 4096, 8192),
    [hashtable]$ExtraEnv = @{},
    [int]$Tokens = 8000,
    [int]$Rounds = 3
)

$ErrorActionPreference = 'Continue'
$HERE = $PSScriptRoot
# STRATA_HOME = the Strata install dir (the one holding terminal\, models\, patches\).
# Set it once per shell, e.g.  $env:STRATA_HOME = 'D:\llm\Strata'
if (-not $env:STRATA_HOME) { throw 'STRATA_HOME is not set: point it at the Strata install directory.' }
$STRATA = Join-Path $env:STRATA_HOME 'terminal\current\bin\strata.cmd'
if (-not (Test-Path -LiteralPath $STRATA)) { throw "strata.cmd not found under $env:STRATA_HOME" }
$BENCH = Join-Path $HERE 'bench-prefill.py'
$PRESET_DIR = Join-Path $env:APPDATA 'Strata\launch-presets'
$SCRATCH = Join-Path $PRESET_DIR 'bench-prefill.json'
$env:PYTHONUTF8 = '1'

function Set-Scratch([int]$chunk) {
    $base = Get-Content -Raw -LiteralPath (Join-Path $PRESET_DIR 'iq2_xs-256k.json') | ConvertFrom-Json
    $base.name = 'BENCH PREFILL'
    $extra = [ordered]@{}
    if ($base.extra) { $base.extra.PSObject.Properties | ForEach-Object { $extra[$_.Name] = $_.Value } }
    $extra['--prefill'] = "$chunk"
    $base.extra = $extra
    ($base | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $SCRATCH -Encoding UTF8
}

$results = @()

foreach ($chunk in $Chunks) {
    Write-Host ''
    Write-Host ("--- prefill chunk {0} ---" -f $chunk) -ForegroundColor Cyan

    & $STRATA launch --stop 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    Set-Scratch $chunk

    foreach ($k in $ExtraEnv.Keys) { Set-Item -Path "env:$k" -Value $ExtraEnv[$k] }
    $out = & $STRATA launch --preset 'BENCH PREFILL' --restart --no-tui 2>&1 | Out-String
    foreach ($k in $ExtraEnv.Keys) { Remove-Item -Path "env:$k" -ErrorAction SilentlyContinue }

    if ($out -notmatch 'Strata is serving|serving') {
        Write-Host '    launch failed' -ForegroundColor Red
        Write-Host ($out -split "`n" | Select-Object -Last 3)
        continue
    }

    # the first request pays the expert-arena warm-up; measure after it settles
    $null = python -I $BENCH 8080 $Tokens 1 2>&1
    $raw = python -I $BENCH 8080 $Tokens $Rounds 2>&1
    Write-Host $raw

    $m = [regex]::Match($raw -join "`n", 'prefill median ([0-9.]+)')
    if ($m.Success) { $results += [pscustomobject]@{ Chunk = $chunk; Toks = [double]$m.Groups[1].Value } }
}

Remove-Item -LiteralPath $SCRATCH -Force -ErrorAction SilentlyContinue
& $STRATA launch --stop 2>&1 | Out-Null
Remove-Item -LiteralPath $SCRATCH -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ('=' * 50) -ForegroundColor Green
if (-not $results.Count) { Write-Host 'No results.' -ForegroundColor Red; exit 1 }
$best = ($results | Measure-Object -Property Toks -Maximum).Maximum
foreach ($r in $results) {
    $mark = if ($r.Toks -eq $best) { '  <-- best' } else { '' }
    Write-Host ("  chunk {0,6}  {1,8:N1} tok/s  ({2,5:N1}% of best){3}" -f `
        $r.Chunk, $r.Toks, ($r.Toks / $best * 100), $mark)
}
