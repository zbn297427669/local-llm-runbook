<#
    Strata USB monitor: record what the machine is doing whenever the USB display re-enumerates.

    The small USB screens have no "allow the computer to turn off this device" checkbox
    (they are WinUSB devices), so Windows logs nothing when they drop. The only hard evidence
    is DEVPKEY_Device_LastArrivalDate: it changes exactly when the device is re-enumerated,
    i.e. when it lost power and came back.

    This writes one CSV line every interval, plus a WATCH line the moment an arrival time
    changes. Leave it running while you work; if the screen drops, the timestamp and the
    power/GPU/memory figures at that moment are in the file.

    Start:   powershell -NoProfile -File $env:STRATA_HOME\usb-monitor.ps1
    Stop:    Ctrl+C

    Nothing here changes any setting. It only reads.
#>
param(
    [int]$IntervalMs = 2000,
    [string]$LogPath = (Join-Path $PSScriptRoot 'usb-monitor.csv'),
    # label -> PnP instance id, e.g. @{ screen = 'USB\VID_1234&PID_5678\A1B2C3' }
    # No defaults on purpose: instance ids contain this machine's device serials.
    [hashtable]$Devices = @{}
)

$ErrorActionPreference = 'Continue'

function Arrival([string]$instanceId) {
    $p = Get-PnpDeviceProperty -InstanceId $instanceId -KeyName 'DEVPKEY_Device_LastArrivalDate' -ErrorAction SilentlyContinue
    if ($p -and $p.Data) { ([datetime]$p.Data).ToString('yyyy-MM-dd HH:mm:ss.fff') } else { '' }
}

if (-not $Devices.Count) {
    Write-Host 'Pass -Devices as a hashtable of label -> PnP instance id, e.g.:'
    Write-Host '    .\usb-monitor.ps1 -Devices @{ screen = ''USB\VID_1234&PID_5678\A1B2C3'' }'
    Write-Host ''
    Write-Host 'USB devices present on this machine:'
    Get-PnpDevice -Class USB -Status OK -ErrorAction SilentlyContinue |
        Where-Object InstanceId -like 'USB\VID_*' |
        Select-Object FriendlyName, InstanceId | Format-Table -AutoSize
    return
}

function GpuSample {
    $out = & nvidia-smi --query-gpu=power.draw,utilization.gpu,memory.used,temperature.gpu --format=csv,noheader,nounits 2>$null
    if ($out) {
        $f = $out -split ',' | ForEach-Object { $_.Trim() }
        return [pscustomobject]@{ Power = $f[0]; Util = $f[1]; Vram = $f[2]; Temp = $f[3] }
    }
    return [pscustomobject]@{ Power = ''; Util = ''; Vram = ''; Temp = '' }
}

function MemFreeGb {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) { [math]::Round($os.FreePhysicalMemory / 1MB, 1) } else { '' }
}

function StrataPid {
    (Get-Process strata -ErrorAction SilentlyContinue | Select-Object -First 1).Id
}

$keys = @($Devices.Keys)
$arrivalCols = @($keys | ForEach-Object { "arrival_$_" })
if (-not (Test-Path $LogPath)) {
    ((@('time','event','gpu_power_w','gpu_util_pct','vram_mib','gpu_temp_c','ram_free_gb','strata_pid','strata_ram_gb') +
      $arrivalCols + @('note')) -join ',') |
        Set-Content -LiteralPath $LogPath -Encoding UTF8
    Write-Host "new log: $LogPath"
} else {
    Write-Host "appending to: $LogPath"
}

$last = @{}
foreach ($k in $keys) { $last[$k] = Arrival $Devices[$k] }
Write-Host 'baseline arrival:'
foreach ($k in $keys) { '  {0,-12} {1}' -f $k, $last[$k] }
Write-Host "watching every ${IntervalMs} ms. Ctrl+C to stop."
Write-Host ''

$stop = $false
try {
    while (-not $stop) {
        $g = GpuSample
        $ramFree = MemFreeGb
        $spid = StrataPid
        $sram = ''
        if ($spid) {
            $p = Get-Process -Id $spid -ErrorAction SilentlyContinue
            if ($p) { $sram = [math]::Round($p.WorkingSet64 / 1GB, 1) }
        }

        $arrivals = @{}
        foreach ($k in $keys) { $arrivals[$k] = Arrival $Devices[$k] }

        # a change in any arrival time is the event we are looking for
        $events = @()
        foreach ($k in $keys) {
            if ($arrivals[$k] -ne $last[$k]) {
                $events += "$k re-enumerated (was $($last[$k]))"
                $last[$k] = $arrivals[$k]
            }
        }

        $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        $event = if ($events.Count) { 'WATCH' } else { 'tick' }
        $note  = if ($events.Count) { $events -join '; ' } else { '' }

        $vals = @($stamp, $event, $g.Power, $g.Util, $g.Vram, $g.Temp, $ramFree, $spid, $sram) +
                @($keys | ForEach-Object { $arrivals[$_] }) + @($note)
        (($vals[0..($vals.Count - 2)] -join ',') + ',"' + ($note -replace '"', '""') + '"') |
            Add-Content -LiteralPath $LogPath -Encoding UTF8

        if ($events.Count) {
            Write-Host ''
            Write-Host "  *** $($events -join '; ') at $stamp ***" -ForegroundColor Yellow
            Write-Host ("      GPU {0}W {1}% {2}C   free RAM {3} GB   strata {4}" -f $g.Power, $g.Util, $g.Temp, $ramFree, $sram) -ForegroundColor Yellow
            Write-Host ''
        }

        Start-Sleep -Milliseconds $IntervalMs
    }
}
finally {
    Write-Host ''
    Write-Host "stopped. log: $LogPath"
    $w = Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue | Where-Object { $_ -match ',WATCH,' }
    if ($w) {
        Write-Host 'events recorded:'
        $w | ForEach-Object { '  ' + $_ }
    } else {
        Write-Host 'no re-enumeration recorded in this session.'
    }
}
