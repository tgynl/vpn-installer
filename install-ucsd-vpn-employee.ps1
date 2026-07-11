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
$GitHubRepo      = "tgynl/vpn-installer"
# The exact filename you upload as a release asset each month - keep this identical every time
$AssetName       = "CiscoSecureClient-Windows.msi"
$VpnServer       = "vpn.ucsd.edu"
$VpnDisplayName  = "vpn.ucsd.edu"
$VpnGroup        = "Secure-Connect-Allthru"
# This script's own raw GitHub URL - only needed if you distribute it as a
# copy-paste "irm ... | iex" one-liner instead of a downloaded .ps1 file.
# Leave blank ("") if people always download and run the .ps1 directly.
$ScriptUrl       = "https://raw.githubusercontent.com/tgynl/vpn-installer/main/install-ucsd-vpn-employee.ps1"

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
    $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) UCSD-VPN-Installer"
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec 60 -UserAgent $userAgent
            return
        } catch {
            Write-Warn "Invoke-WebRequest attempt $attempt failed: $($_.Exception.Message)"
            Start-Sleep -Seconds 3
        }
    }

    # Fallback: some networks/proxies reset Invoke-WebRequest's connection to
    # GitHub's CDN but allow a plain WebClient request through. Worth trying
    # before giving up entirely.
    Write-Warn "Retrying with a different download method..."
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", $userAgent)
        $webClient.DownloadFile($Uri, $OutFile)
        return
    } catch {
        throw
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

# Safety net: catch ANY unexpected error anywhere below this point so the
# window always pauses with the actual error message, instead of the console
# closing instantly before anyone can read what went wrong.
trap {
    Write-Fail "Unexpected error: $($_.Exception.Message)"
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
    if ($PSCommandPath) {
        # Running as a downloaded .ps1 file - relaunch that same file elevated.
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } else {
        # Running via "irm <url> | iex" - there's no local file to relaunch,
        # so re-fetch and re-run the same script in a new elevated window.
        if (-not $ScriptUrl) {
            Exit-WithMessage "This script needs Administrator rights, but it was run via 'irm | iex' without `$ScriptUrl set, so it can't relaunch itself elevated. Either set `$ScriptUrl in the CONFIG block, or run this as a downloaded .ps1 file instead."
        }
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        } catch {}
        # The TLS setting above only applies to THIS process, not the new
        # elevated one we're about to spawn - so it needs to be set again
        # inside the relaunched command. Also wrap in try/catch so a failure
        # in the outer fetch (network, TLS, 404) shows an error and pauses,
        # instead of the elevated window flashing and closing instantly.
        # Built from a single-quoted template (no PowerShell interpolation at
        # all) with the URL swapped in afterward - avoids fragile backtick
        # escaping when embedding this as a command-line argument.
        $innerTemplate = 'try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; irm ''__URL__'' | iex } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Read-Host ''Press Enter to close this window'' }'
        $command = $innerTemplate.Replace('__URL__', $ScriptUrl)
        $argList = "-NoProfile -ExecutionPolicy Bypass -Command `"$command`""
    }
    Start-Process powershell -Verb RunAs -ArgumentList $argList
    exit
}

# --- Check for existing install ---
Write-Step "Checking for an existing Cisco Secure Client installation"
$installPath64 = "$Env:ProgramFiles\Cisco\Cisco Secure Client"
$installPath86 = "${Env:ProgramFiles(x86)}\Cisco\Cisco Secure Client"
$alreadyInstalled = Test-CiscoModuleInstalled -NameLike "AnyConnect VPN"

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
        try {
            $iseProc = Start-Process msiexec.exe -ArgumentList $iseArgs -Wait -PassThru
        } catch {
            Exit-WithMessage "Failed to launch the ISE Posture installer: $($_.Exception.Message)"
        }
        if ($iseProc.ExitCode -ne 0) {
            Exit-WithMessage "ISE Posture installer exited with code $($iseProc.ExitCode). This usually means the .msi failed validation - confirm the uploaded file is a genuine, uncorrupted Cisco ISE Posture installer."
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
      <UserGroup>$VpnGroup</UserGroup>
    </HostEntry>
  </ServerList>
</AnyConnectProfile>
"@
Set-Content -Path $profilePath -Value $profileXml -Encoding UTF8
Write-Ok "Connection profile written to $profilePath"

# --- Launch the client ---
Write-Step "Launching Cisco Secure Client"
# The GUI executable's name has changed across Cisco Secure Client versions
# (vpnui.exe historically, csc_ui.exe in newer releases) - check both.
$knownExeNames = @("csc_ui.exe", "vpnui.exe")
$vpnui = $null
foreach ($installFolder in @($installPath64, $installPath86)) {
    if (-not (Test-Path $installFolder)) { continue }
    foreach ($exeName in $knownExeNames) {
        $found = Get-ChildItem -Path $installFolder -Filter $exeName -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $vpnui = $found.FullName; break }
    }
    if ($vpnui) { break }
}
if (-not $vpnui) {
    # Last resort: search all of Program Files\Cisco in case the install folder itself moved.
    $searchRoots = @("$Env:ProgramFiles\Cisco", "${Env:ProgramFiles(x86)}\Cisco") | Where-Object { Test-Path $_ }
    foreach ($root in $searchRoots) {
        foreach ($exeName in $knownExeNames) {
            $found = Get-ChildItem -Path $root -Filter $exeName -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $vpnui = $found.FullName; break }
        }
        if ($vpnui) { break }
    }
}

if ($vpnui) {
    try {
        Start-Process $vpnui
    } catch {
        Write-Warn "Could not auto-launch Cisco Secure Client ($($_.Exception.Message)). Please open it from the Start Menu."
    }
} else {
    Write-Warn "Installed successfully, but couldn't locate the Cisco Secure Client GUI to launch it automatically. Please open 'Cisco Secure Client' from the Start Menu."
}

Write-Host "`nAll done! In the Cisco Secure Client window, pick '$VpnDisplayName' from the list," -ForegroundColor Cyan
Write-Host "then choose your Group and log in with your Active Directory username and password." -ForegroundColor Cyan
Write-Host "If you use Duo two-step login, approve the prompt on your phone when asked." -ForegroundColor Cyan
if ($Audience -eq "Employee") {
    Write-Host "You may briefly see an ISE Posture compliance check window after connecting - this is expected." -ForegroundColor Cyan
}
Read-Host "`nPress Enter to close this window"
