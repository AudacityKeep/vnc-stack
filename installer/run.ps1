<#
  vnc-stack wizard helper. Setup.exe and the Start Menu shortcuts call this.
  It runs the right Windows script in this console, then waits for Enter so the
  window does not close before you can read the output.

      powershell -ExecutionPolicy Bypass -File .\installer\run.ps1 -Action install [-NoVdd] [-Email name@gmail.com]
      powershell -ExecutionPolicy Bypass -File .\installer\run.ps1 -Action uninstall
#>
param(
    [Parameter(Mandatory)][ValidateSet('install', 'uninstall')][string]$Action,
    [switch]$NoVdd,
    [string]$Email
)

# The Start Menu shortcuts are not elevated, so re-launch as administrator if needed.
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action $Action"
    if ($NoVdd) { $argList += ' -NoVdd' }
    if ($Email) { $argList += " -Email $Email" }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
    exit 0
}

$ErrorActionPreference = 'Stop'
$windowsDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'windows'

try {
    if ($Action -eq 'install') {
        $build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
        $scriptName = if ($build -ge 22000) { 'win11.ps1' } else { 'win10.ps1' }
        $params = @{}
        if ($NoVdd) { $params['NoVdd'] = $true }
        if ($Email) { $params['Email'] = $Email }

        $log = Join-Path $env:USERPROFILE 'vnc-stack-install.log'
        Start-Transcript -Path $log -Append | Out-Null
        try { & (Join-Path $windowsDir $scriptName) @params }
        finally { try { Stop-Transcript | Out-Null } catch { } }
    }
    else {
        & (Join-Path $windowsDir 'uninstall.ps1') -Yes
    }
}
catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ''
Read-Host 'Press Enter to close this window'
