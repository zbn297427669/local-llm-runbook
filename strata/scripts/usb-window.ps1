# Everything the system logged around the 12:26:35 event.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$from = Get-Date '2026-10-26 12:24:00'
$to   = Get-Date '2026-10-26 12:30:00'

Write-Host "=== System log, $($from.ToString('HH:mm'))-$($to.ToString('HH:mm')) ==="
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$from; EndTime=$to} -ErrorAction SilentlyContinue |
    Sort-Object TimeCreated |
    ForEach-Object {
        $first = ($_.Message -split "`r?`n")[0]
        if ($first.Length -gt 130) { $first = $first.Substring(0,130) }
        '{0:HH:mm:ss.fff}  {1,-38} id={2,-5} {3}' -f $_.TimeCreated, $_.ProviderName, $_.Id, $first
    }

Write-Host ''
Write-Host '=== Kernel-PnP device configuration events, same window ==='
Get-WinEvent -LogName 'Microsoft-Windows-Kernel-PnP/Configuration' -MaxEvents 200 -ErrorAction SilentlyContinue |
    Where-Object { $_.TimeCreated -ge $from -and $_.TimeCreated -le $to } |
    Sort-Object TimeCreated |
    ForEach-Object {
        '{0:HH:mm:ss.fff} id={1}  {2}' -f $_.TimeCreated, $_.Id, (($_.Message -split "`r?`n")[0])
    }

Write-Host ''
Write-Host '=== USB hub driver events, same window ==='
foreach ($log in 'Microsoft-Windows-USB-USBHUB3/Operational','Microsoft-Windows-USB-USBXHCI/Operational') {
    $ev = Get-WinEvent -LogName $log -MaxEvents 300 -ErrorAction SilentlyContinue |
        Where-Object { $_.TimeCreated -ge $from -and $_.TimeCreated -le $to }
    if ($ev) {
        Write-Host "  --- $log ---"
        $ev | Sort-Object TimeCreated | ForEach-Object {
            '  {0:HH:mm:ss.fff} id={1,-6} {2}' -f $_.TimeCreated, $_.Id, (($_.Message -split "`r?`n")[0])
        }
    } else { Write-Host "  --- $log : no events ---" }
}

Write-Host ''
Write-Host '=== The keyboard devices and their arrival times ==='
$kb = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.Class -in 'Keyboard','HIDClass' -and $_.InstanceId -like 'USB\*' }
foreach ($d in $kb) {
    $p = Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_LastArrivalDate' -ErrorAction SilentlyContinue
    $parent = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_Parent' -ErrorAction SilentlyContinue).Data
    '{0:yyyy-MM-dd HH:mm:ss.fff}  {1,-30} {2}' -f ([datetime]$p.Data), $d.FriendlyName, $d.InstanceId
    '      parent: {0}' -f $parent
}
