# Restarts the Virtual Display Driver device. Run on demand by the "Restart-VDD" scheduled task:
#   schtasks /run /tn Restart-VDD
$device = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -like '*Virtual Display Driver*' } |
    Select-Object -First 1
if (-not $device) {
    Write-Error 'Virtual Display Driver device not found.'
    exit 1
}
Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false
Start-Sleep -Seconds 3
Enable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false
