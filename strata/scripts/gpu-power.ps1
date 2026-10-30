<#
    Strata GPU power limit: cap the card while the model serves, restore it when the service stops.

    Why: the small USB display and the keyboard both dropped every time the GPU jumped from
    idle to ~99% load. VRAM and RAM headroom were ruled out (the third drop happened with
    2.3 GB VRAM and 3.8 GB RAM free). That leaves the 12 V rail sagging under the GPU's
    current step. Capping the power limit lowers both the peak current and the step size.

    Usage (needs an elevated PowerShell: nvidia-smi -pl requires administrator):
        .\gpu-power.ps1 -Limit 200      set the cap to 200 W now
        .\gpu-power.ps1 -Restore        restore the card's default limit
        .\gpu-power.ps1 -Status         show the current limit and who holds it

    The cap is NOT persistent: a reboot returns the card to its default. Nothing here is
    written to the registry or the driver profile.
#>
param(
    [int]$Limit = 0,
    [switch]$Restore,
    [switch]$Status
)

$ErrorActionPreference = 'Stop'

function Current {
    $out = & nvidia-smi --query-gpu=power.limit,power.default_limit,power.min_limit,power.max_limit --format=csv,noheader,nounits 2>$null
    if (-not $out) { throw 'nvidia-smi returned nothing: is the NVIDIA driver loaded?' }
    $f = $out -split ',' | ForEach-Object { $_.Trim() }
    [pscustomobject]@{
        Limit   = [double]$f[0]
        Default = [double]$f[1]
        Min     = [double]$f[2]
        Max     = [double]$f[3]
    }
}

if ($Status) {
    $c = Current
    'current limit : {0:N0} W' -f $c.Limit
    'default limit : {0:N0} W' -f $c.Default
    'allowed range : {0:N0} - {1:N0} W' -f $c.Min, $c.Max
    if ($c.Limit -lt $c.Default) { 'state         : CAPPED (service running?)' } else { 'state         : default' }
    exit 0
}

if (-not $Restore -and $Limit -le 0) {
    Write-Host 'give -Limit <watts>, or -Restore, or -Status' -ForegroundColor Yellow
    exit 2
}

$c = Current
if ($Restore) {
    $target = [int]$c.Default
    $what = 'restoring the default'
} else {
    if ($Limit -lt $c.Min -or $Limit -gt $c.Max) {
        Write-Host ("{0} W is outside this card's {1:N0}-{2:N0} W range" -f $Limit, $c.Min, $c.Max) -ForegroundColor Yellow
        exit 2
    }
    $target = $Limit
    $what = 'applying the cap'
}

Write-Host ("was {0:N0} W; {1} -> {2:N0} W" -f $c.Limit, $what, $target)
$out = & nvidia-smi -pl $target 2>&1 | Out-String
Write-Host $out.Trim()

$after = Current
'now {0:N0} W' -f $after.Limit
if ([int]$after.Limit -ne $target) {
    Write-Host 'the driver did not accept it (running elevated?)' -ForegroundColor Red
    exit 1
}
