<#
.SYNOPSIS
  UCSD VPN (Cisco Secure Client) automated installer & setup for Windows.

.DESCRIPTION
  1. Checks if Cisco Secure Client is already installed.
  2. If not, downloads the installer from a GitHub Release and installs it silently.
  3. Writes a connection profile so "vpn.ucsd.edu" is pre-filled - students don't have to type it.
  4. Launches the client so all that's left is choosing a Group and logging in.

.NOTES
  IT ADMIN: edit the CONFIG block below before sharing this script with anyone.

  MONTHLY UPDATE PROCESS: when Cisco ships a new client, go to your GitHub repo's
  release tagged "latest", delete the old Windows asset, and upload the new
  installer with the EXACT SAME FILENAME as $AssetName below. Nothing in this
  script needs to change - the download URL always resolves to whatever file is
  currently attached to that tag.
#>

# ======================== CONFIG (edit me) ========================
# Your GitHub repo, as "owner/repo" (e.g. "ucsd-oec/vpn-installer")
$GitHubRepo      = "tgynl/vpn-installations"
# The exact filename you upload as a release asset each month - keep this identical every time
$AssetName       = "CiscoSecureClient-Windows.msi"
$VpnServer       = "vpn.ucsd.edu"
$VpnDisplayName  = "UCSD VPN"

# Who is this copy of the script for? "Student" = core VPN only. "Employee" = VPN + ISE Posture.
# IT ADMIN: distribute two copies of this script - one with this set to "Student", one to "Employee".
$Audience             = "Employee"   # "Student" or "Employee"
$IsePostureAssetName  = "CiscoISEPosture-Windows.msi"
# ====================================================================

$ErrorActionPreference = "Stop"

# Older Windows PowerShell (5.1) defaults to TLS 1.0/1.1, which GitHub's
# servers reject - this is the most common cause of "connection was closed
# unexpectedly" errors. Force TLS 1.2 before making any web requests.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

function Invoke-DownloadWithRetry {
    param(
        [string]$Uri,
        [string]$OutFile,
        [int]$MaxAttempts = 3
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec 60
            return
        } catch {
            if ($attempt -eq $MaxAttempts) { throw }
            Write-Warn "Download attempt $attempt failed, retrying..."
            Start-Sleep -Seconds 3
        }
    }
}

function Write-Step { param($msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "    $msg" -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "    $msg" -ForegroundColor Red }

function Exit-WithMessage {
    param($msg)
    Write-Fail $msg
    Write-Fail "If this keeps happening, contact IT support for a manual install."
    Read-Host "`nPress Enter to close this window"
    exit 1
}

# --- Sanity check: config was actually edited ---
if ($GitHubRepo -eq "PUT_GITHUB_OWNER/PUT_GITHUB_REPO_HERE") {
    Exit-WithMessage "This script hasn't been configured with a real GitHub repo yet."
}
if ($Audience -ne "Student" -and $Audience -ne "Employee") {
    Exit-WithMessage "`$Audience must be set to either 'Student' or 'Employee'."
}

function Test-CiscoModuleInstalled {
    # Looks for a program matching $NameLike in the Windows uninstall registry -
    # more reliable than guessing an install path, since module layouts can
    # shift slightly between Cisco Secure Client versions.
    param([string]$NameLike)
    $uninstallKeys = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($key in $uninstallKeys) {
        $found = Get-ItemProperty $key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "*$NameLike*" }
        if ($found) { return $true }
    }
    return $false
}

# --- Self-elevate to Administrator ---
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warn "Administrator rights are required. Relaunching with elevation..."
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process powershell -Verb RunAs -ArgumentList $argList
    exit
}

# --- Check for existing install ---
Write-Step "Checking for an existing Cisco Secure Client installation"
$installPath64 = "$Env:ProgramFiles\Cisco\Cisco Secure Client\vpnui.exe"
$installPath86 = "${Env:ProgramFiles(x86)}\Cisco\Cisco Secure Client\vpnui.exe"
$alreadyInstalled = (Test-Path $installPath64) -or (Test-Path $installPath86)

