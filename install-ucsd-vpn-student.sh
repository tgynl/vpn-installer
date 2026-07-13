#!/usr/bin/env bash
#
# UCSD VPN (Cisco Secure Client) automated installer & setup for macOS.
#
#   1. Downloads the installer disk image (.dmg) from a GitHub Release.
#   2. Mounts it, finds the installer .pkg inside, and installs only the
#      modules this role needs (AnyConnect VPN, plus ISE Posture for
#      employees) via a choice-changes file - everything else Cisco bundles
#      (DART, NVM, Umbrella, ThousandEyes, ZTA, Duo) is excluded.
#   3. Writes a connection profile so "vpn.ucsd.edu" is pre-filled - users
#      don't have to type it.
#   4. Launches the client so all that's left is choosing a Group and logging in.
#
# IT ADMIN: edit the CONFIG block below before sharing this script with anyone.
#
# MONTHLY UPDATE PROCESS: when Cisco ships a new client, go to your GitHub repo's
# release tagged "latest", delete the old macOS asset, and upload the new
# installer with the EXACT SAME FILENAME as ASSET_NAME below. Nothing in this
# script needs to change - the download URL always resolves to whatever file is
# currently attached to that tag.
#
# If Cisco ever changes this package's internal choice identifiers (e.g. a
# future Secure Client version renames "choice_iseposture"), the choices file
# built further down will need updating to match. Regenerate the reference
# list with:
#   sudo installer -showChoiceChangesXML -pkg "/Volumes/.../Cisco Secure Client.pkg" -target / 

set -euo pipefail

# ======================== CONFIG (edit me) ========================
# Your GitHub repo, as "owner/repo" (e.g. "ucsd-oec/vpn-installer")
GITHUB_REPO="tgynl/vpn-installer"
# The exact filename you upload as a release asset each month - keep this identical every time
ASSET_NAME="CiscoSecureClient-macOS.dmg"
VPN_SERVER="vpn.ucsd.edu"
VPN_DISPLAY_NAME="vpn.ucsd.edu"
# NOTE: unlike Windows, macOS does not write a <UserGroup> into the profile.
# Testing showed the macOS client's connection was refused by the server
# when <UserGroup> was present - removing it fixed the connection. Users
# pick their Group manually from the dropdown in the app on macOS instead.

# Who is this copy of the script for? "student" = core VPN only. "employee" = VPN + ISE Posture.
# IT ADMIN: distribute two copies of this script - one with this set to "student", one to "employee".
AUDIENCE="student"   # "student" or "employee"
# ====================================================================

BLUE='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${BLUE}==> $1${NC}"; }
ok()   { echo -e "    ${GREEN}$1${NC}"; }
warn() { echo -e "    ${YELLOW}$1${NC}"; }
fail() { echo -e "    ${RED}$1${NC}"; }

echo -e "${BLUE}Rady Technology Services - Cisco Secure Client Installer${NC}"
echo ""

