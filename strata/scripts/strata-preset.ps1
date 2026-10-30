<#
    Pick a Strata preset, restart the model with it, and report the address.

    Why a launcher instead of picking inside CCR: Strata serves one configuration
    at a time and /v1/models reports only that one, with the same id
    (qwen3.8-flash-next-iq2_xs) whatever the context is. CCR therefore cannot
    offer "32K / 64K / 128K" as separate models -- they would need one engine
    each, and 16 GB of VRAM holds one.

    So the context tier is chosen here, before CCR connects. CCR keeps pointing
    at http://127.0.0.1:8080 and picks up the new window on its next probe.

    Place this file directly in $env:STRATA_HOME (the folder holding terminal\,
    models\, patches\) -- it resolves strata.cmd relative to its own location.

    Usage:
        .\strata-preset.ps1                 list the tiers and ask
        .\strata-preset.ps1 128k            start that tier
        .\strata-preset.ps1 -Status         what is serving now
        .\strata-preset.ps1 -Stop           stop, restore the GPU power limit
#>
param(
    [Parameter(Position = 0)]
    [string]$Tier,
    [switch]$Status,
    [switch]$Stop
)

$ErrorActionPreference = 'Stop'
$HERE = $PSScriptRoot

# one engine per tier; the numbers came from measuring this machine
$TIERS = @(
    @{ Key = '32k';  Preset = 'IQ2_XS 32K';  Context = 32768;  Vision = $true;  Note = 'fastest; images on; most RAM headroom' }
    @{ Key = '64k';  Preset = 'IQ2_XS 64K';  Context = 65536;  Vision = $true;  Note = 'default; images on; balanced' }
    @{ Key = '128k'; Preset = 'IQ2_XS 128K'; Context = 131072; Vision = $false; Note = 'long text; images off to save 1.2 GB RAM' }
    @{ Key = '256k'; Preset = 'IQ2_XS 256K'; Context = 262144; Vision = $false; Note = 'full trained window; k8v4 KV' }
)

function Strata([string[]]$StrataArgs) {
    # not $args: that is an automatic variable ($args for the function's own
    # unbound arguments), and naming a parameter that silently repoints it
    $env:PYTHONUTF8 = '1'
    & (Join-Path $HERE 'terminal\current\bin\strata.cmd') @StrataArgs
}

function Show-Tiers {
    Write-Host 'Strata presets on this machine:'
    Write-Host ''
    Write-Host ('  {0,-7} {1,-22} {2,-8} {3,-6} {4}' -f 'KEY', 'PRESET', 'CONTEXT', 'IMAGES', 'NOTE')
    Write-Host ('  {0,-7} {1,-22} {2,-8} {3,-6} {4}' -f '---', '------', '-------', '------', '----')
    foreach ($t in $TIERS) {
        $ctx = '{0}K' -f ([int]($t.Context / 1024))
        $vis = if ($t.Vision) { 'yes' } else { 'no' }
        Write-Host ('  {0,-7} {1,-22} {2,-8} {3,-6} {4}' -f $t.Key, $t.Preset, $ctx, $vis, $t.Note)
    }
    Write-Host ''
}

if ($Status) {
    # loopback must skip any proxy: -NoProxy is not on Windows PowerShell 5.1,
    # so clear the proxy for this request only
    $h = $null
    try {
        $savedHttp = $env:HTTP_PROXY; $savedHttps = $env:HTTPS_PROXY
        $env:HTTP_PROXY = ''; $env:HTTPS_PROXY = ''
        $h = Invoke-RestMethod -Uri 'http://127.0.0.1:8080/health' -TimeoutSec 5
    } catch { }
    finally {
        $env:HTTP_PROXY = $savedHttp; $env:HTTPS_PROXY = $savedHttps
    }
    if (-not $h) { Write-Host 'Nothing is serving on 127.0.0.1:8080.'; exit 0 }
    Write-Host ("Serving {0}" -f $h.model)
    Write-Host ("Context  {0:N0} tokens ({1}K)" -f $h.max_context, [int]($h.max_context / 1024))
    Write-Host ("Images   {0}" -f $(if ($h.images) { 'yes' } else { 'no' }))
    Write-Host ("Address  http://127.0.0.1:8080   (Anthropic clients: no /v1)")
    exit 0
}

if ($Stop) {
    Strata @('launch', '--stop')
    exit $LASTEXITCODE
}

Show-Tiers

if (-not $Tier) {
    $Tier = Read-Host 'Which one? (32k/64k/128k/128kv, Enter to cancel)'
    if ([string]::IsNullOrWhiteSpace($Tier)) { Write-Host 'Cancelled.'; exit 0 }
}
$Tier = $Tier.Trim().ToLower()
$pick = $TIERS | Where-Object { $_.Key -eq $Tier } | Select-Object -First 1
if (-not $pick) {
    Write-Host "No tier called '$Tier'. Use one of: $((($TIERS | ForEach-Object { $_.Key }) -join ', '))" -ForegroundColor Yellow
    exit 2
}

Write-Host ''
Write-Host ("Starting {0} ({1}K, images {2})..." -f $pick.Preset, [int]($pick.Context / 1024), $(if ($pick.Vision) { 'on' } else { 'off' }))
Write-Host ''

# No GPU power cap. A 200 W cap was tried against the USB disconnect problem and did not
# stop it (13 events were logged while it was in force), so the card runs at its own 350 W
# default and no UAC prompt appears. The STRATA_GPU_POWER_LIMIT support is still installed
# in the Terminal; set that variable by hand to experiment.
$env:HTTPS_PROXY = 'http://127.0.0.1:7890'   # only used if the engine/model need fetching
$env:HTTP_PROXY = 'http://127.0.0.1:7890'

# --restart: switching tiers changes the context, and Strata refuses to replace a
# running server with different choices unless it is told to. Answers in flight stop.
Strata @('launch', '--preset', $pick.Preset, '--restart', '--no-tui')
$code = $LASTEXITCODE
if ($code -ne 0) { exit $code }

Write-Host ''
Write-Host 'Point CCR at http://127.0.0.1:8080 (Anthropic clients use it without /v1).'
Write-Host 'Restart ccr-claude so it re-reads the window:'
Write-Host ('  ' + (Join-Path (Split-Path $HERE -Parent) 'claude\ccr-claude\windows\ccr-claude.cmd'))