if ($alreadyInstalled) {
    Write-Ok "Cisco Secure Client is already installed. Skipping install."
} else {
    Write-Step "Downloading the Cisco Secure Client installer"
    $tempDir = Join-Path $Env:TEMP "ucsd-vpn-install"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $installerPath = Join-Path $tempDir $AssetName

    $downloadUrl = "https://github.com/$GitHubRepo/releases/latest/download/$AssetName"
    try {
        Invoke-DownloadWithRetry -Uri $downloadUrl -OutFile $installerPath
    } catch {
        Exit-WithMessage "Automatic download failed: $_"
    }

    if (-not (Test-Path $installerPath) -or (Get-Item $installerPath).Length -lt 1MB) {
        Exit-WithMessage "Downloaded file looks too small or missing - the download likely failed."
    }
    Write-Ok "Downloaded to $installerPath"

    Write-Step "Installing Cisco Secure Client (this can take a minute)..."
    $msiArgs = "/i `"$installerPath`" /quiet /norestart"
    $proc = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Exit-WithMessage "Installer exited with code $($proc.ExitCode)."
    }
    Write-Ok "Installation complete."
}

# --- ISE Posture module (employees only - students should NOT have this installed) ---
if ($Audience -eq "Employee") {
    Write-Step "Checking for ISE Posture module (required for employees)"
    if (Test-CiscoModuleInstalled -NameLike "ISE Posture") {
        Write-Ok "ISE Posture module is already installed. Skipping."
    } else {
        Write-Step "Downloading the ISE Posture module"
        $tempDir = Join-Path $Env:TEMP "ucsd-vpn-install"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        $isePath = Join-Path $tempDir $IsePostureAssetName

        $iseDownloadUrl = "https://github.com/$GitHubRepo/releases/latest/download/$IsePostureAssetName"
        try {
            Invoke-DownloadWithRetry -Uri $iseDownloadUrl -OutFile $isePath
        } catch {
            Exit-WithMessage "Automatic download of ISE Posture module failed: $_"
        }

        if (-not (Test-Path $isePath) -or (Get-Item $isePath).Length -lt 1MB) {
            Exit-WithMessage "Downloaded ISE Posture file looks too small or missing - the download likely failed."
        }
        Write-Ok "Downloaded to $isePath"

        Write-Step "Installing ISE Posture module"
        $iseArgs = "/i `"$isePath`" /quiet /norestart"
        $iseProc = Start-Process msiexec.exe -ArgumentList $iseArgs -Wait -PassThru
        if ($iseProc.ExitCode -ne 0) {
            Exit-WithMessage "ISE Posture installer exited with code $($iseProc.ExitCode)."
        }
        Write-Ok "ISE Posture module installed."
    }
} else {
    Write-Ok "Student install - ISE Posture module is not required and will not be installed."
}

# --- Pre-configure the VPN server so students don't have to type it ---
Write-Step "Setting up '$VpnServer' as the default connection"
$profileDir = "$Env:ProgramData\Cisco\Cisco Secure Client\VPN\Profile"
New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
$profilePath = Join-Path $profileDir "UCSD.xml"

$profileXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<AnyConnectProfile xmlns="http://schemas.xmlsoap.org/encoding/">
  <ServerList>
    <HostEntry>
      <HostName>$VpnDisplayName</HostName>
      <HostAddress>$VpnServer</HostAddress>
    </HostEntry>
  </ServerList>
</AnyConnectProfile>
"@
Set-Content -Path $profilePath -Value $profileXml -Encoding UTF8
Write-Ok "Connection profile written to $profilePath"

# --- Launch the client ---
Write-Step "Launching Cisco Secure Client"
$vpnui = if (Test-Path $installPath64) { $installPath64 } else { $installPath86 }
Start-Process $vpnui

Write-Host "`nAll done! In the Cisco Secure Client window, pick '$VpnDisplayName' from the list," -ForegroundColor Cyan
Write-Host "then choose your Group and log in with your Active Directory username and password." -ForegroundColor Cyan
Write-Host "If you use Duo two-step login, approve the prompt on your phone when asked." -ForegroundColor Cyan
if ($Audience -eq "Employee") {
    Write-Host "You may briefly see an ISE Posture compliance check window after connecting - this is expected." -ForegroundColor Cyan
}
Read-Host "`nPress Enter to close this window"
