#Requires -RunAsAdministrator
<#
  vnc-stack launcher. Asks which Windows you have, then runs the matching installer.
      powershell -ExecutionPolicy Bypass -File .\windows\install.ps1
#>
$build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
$detected = if ($build -ge 22000) { '11' } else { '10' }

Write-Host 'Which version of Windows is this PC running?'
Write-Host '  10 = Windows 10'
Write-Host '  11 = Windows 11'
$choice = (Read-Host "Enter 10 or 11 (Enter = $detected, the detected version)").Trim()
if (-not $choice) { $choice = $detected }

switch ($choice) {
    '10' { $script = Join-Path $PSScriptRoot 'win10.ps1' }
    '11' { $script = Join-Path $PSScriptRoot 'win11.ps1' }
    default { throw 'Please enter 10 or 11.' }
}
if ($choice -ne $detected) {
    Write-Host "This PC looks like Windows $detected (build $build), but you chose $choice." -ForegroundColor Yellow
    if ((Read-Host 'Continue anyway? (y/N)') -ne 'y') { exit 1 }
}
& $script @args