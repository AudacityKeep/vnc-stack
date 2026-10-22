#Requires -RunAsAdministrator
<#
  vnc-stack, Windows side.
  Run from an elevated PowerShell:
      powershell -ExecutionPolicy Bypass -File .\windows\install.ps1 [-NoVdd] [-Distro Ubuntu]

  STATUS: untested draft. Test it on a clean machine before sharing it.
#>
param(
    [string]$Distro = 'Ubuntu',
    [switch]$NoVdd,
    [int]$VddWidth = 1920,
    [int]$VddHeight = 1080,
    [string]$Email
)
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "WARNING: $m" -ForegroundColor Yellow }
function New-RandomString([int]$Length) {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $bytes = New-Object byte[] $Length
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

# ---- 0. Checks ---------------------------------------------------------------
Step 'Checking this PC'
$build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
if ($build -lt 22621) { throw 'Windows 11 22H2 or newer is required (WSL mirrored networking).' }
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget was not found. Install 'App Installer' from the Microsoft Store, then run this again."
}
if (-not $Email) { $Email = Read-Host 'Email address for your access link (Enter to skip)' }
# ---- 1. WSL + Ubuntu ---------------------------------------------------------
Step "Checking WSL and $Distro"
$installed = @(& wsl.exe -l -q 2>$null) |
    ForEach-Object { ($_ -replace "`0", '').Trim() } |
    Where-Object { $_ }
if ($installed -notcontains $Distro) {
    Step "Installing WSL and $Distro (a restart may be needed)"
    & wsl.exe --install -d $Distro --no-launch
    Write-Host "`nNext: restart Windows if asked, open '$Distro' from the Start menu once to create your Linux user, then run this script again." -ForegroundColor Green
    exit 0
}
$linuxUser = (& wsl.exe -d $Distro --exec whoami).Trim()
if ($linuxUser -eq 'root') {
    throw "Open '$Distro' from the Start menu once and create a normal Linux user first, then run this again."
}

# ---- 2. .wslconfig (mirrored networking so WSL can reach TightVNC on localhost) ---
Step 'Checking .wslconfig'
$cfg = Join-Path $env:USERPROFILE '.wslconfig'
$memGB = [math]::Max(4, [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB / 2))
$needShutdown = $false
if (-not (Test-Path $cfg)) {
    @"
[wsl2]
networkingMode=mirrored
memory=${memGB}GB

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
"@ | Set-Content -Path $cfg -Encoding ASCII
    $needShutdown = $true
    Write-Host "Created $cfg"
}
elseif ((Get-Content $cfg -Raw) -notmatch 'networkingMode\s*=\s*mirrored') {
    Warn "$cfg already exists and does not enable mirrored networking."
    Warn 'Add this under [wsl2], then run "wsl --shutdown":   networkingMode=mirrored'
}

# ---- 3. TightVNC ---------------------------------------------------------------
Step 'Setting up TightVNC'
$vncPass = $null
if (Get-Service tvnserver -ErrorAction SilentlyContinue) {
    Warn 'TightVNC is already installed. Keeping its password; applying the safe settings only.'
}
else {
    & winget.exe show --id GlavSoft.TightVNC -e --accept-source-agreements *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'winget could not find GlavSoft.TightVNC. Install TightVNC (Server only, as a service) from tightvnc.com, then run this again.'
    }
    $vncPass = New-RandomString 8
    $msiArgs = '/quiet /norestart ADDLOCAL=Server SERVER_REGISTER_AS_SERVICE=1 SERVER_ADD_FIREWALL_EXCEPTION=0 ' +
        'SET_USEVNCAUTHENTICATION=1 VALUE_OF_USEVNCAUTHENTICATION=1 SET_PASSWORD=1 VALUE_OF_PASSWORD=' + $vncPass + ' ' +
        'SET_ALLOWLOOPBACK=1 VALUE_OF_ALLOWLOOPBACK=1 SET_LOOPBACKONLY=1 VALUE_OF_LOOPBACKONLY=1 ' +
        'SET_ACCEPTHTTPCONNECTIONS=1 VALUE_OF_ACCEPTHTTPCONNECTIONS=0 ' +
        'SET_ENABLEFILETRANSFERS=1 VALUE_OF_ENABLEFILETRANSFERS=0'
    & winget.exe install --id GlavSoft.TightVNC -e --silent --accept-package-agreements --accept-source-agreements --override $msiArgs
    if ($LASTEXITCODE -ne 0) { throw 'TightVNC install failed.' }