MOUNT_POINT=""
cleanup() {
  if [ -n "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
  fi
}
trap cleanup EXIT

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

APP_PATH="/Applications/Cisco/Cisco Secure Client.app"

if [ -d "$APP_PATH" ]; then
  ok "Cisco Secure Client is already installed - re-applying configuration for this role."
else
  ok "Cisco Secure Client is not yet installed - installing now."
fi

step "Downloading the Cisco Secure Client installer"
TMP_DIR="$(mktemp -d)"
DMG_PATH="$TMP_DIR/$ASSET_NAME"
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/latest/download/${ASSET_NAME}"

if ! curl -L --fail --silent --show-error -o "$DMG_PATH" "$DOWNLOAD_URL"; then
  exit_with_message "Automatic download failed."
fi

SIZE=$(stat -f%z "$DMG_PATH" 2>/dev/null || stat -c%s "$DMG_PATH")
if [ "$SIZE" -lt 1000000 ]; then
  exit_with_message "Downloaded file looks too small - the download likely failed."
fi
ok "Downloaded to $DMG_PATH"

step "Mounting the installer disk image"
ATTACH_OUTPUT=$(hdiutil attach "$DMG_PATH" -nobrowse -readonly 2>&1) || exit_with_message "Could not mount the downloaded disk image."
MOUNT_POINT=$(echo "$ATTACH_OUTPUT" | grep -Eo '/Volumes/.*$' | tail -1)
if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
  exit_with_message "Could not determine the mounted volume path for the disk image."
fi
ok "Mounted at $MOUNT_POINT"

step "Locating the installer package"
PKG_PATH=$(find "$MOUNT_POINT" -maxdepth 2 -iname "*.pkg" 2>/dev/null | head -1)
if [ -z "$PKG_PATH" ]; then
  exit_with_message "Could not find an installer .pkg inside the downloaded disk image."
fi
ok "Found $PKG_PATH"

# Only AnyConnect VPN (always) and ISE Posture (employees only) get installed.
# Everything else this package bundles by default - DART, Secure Firewall
# Posture, NVM, Umbrella, ThousandEyes, Duo, ZTA - is explicitly excluded to
# match the Windows deployment's footprint.
#
# NOTE: testing showed ISE Posture reports "Service is unavailable" in the
# client UI without Secure Firewall Posture also installed (the two modules
# appear to share an underlying posture engine) - this is a known open
# question, still being decided, not yet resolved in this script.
if [ "$AUDIENCE" = "employee" ]; then
  ISE_SELECTED=1
else
  ISE_SELECTED=0
fi

CHOICES_PATH="$TMP_DIR/choices.xml"
cat > "$CHOICES_PATH" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
	<dict>
		<key>attributeSetting</key>
		<integer>1</integer>
		<key>choiceAttribute</key>
		<string>selected</string>
		<key>choiceIdentifier</key>
		<string>choice_anyconnect_vpn</string>
	</dict>
	<dict>
		<key>attributeSetting</key>
		<integer>0</integer>
		<key>choiceAttribute</key>
		<string>selected</string>
		<key>choiceIdentifier</key>
		<string>choice_dart</string>
	</dict>
	<dict>
		<key>attributeSetting</key>
		<integer>0</integer>
		<key>choiceAttribute</key>
		<string>selected</string>
		<key>choiceIdentifier</key>
		<string>choice_secure_firewall_posture</string>
	</dict>
	<dict>
		<key>attributeSetting</key>
		<integer>${ISE_SELECTED}</integer>
		<key>choiceAttribute</key>
		<string>selected</string>
		<key>choiceIdentifier</key>
		<string>choice_iseposture</string>
	</dict>
	<dict>
		<key>attributeSetting</key>
		<integer>0</integer>
		<key>choiceAttribute</key>
		<string>selected</string>
		<key>choiceIdentifier</key>
		<string>choice_nvm</string>
	</dict>
	<dict>
		<key>attributeSetting</key>
		<integer>0</integer>
		<key>choiceAttribute</key>
		<string>selected</string>
		<key>choiceIdentifier</key>
		<string>choice_secure_umbrella</string>
	</dict>
	<dict>
		<key>attributeSetting</key>
		<integer>0</integer>
		<key>choiceAttribute</key>
		<string>selected</string>
		<key>choiceIdentifier</key>
		<string>choice_thousandeyes</string>
	</dict>
	<dict>
		<key>attributeSetting</key>
		<integer>0</integer>
		<key>choiceAttribute</key>
		<string>selected</string>
		<key>choiceIdentifier</key>
		<string>choice_duo</string>
	</dict>
	<dict>
		<key>attributeSetting</key>
		<integer>0</integer>
		<key>choiceAttribute</key>
		<string>selected</string>
		<key>choiceIdentifier</key>
		<string>choice_zta</string>
	</dict>
	<dict>
		<key>attributeSetting</key>
		<integer>1</integer>
		<key>choiceAttribute</key>
		<string>selected</string>
		<key>choiceIdentifier</key>
		<string>choice_ui</string>
	</dict>
</array>
</plist>
PLIST_EOF

step "Installing Cisco Secure Client (you'll be asked for your Mac password)"
INSTALL_EXIT=0
sudo installer -pkg "$PKG_PATH" -target / -applyChoiceChangesXML "$CHOICES_PATH" || INSTALL_EXIT=$?

step "Ejecting installer disk image"
hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || warn "Could not cleanly eject the disk image (non-fatal)."
MOUNT_POINT=""

if [ "$INSTALL_EXIT" -ne 0 ]; then
  exit_with_message "Installer exited with code $INSTALL_EXIT."
fi
ok "Installation complete."

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
      <BackupServerList>
        <HostAddress>vpn-1.ucsd.edu</HostAddress>
        <HostAddress>vpn-2.ucsd.edu</HostAddress>
      </BackupServerList>
    </HostEntry>
  </ServerList>
</AnyConnectProfile>
XML
ok "Connection profile written to $PROFILE_PATH"

step "Launching Cisco Secure Client"
open -a "Cisco Secure Client"

echo -e "\n${BLUE}Done! To finish connecting, do the following:${NC}"
echo -e ""
echo -e "${BLUE}  1. In the Cisco Secure Client window, pick '${VPN_DISPLAY_NAME}' from the list, and click on 'Connect'.${NC}"
echo -e "${BLUE}  2. Choose your Group (secure-connect-allthru or secure-connect-split) and log in with your Active Directory username and password.${NC}"
echo -e "${BLUE}  3. Approve the Duo two-step login prompt on your phone (required).${NC}"
if [ "$AUDIENCE" = "employee" ]; then
  echo -e "${BLUE}  4. You may briefly see an ISE Posture compliance check window after connecting - this is expected.${NC}"
fi
