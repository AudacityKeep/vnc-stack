#Requires -RunAsAdministrator
<#
  vnc-stack uninstaller, Windows side. Removes what install.ps1 added.
  Run from an elevated PowerShell:
      powershell -ExecutionPolicy Bypass -File .\windows\uninstall.ps1 [-Distro Ubuntu]

  This turns remote access off. Do not run it on a PC you are using for remote access right now.
#>
param(
    [string]$Distro = 'Ubuntu',
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "WARNING: $m" -ForegroundColor Yellow }

if (-not $Yes) {
    $answer = (Read-Host 'This will remove vnc-stack from this PC. Continue? (Y/N)').Trim().ToUpper()
    if ($answer -ne 'Y') {
        Write-Host 'Uninstall cancelled.'
        exit 1
    }
}

# ---- 1. Linux side (runs uninstall.sh from the repo root, if it exists) ------------
Step "Running the Linux-side uninstall inside $Distro"
$installed = @(& wsl.exe -l -q 2>$null) |
    ForEach-Object { ($_ -replace "`0", '').Trim() } |
    Where-Object { $_ }
$uninstallSh = Join-Path $RepoRoot 'uninstall.sh'
if (($installed -contains $Distro) -and (Test-Path $uninstallSh)) {
    $repoPosix = $RepoRoot.Replace('\', '/')
    $repoWsl = (& wsl.exe -d $Distro --exec wslpath -a $repoPosix).Trim()
    & wsl.exe -d $Distro --exec bash "$repoWsl/uninstall.sh"
    if ($LASTEXITCODE -ne 0) { Warn 'The Linux-side uninstall reported an error. Continuing with the Windows side.' }
}
else {
    Warn "Skipped: either $Distro is not installed or uninstall.sh was not found in $RepoRoot."
}

# ---- 2. WSL keep-alive -----------------------------------------------------------------
Step 'Removing the WSL keep-alive'
Get-CimInstance Win32_Process -Filter "Name='wsl.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*sleep infinity*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
$vbs = Join-Path ([Environment]::GetFolderPath('Startup')) 'wsl-keepalive.vbs'
Remove-Item $vbs -Force -ErrorAction SilentlyContinue

# ---- 3. Restart-VDD scheduled task and firewall rule -----------------------------------
Step 'Removing the Restart-VDD task and the WSL firewall rule'
Unregister-ScheduledTask -TaskName 'Restart-VDD' -Confirm:$false -ErrorAction SilentlyContinue
Get-NetFirewallRule -DisplayName 'vnc-stack TightVNC from WSL only' -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule

# ---- 4. TightVNC (only if vnc-stack installed it) --------------------------------------
Step 'Checking TightVNC'
$marker = 'C:\ProgramData\vnc-stack\tightvnc-installed-by-vnc-stack'
if (Test-Path $marker) {
    Stop-Service tvnserver -ErrorAction SilentlyContinue
    & winget.exe uninstall --id GlavSoft.TightVNC -e --silent
    if ($LASTEXITCODE -ne 0) { Warn 'Could not remove TightVNC. Uninstall it in Settings > Apps.' }
}
else {
    Write-Host 'TightVNC was not installed by vnc-stack, so it was left alone.'
}

# ---- 5. Virtual Display Driver (asks, because it may have been there before) -----------
Step 'Checking the Virtual Display Driver'
& winget.exe list --id VirtualDrivers.Virtual-Display-Driver -e *> $null
if ($LASTEXITCODE -eq 0) {
    $vdd = (Read-Host 'Remove the Virtual Display Driver too? Say N if you used it before vnc-stack. (y/N)').Trim().ToLower()
    if ($vdd -eq 'y') {
        & winget.exe uninstall --id VirtualDrivers.Virtual-Display-Driver -e --silent
        if ($LASTEXITCODE -ne 0) { Warn 'Could not remove the Virtual Display Driver. Uninstall it in Settings > Apps.' }
        Remove-Item 'C:\VirtualDisplayDriver\vdd_settings.xml' -Force -ErrorAction SilentlyContinue
    }
}
else {
    Write-Host 'The Virtual Display Driver is not installed.'
}

# ---- 6. vnc-stack's own folder (last, because step 4 reads the marker file in it) ------
Step 'Removing C:\ProgramData\vnc-stack'
Remove-Item 'C:\ProgramData\vnc-stack' -Recurse -Force -ErrorAction SilentlyContinue

# ---- 7. Finish ------------------------------------------------------------------------
Step 'Done'
Write-Host 'Left in place on purpose: WSL and Ubuntu, your .wslconfig, and winget.' -ForegroundColor Green
Write-Host 'Restart Windows if the driver or TightVNC removal asked for it.'
