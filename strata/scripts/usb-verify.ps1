# Verify the event log actually works, then look for the keyboard and any hub power event.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

Write-Host '=== Sanity: does the System log have ANY recent events? ==='
$any = Get-WinEvent -LogName System -MaxEvents 5 -ErrorAction SilentlyContinue
$any | ForEach-Object { '  {0:yyyy-MM-dd HH:mm:ss}  {1}  id={2}' -f $_.TimeCreated, $_.ProviderName, $_.Id }

Write-Host ''
Write-Host '=== Keyboard-class devices ==='
Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.Class -eq 'Keyboard' } |
    ForEach-Object {
        $p = Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_LastArrivalDate' -ErrorAction SilentlyContinue
        '{0}  {1}' -f $_.FriendlyName, $_.InstanceId
        '      arrival: {0}' -f $p.Data
    }

Write-Host ''
Write-Host '=== Every device whose arrival is from today after 10:00 (possible disconnect) ==='
$cut = Get-Date '2026-10-26 10:00:00'
Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    ForEach-Object {
        $p = Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_LastArrivalDate' -ErrorAction SilentlyContinue
        if ($p -and $p.Data -and ([datetime]$p.Data) -gt $cut) {
            [pscustomobject]@{ A = [datetime]$p.Data; N = $_.FriendlyName; I = $_.InstanceId; C = $_.Class }
        }
    } |
    Sort-Object A -Descending |
    ForEach-Object { '  {0:HH:mm:ss.fff}  {1,-10} {2,-28} {3}' -f $_.A, $_.C, $_.N, $_.I }

Write-Host ''
Write-Host '=== Disabled event logs that would have recorded the drop ==='
foreach ($n in 'Microsoft-Windows-USB-USBHUB3/Operational','Microsoft-Windows-USB-USBXHCI/Operational','Microsoft-Windows-Kernel-PnP/Configuration','Microsoft-Windows-DeviceSetupManager/Admin') {
    $l = Get-WinEvent -ListLog $n -ErrorAction SilentlyContinue
    if ($l) {
        '  {0,-52} enabled={1,-6} records={2}' -f $n, $l.IsEnabled, $l.RecordCount
    } else { '  {0,-52} not present' -f $n }
}

Write-Host ''
Write-Host '=== Power supply / brownout indicators (Kernel-Power 41, WHEA, BugCheck) ==='
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddDays(-2); Id=@(41,42,107,6008,18,19,20,46,47)} -ErrorAction SilentlyContinue |
    Sort-Object TimeCreated |
    ForEach-Object { '  {0:yyyy-MM-dd HH:mm:ss}  {1} id={2}  {3}' -f $_.TimeCreated, $_.ProviderName, $_.Id, (($_.Message -split "`r?`n")[0]) }
