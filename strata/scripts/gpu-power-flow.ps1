<#
    End-to-end test of the GPU power cap flow, run once with administrator rights:

        350 W (default)  ->  cap to 200 W  ->  `strata launch --stop`  ->  back to 350 W

    Each step is written to gpu-power-flow.log so the result can be read afterwards, even
    though this runs in its own elevated window.

    Nothing persistent is changed: the power cap is a driver setting that a reboot also clears.
#>
$ErrorActionPreference = 'Continue'

$log = Join-Path $PSScriptRoot 'gpu-power-flow.log'
if (Test-Path $log) { Remove-Item $log -Force }
function Say([string]$t) {
    $t | Tee-Object -FilePath $log -Append | Out-Host
}

function Limit {
    $o = & nvidia-smi --query-gpu=power.limit,power.default_limit --format=csv,noheader,nounits 2>$null
    ($o -split ',' | ForEach-Object { $_.Trim() }) -join ' / '
}

$strata = Join-Path $PSScriptRoot 'strata-launch.cmd'
$bin = Join-Path $PSScriptRoot 'terminal\current\bin'

Say "=== GPU power cap flow test $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
Say "elevated: $((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
Say ""

Say "[1] before          limit/default = $(Limit)"

Say "[2] capping to 200 W ..."
& nvidia-smi -pl 200 2>&1 | ForEach-Object { Say "    $_" }
Say "    now            limit/default = $(Limit)"

Say "[3] running: strata launch --stop"
$env:Path = "$bin;$env:Path"
$env:PYTHONUTF8 = '1'
$out = & (Join-Path $bin 'strata.cmd') launch --stop 2>&1 | Out-String
foreach ($line in ($out -split "`r?`n")) {
    if ($line.Trim()) { Say "    $line" }
}

Say "[4] after           limit/default = $(Limit)"

$final = (& nvidia-smi --query-gpu=power.limit,power.default_limit --format=csv,noheader,nounits 2>$null)
$f = $final -split ',' | ForEach-Object { $_.Trim() }
if ([double]$f[0] -eq [double]$f[1]) {
    Say ""
    Say "RESULT: PASS - the stop put the card back at its default ($($f[0]) W)."
} else {
    Say ""
    Say "RESULT: FAIL - the card is still at $($f[0]) W (default $($f[1]) W)."
}
