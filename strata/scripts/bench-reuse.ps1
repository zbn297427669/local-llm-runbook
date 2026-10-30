<#
    Measure how much of an agent-style conversation the engine re-reads versus
    reuses, and how long each turn takes.

    Why this shape: the decoder's prefix cache is what makes an agent loop
    affordable - each turn re-sends the whole history and only the new tail
    should be read. The engine log's
        prompt N tokens = R reused + T read in X ms
    line is the direct evidence, so the script grows one conversation over
    several turns and reads those lines back.

    Usage:  .\bench-reuse.ps1 -Tier 256k
            .\bench-reuse.ps1 -Tier 256k -Extra @('--conversation-cache-min-tokens','8000')
#>
param(
    [string]$Tier = '256k',
    [string[]]$Extra = @(),
    [int]$Turns = 6,
    [int]$SeedTokens = 60000
)

$ErrorActionPreference = 'Continue'
$HERE = $PSScriptRoot
# STRATA_HOME = the Strata install dir (the one holding terminal\, models\, patches\).
# Set it once per shell, e.g.  $env:STRATA_HOME = 'D:\llm\Strata'
if (-not $env:STRATA_HOME) { throw 'STRATA_HOME is not set: point it at the Strata install directory.' }
$STRATA = Join-Path $env:STRATA_HOME 'terminal\current\bin\strata.cmd'
if (-not (Test-Path -LiteralPath $STRATA)) { throw "strata.cmd not found under $env:STRATA_HOME" }
$PRESET_DIR = Join-Path $env:APPDATA 'Strata\launch-presets'
$SCRATCH = Join-Path $PRESET_DIR 'bench-reuse.json'
$LOG = Join-Path $env:LOCALAPPDATA 'Strata\launch\bench-reuse.engine.log'
$env:PYTHONUTF8 = '1'

$PRESET_NAMES = @{ '32k'='IQ2_XS 32K'; '64k'='IQ2_XS 64K'; '128k'='IQ2_XS 128K'; '256k'='IQ2_XS 256K' }
$Preset = if ($PRESET_NAMES.ContainsKey($Tier)) { $PRESET_NAMES[$Tier] } else { $Tier }

# ---- scratch preset: the base tier plus whatever this run is testing --------
$base = Get-Content -Raw -LiteralPath (Join-Path $PRESET_DIR ("iq2_xs-{0}.json" -f $Tier)) | ConvertFrom-Json
$base.name = 'BENCH REUSE'
$extraMap = [ordered]@{}
if ($base.extra) { $base.extra.PSObject.Properties | ForEach-Object { $extraMap[$_.Name] = $_.Value } }
for ($i = 0; $i -lt $Extra.Count; $i += 2) { $extraMap[$Extra[$i]] = $Extra[$i + 1] }
$base.extra = $extraMap
($base | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $SCRATCH -Encoding UTF8

Write-Host ("arm: {0}  extra: {1}" -f $Tier, ($Extra -join ' ')) -ForegroundColor Cyan

& $STRATA launch --stop 2>&1 | Out-Null
Start-Sleep -Seconds 3
Remove-Item -LiteralPath $LOG -Force -ErrorAction SilentlyContinue
$null = & $STRATA launch --preset 'BENCH REUSE' --restart --no-tui 2>&1 | Out-String

# wait for the engine to be answering
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 3
    $saved = $env:HTTP_PROXY; $env:HTTP_PROXY = ''
    try { $h = Invoke-RestMethod 'http://127.0.0.1:8080/health' -TimeoutSec 4
          if ($h.status -eq 'ok' -and $h.loaded) { $ok = $true; break } } catch { }
    finally { $env:HTTP_PROXY = $saved }
}
if (-not $ok) { Write-Host 'engine never became ready' -ForegroundColor Red; exit 1 }

# ---- one conversation, grown turn by turn ----------------------------------
$filler = "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs. "
$history = $filler * [int]($SeedTokens * 4 / $filler.Length)
$nonce = [DateTime]::UtcNow.Ticks

for ($t = 1; $t -le $Turns; $t++) {
    $history += "`nTurn $t question: summarise the passage in one short sentence."
    $body = @{
        messages = @(@{ role = 'user'; content = ("[conv $nonce]`n" + $history) })
        max_tokens = 40
        temperature = 0
        stream = $false
    } | ConvertTo-Json -Depth 5 -Compress
    $tmp = Join-Path $env:TEMP ("r-" + [guid]::NewGuid().ToString('N').Substring(0,8) + ".json")
    $body | Set-Content -LiteralPath $tmp -Encoding UTF8 -NoNewline
    $null = curl.exe -sS --noproxy '*' --max-time 900 -X POST 'http://127.0.0.1:8080/v1/chat/completions' `
        -H 'Content-Type: application/json' --data-binary "@$tmp" -o "$tmp.out" 2>&1
    Remove-Item -LiteralPath $tmp, "$tmp.out" -Force -ErrorAction SilentlyContinue
    # grow the conversation the way an agent does
    $history += "`nAssistant: (answer $t)"
}

Start-Sleep -Seconds 2
& $STRATA launch --stop 2>&1 | Out-Null
Remove-Item -LiteralPath $SCRATCH -Force -ErrorAction SilentlyContinue

# ---- read the engine's own accounting --------------------------------------
# The log survives restarts, so parse only the final run: an earlier version of
# this script scanned the whole file and reported stale rows as fresh results.
Write-Host ''
Write-Host 'prompt reuse per turn (engine log, last run only):'
$parser = Join-Path $HERE 'parse-reuse.py'
if (-not (Test-Path -LiteralPath $parser)) { Write-Host "missing $parser" -ForegroundColor Red; exit 1 }
python -I $parser $LOG
