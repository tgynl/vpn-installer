#!/usr/bin/env bash
#
# UCSD VPN (Cisco Secure Client) automated installer & setup for macOS.
#
#   1. Checks if Cisco Secure Client is already installed.
#   2. If not, downloads the installer from a GitHub Release and installs it.
#   3. Writes a connection profile so "vpn.ucsd.edu" is pre-filled - students don't have to type it.
#   4. Launches the client so all that's left is choosing a Group and logging in.
#
# IT ADMIN: edit the CONFIG block below before sharing this script with anyone.
#
# MONTHLY UPDATE PROCESS: when Cisco ships a new client, go to your GitHub repo's
# release tagged "latest", delete the old macOS asset, and upload the new
# installer with the EXACT SAME FILENAME as ASSET_NAME below. Nothing in this
# script needs to change - the download URL always resolves to whatever file is
# currently attached to that tag.

set -euo pipefail

# ======================== CONFIG (edit me) ========================
# Your GitHub repo, as "owner/repo" (e.g. "ucsd-oec/vpn-installer")
GITHUB_REPO="tgynl/vpn-installer"
# The exact filename you upload as a release asset each month - keep this identical every time
ASSET_NAME="CiscoSecureClient-macOS.pkg"
VPN_SERVER="vpn.ucsd.edu"
VPN_DISPLAY_NAME="vpn.ucsd.edu"
VPN_GROUP="secure-connect-allthru"

# Who is this copy of the script for? "student" = core VPN only. "employee" = VPN + ISE Posture.
# IT ADMIN: distribute two copies of this script - one with this set to "student", one to "employee".
AUDIENCE="student"   # "student" or "employee"
ISE_ASSET_NAME="CiscoISEPosture-macOS.pkg"
# ====================================================================

BLUE='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${BLUE}==> $1${NC}"; }
ok()   { echo -e "    ${GREEN}$1${NC}"; }
warn() { echo -e "    ${YELLOW}$1${NC}"; }
fail() { echo -e "    ${RED}$1${NC}"; }

echo -e "${BLUE}Rady Technology Services - Cisco Secure Client Installer${NC}"
echo ""

exit_with_message() {
  fail "$1"
  fail "If this keeps happening, contact IT support for a manual install."
  exit 1
}

if [ "$GITHUB_REPO" = "PUT_GITHUB_OWNER/PUT_GITHUB_REPO_HERE" ]; then
  exit_with_message "This script hasn't been configured with a real GitHub repo yet."
fi
if [ "$AUDIENCE" != "student" ] && [ "$AUDIENCE" != "employee" ]; then
  exit_with_message "AUDIENCE must be set to either 'student' or 'employee'."
fi

# Looks for the ISE Posture module's typical install location. Cisco's exact
# path can shift slightly between Secure Client versions - confirm this
# against one real installed Mac and adjust if needed.
is_ise_posture_installed() {
  [ -d "/opt/cisco/secureclient/iseposture" ] || [ -d "/opt/cisco/anyconnect/iseposture" ]
}

APP_PATH="/Applications/Cisco/Cisco Secure Client.app"

step "Checking for an existing Cisco Secure Client installation"
if [ -d "$APP_PATH" ]; then
  ok "Cisco Secure Client is already installed. Skipping install."
else
  step "Downloading the Cisco Secure Client installer"
  TMP_DIR="$(mktemp -d)"
  PKG_PATH="$TMP_DIR/$ASSET_NAME"
  DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/latest/download/${ASSET_NAME}"

  if ! curl -L --fail --silent --show-error -o "$PKG_PATH" "$DOWNLOAD_URL"; then
    exit_with_message "Automatic download failed."
  fi

  SIZE=$(stat -f%z "$PKG_PATH" 2>/dev/null || stat -c%s "$PKG_PATH")
  if [ "$SIZE" -lt 1000000 ]; then
    exit_with_message "Downloaded file looks too small - the download likely failed."
  fi
  ok "Downloaded to $PKG_PATH"

  step "Installing Cisco Secure Client (you'll be asked for your Mac password)"
  sudo installer -pkg "$PKG_PATH" -target /
  ok "Installation complete."
fi

# --- ISE Posture module (employees only - students should NOT have this installed) ---
if [ "$AUDIENCE" = "employee" ]; then
  step "Checking for ISE Posture module (required for employees)"
  if is_ise_posture_installed; then
    ok "ISE Posture module is already installed. Skipping."
  else
    step "Downloading the ISE Posture module"
    ISE_TMP_DIR="$(mktemp -d)"
    ISE_PKG_PATH="$ISE_TMP_DIR/$ISE_ASSET_NAME"
    ISE_DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/latest/download/${ISE_ASSET_NAME}"

    if ! curl -L --fail --silent --show-error -o "$ISE_PKG_PATH" "$ISE_DOWNLOAD_URL"; then
      exit_with_message "Automatic download of ISE Posture module failed."
    fi

    ISE_SIZE=$(stat -f%z "$ISE_PKG_PATH" 2>/dev/null || stat -c%s "$ISE_PKG_PATH")
    if [ "$ISE_SIZE" -lt 1000000 ]; then
      exit_with_message "Downloaded ISE Posture file looks too small - the download likely failed."
    fi
    ok "Downloaded to $ISE_PKG_PATH"

    step "Installing ISE Posture module"
    sudo installer -pkg "$ISE_PKG_PATH" -target /
    ok "ISE Posture module installed."
  fi
else
  ok "Student install - ISE Posture module is not required and will not be installed."
fi

step "Setting up '$VPN_SERVER' as the default connection"
PROFILE_DIR="/opt/cisco/secureclient/vpn/profile"
sudo mkdir -p "$PROFILE_DIR"
PROFILE_PATH="$PROFILE_DIR/UCSD.xml"

sudo tee "$PROFILE_PATH" > /dev/null <<XML
<?xml version="1.0" encoding="UTF-8"?>
<AnyConnectProfile xmlns="http://schemas.xmlsoap.org/encoding/">
  <ServerList>
    <HostEntry>
      <HostName>${VPN_DISPLAY_NAME}</HostName>
      <HostAddress>${VPN_SERVER}</HostAddress>
      <UserGroup>${VPN_GROUP}</UserGroup>
    </HostEntry>
  </ServerList>
</AnyConnectProfile>
XML
ok "Connection profile written to $PROFILE_PATH"

step "Launching Cisco Secure Client"
open -a "Cisco Secure Client"

echo -e "\n${BLUE}Installed! To finish connecting, do the following:${NC}"
echo -e ""
echo -e "${BLUE}  1. In the Cisco Secure Client window, pick '${VPN_DISPLAY_NAME}' from the list.${NC}"
echo -e "${BLUE}  2. Choose your Group (secure-connect-allthru or secure-connect-split) and log in with your Active Directory username and password.${NC}"
echo -e "${BLUE}  3. Approve the Duo two-step login prompt on your phone (required).${NC}"
if [ "$AUDIENCE" = "employee" ]; then
  echo -e "${BLUE}  4. You may briefly see an ISE Posture compliance check window after connecting - this is expected.${NC}"
fi
