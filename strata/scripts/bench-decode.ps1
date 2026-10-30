<#
    Measure decode speed for one or more environment-variable arms against the
    same preset, interleaved so a slow patch of the machine hits every arm.

    Why the sequence, not per-arm blocks: the first run on a fresh engine is
    always slower (the expert cache has not seen real routing yet). Running
    A B A B lets each arm act as the other's warm-up, and the median of the
    second pair onward is what gets compared.

    Usage:  .\bench-decode.ps1
            .\bench-decode.ps1 -Tier 64k -Rounds 5
            .\bench-decode.ps1 -Arms @{ baseline=@{}; attn=@{STRATA_ATTN_DAILY='1'} }
#>
param(
    [string]$Tier = '64k',
    [int]$Rounds = 4,          # measured rounds per arm (after warm-up)
    [int]$Warmup = 1,
    [hashtable]$Arms = @{},
    [string]$Prompt = 'Write a Python function that merges two sorted lists into one sorted list, then explain its time and space complexity in two sentences.',
    [int]$MaxTokens = 200
)

$ErrorActionPreference = 'Continue'
$HERE = $PSScriptRoot
# STRATA_HOME = the Strata install dir (the one holding terminal\, models\, patches\).
# Set it once per shell, e.g.  $env:STRATA_HOME = 'D:\llm\Strata'
if (-not $env:STRATA_HOME) { throw 'STRATA_HOME is not set: point it at the Strata install directory.' }
$STRATA = Join-Path $env:STRATA_HOME 'terminal\current\bin\strata.cmd'
if (-not (Test-Path -LiteralPath $STRATA)) { throw "strata.cmd not found under $env:STRATA_HOME" }
$env:PYTHONUTF8 = '1'

# `--preset` takes the saved preset's NAME, not the tier key the launcher script
# uses ("IQ2_XS 64K", not "64k"). Passing the key straight through is what made
# every arm report "launch failed".
$PRESET_NAMES = @{
    '32k' = 'IQ2_XS 32K'; '64k' = 'IQ2_XS 64K'
    '128k' = 'IQ2_XS 128K'; '256k' = 'IQ2_XS 256K'
}
$Preset = if ($PRESET_NAMES.ContainsKey($Tier)) { $PRESET_NAMES[$Tier] } else { $Tier }

if ($Arms.Count -eq 0) {
    $Arms = [ordered]@{
        'baseline' = @{}
        'ATTN_DAILY' = @{ STRATA_ATTN_DAILY = '1' }
        'QSA_ROWS' = @{ STRATA_QSA_ROWS = '1' }
        'B6_MMVQ_ROWS' = @{ STRATA_B6_MMVQ_ROWS = '1' }
    }
}
$names = @($Arms.Keys)

$data = @{}
foreach ($n in $names) { $data[$n] = @() }

function Wait-Healthy([int]$timeoutS = 180) {
    # The engine loads a 33 GiB expert arena before it answers; poll /health
    # rather than trusting the launcher's last line.
    $deadline = (Get-Date).AddSeconds($timeoutS)
    while ((Get-Date) -lt $deadline) {
        $saved = @{ H = $env:HTTP_PROXY; S = $env:HTTPS_PROXY }
        $env:HTTP_PROXY = ''; $env:HTTPS_PROXY = ''
        try {
            $h = Invoke-RestMethod -Uri 'http://127.0.0.1:8080/health' -TimeoutSec 4
            if ($h.status -eq 'ok' -and $h.loaded) { return $true }
        } catch { }
        finally {
            $env:HTTP_PROXY = $saved.H; $env:HTTPS_PROXY = $saved.S
        }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Start-Arm([hashtable]$envVars) {
    # A server left over from the previous arm would make `--restart` skip the
    # load, and then the new env vars would never reach the engine.
    & $STRATA launch --stop 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    foreach ($k in $envVars.Keys) { Set-Item -Path "env:$k" -Value $envVars[$k] }
    $null = & $STRATA launch --preset $Preset --restart --no-tui 2>&1 | Out-String
    foreach ($k in $envVars.Keys) { Remove-Item -Path "env:$k" -ErrorAction SilentlyContinue }
    return (Wait-Healthy)
}

function Measure-Decode {
    $body = @{
        messages = @(@{ role = 'user'; content = $Prompt })
        max_tokens = $MaxTokens
        temperature = 0
        stream = $false
    } | ConvertTo-Json -Depth 5 -Compress
    $tmp = Join-Path $env:TEMP ("d-" + [guid]::NewGuid().ToString('N').Substring(0,8) + ".json")
    $body | Set-Content -LiteralPath $tmp -Encoding UTF8 -NoNewline
    $null = curl.exe -sS --noproxy '*' --max-time 600 -X POST 'http://127.0.0.1:8080/v1/chat/completions' `
        -H 'Content-Type: application/json' --data-binary "@$tmp" -o "$tmp.out" 2>&1
    $tps = $null
    try {
        $j = Get-Content -Raw -LiteralPath "$tmp.out" | ConvertFrom-Json
        $tps = [double]$j.timings.predicted_per_second
    } catch { }
    Remove-Item -LiteralPath $tmp, "$tmp.out" -Force -ErrorAction SilentlyContinue
    return $tps
}

# the arms run in a fixed rotation; the order shifts by one each round so
# position-in-round is not confounded with the arm
$measured = @{}
foreach ($n in $names) { $measured[$n] = @() }

for ($r = 1; $r -le ($Warmup + $Rounds); $r++) {
    $order = @()
    for ($i = 0; $i -lt $names.Count; $i++) { $order += $names[($i + $r - 1) % $names.Count] }
    foreach ($n in $order) {
        if (-not (Start-Arm $Arms[$n])) { Write-Host "  $n : launch failed" -ForegroundColor Red; continue }
        $t = Measure-Decode
        if ($null -eq $t) { Write-Host "  $n : no timings" -ForegroundColor Red; continue }
        $tag = if ($r -le $Warmup) { 'warm' } else { 'meas' }
        Write-Host ("  round {0,2} {1,-14} {2,6:N1} tok/s  ({3})" -f $r, $n, $t, $tag)
        if ($r -gt $Warmup) { $measured[$n] += $t }
    }
}

& $STRATA launch --stop 2>&1 | Out-Null

Write-Host ''
Write-Host ('=' * 62) -ForegroundColor Green
$med = @{}
foreach ($n in $names) {
    $a = $measured[$n]
    if (-not $a.Count) { Write-Host ("  {0,-16} no data" -f $n); continue }
    $s = $a | Sort-Object
    $m = if ($s.Count % 2) { $s[[int]($s.Count/2)] } else { ($s[$s.Count/2-1] + $s[$s.Count/2]) / 2 }
    $med[$n] = $m
    Write-Host ("  {0,-16} median {1,6:N1}  range {2:N1}-{3:N1}  n={4}" -f $n, $m, $s[0], $s[-1], $a.Count)
}
if ($med.ContainsKey('baseline')) {
    Write-Host ''
    foreach ($n in $names) {
        if ($n -eq 'baseline' -or -not $med.ContainsKey($n)) { continue }
        $pct = ($med[$n] - $med['baseline']) / $med['baseline'] * 100
        Write-Host ("  {0,-16} {1:+0.0;-0.0}% vs baseline" -f $n, $pct)
    }
}