$setupArgs = @()
if ($Email) { $setupArgs += '--email'; $setupArgs += $Email }    Start-Sleep -Seconds 3
}

# Make sure the important settings really are set, whatever the installer did.
$key = 'HKLM:\SOFTWARE\TightVNC\Server'
if (Test-Path $key) {
    Set-ItemProperty $key -Name LoopbackOnly -Value 1 -Type DWord
    Set-ItemProperty $key -Name AllowLoopback -Value 1 -Type DWord
    Set-ItemProperty $key -Name UseVncAuthentication -Value 1 -Type DWord
    Set-ItemProperty $key -Name AcceptHttpConnections -Value 0 -Type DWord
    Set-ItemProperty $key -Name EnableFileTransfers -Value 0 -Type DWord
    Restart-Service tvnserver
}
else {
    Warn 'TightVNC settings were not found in the registry. In TightVNC Server > Configuration, enable "Allow loopback connections" and "Only loopback", and disable the web viewer and file transfers.'
}
# Remove TightVNC's default inbound allow rule (not needed for loopback).
Get-NetFirewallRule -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like 'TightVNC*' -and $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' } |
    Remove-NetFirewallRule

# ---- 4. Optional: Virtual Display Driver ------------------------------------------
if (-not $NoVdd) {
    Step 'Installing the Virtual Display Driver (optional)'
    Warn 'Windows will ask you to approve the driver. Note: this driver has been unstable on some PCs - run with -NoVdd to skip it.'
    & winget.exe install --id VirtualDrivers.Virtual-Display-Driver -e --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw 'Virtual Display Driver install failed.' }

    $vddDir = 'C:\VirtualDisplayDriver'
    New-Item -ItemType Directory -Force $vddDir | Out-Null
    $xml = Get-Content (Join-Path $PSScriptRoot 'vdd_settings.xml') -Raw
    $xml = $xml.Replace('{{WIDTH}}', "$VddWidth").Replace('{{HEIGHT}}', "$VddHeight")
    Set-Content -Path (Join-Path $vddDir 'vdd_settings.xml') -Value $xml -Encoding UTF8

    $dir = 'C:\ProgramData\vnc-stack'
    New-Item -ItemType Directory -Force $dir | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'restart-vdd.ps1') $dir -Force
    # Only admins may change the script, because the task below runs it as SYSTEM.
    & icacls.exe $dir /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' 'Users:(OI)(CI)RX' | Out-Null
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$dir\restart-vdd.ps1`""
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
    Register-ScheduledTask -TaskName 'Restart-VDD' -Action $action -Principal $principal -Force | Out-Null
}

# ---- 5. Keep WSL running ------------------------------------------------------------
Step 'Setting up the WSL keep-alive'
$vbs = Join-Path ([Environment]::GetFolderPath('Startup')) 'wsl-keepalive.vbs'
@"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "wsl.exe -d $Distro -e sleep infinity", 0, False
"@ | Set-Content -Path $vbs -Encoding ASCII
Start-Process wscript.exe -ArgumentList "`"$vbs`""

# ---- 6. Linux side ---------------------------------------------------------------
Step "Running the Linux-side setup inside $Distro"
$repoPosix = $RepoRoot.Replace('\', '/')
$repoWsl = (& wsl.exe -d $Distro --exec wslpath -a $repoPosix).Trim()
$setupArgs = @()
if ($Email) { $setupArgs += '--email'; $setupArgs += $Email }

& wsl.exe -d $Distro --exec bash "$repoWsl/setup.sh"
if ($LASTEXITCODE -ne 0) { throw 'The Linux-side setup failed. Fix the error above and run this again.' }

if ($vncPass) {
    $vncPass | & wsl.exe -d $Distro --exec bash -c 'umask 077; mkdir -p ~/.config/vnc-stack; tr -d "\r\n" > ~/.config/vnc-stack/vnc_pass'
}

# ---- 7. Finish ----------------------------------------------------------------------
Step 'Done'
& wsl.exe -d $Distro --exec bash -lc 'vnc creds'
Write-Host "`nOpen $Distro and run:  vnc start" -ForegroundColor Green
Write-Host 'Keep these logins private. Run "vnc stop" whenever you are not using remote access.'
if ($needShutdown) {
    Warn 'A WSL restart is needed once so mirrored networking takes effect (this stops anything running in WSL).'
    if ((Read-Host 'Run "wsl --shutdown" now? (y/N)') -eq 'y') { & wsl.exe --shutdown }
}
