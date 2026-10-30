# Every present USB device's last arrival time, newest first.
# An arrival cluster at one instant means the hub went down, not one device.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$rows = @()
foreach ($d in (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'USB\*' })) {
    $p = Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_LastArrivalDate' -ErrorAction SilentlyContinue
    if ($p -and $p.Data) {
        $rows += [pscustomobject]@{
            Arrival  = [datetime]$p.Data
            Name     = $d.FriendlyName
            Instance = $d.InstanceId
        }
    }
}

Write-Host '=== newest arrival times (all USB devices) ==='
$rows | Sort-Object Arrival -Descending | Select-Object -First 18 |
    ForEach-Object { '{0:yyyy-MM-dd HH:mm:ss.fff}  {1,-28} {2}' -f $_.Arrival, $_.Name, $_.Instance } |
    ForEach-Object { '  ' + $_ }

Write-Host ''
Write-Host '=== arrivals in the last 10 minutes ==='
$cut = (Get-Date).AddMinutes(-10)
$recent = $rows | Where-Object { $_.Arrival -gt $cut } | Sort-Object Arrival
if ($recent) {
    $recent | ForEach-Object { '  {0:HH:mm:ss.fff}  {1,-28} {2}' -f $_.Arrival, $_.Name, $_.Instance }
    Write-Host ''
    Write-Host ("  {0} devices re-enumerated in the last 10 minutes" -f @($recent).Count)
} else {
    Write-Host '  none'
}
