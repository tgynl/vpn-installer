# Rady Technology Services - UCSD VPN Installer

This repo installs and sets up the Cisco Secure Client VPN automatically -
no manual downloads, no typing `vpn.ucsd.edu`, no digging through the KB
article. Run one command, then finish connecting in the app.

---

## Installing the VPN

### Windows

Open **PowerShell** (Windows key → type "PowerShell" → Enter), paste the
command for your role, and press Enter.

**Employees:**
```
irm https://raw.githubusercontent.com/tgynl/vpn-installer/main/install-ucsd-vpn-employee.ps1 | iex
```

**Students:**
```
irm https://raw.githubusercontent.com/tgynl/vpn-installer/main/install-ucsd-vpn-student.ps1 | iex
```

A second window will pop up asking for admin permission (UAC) - click **Yes**.
The first window closes once that happens; the real progress shows in the new
elevated window.

### macOS

Open **Terminal**, paste the command for your role, and press Enter.

**Employees:**
```
curl -fsSL https://raw.githubusercontent.com/tgynl/vpn-installer/main/install-ucsd-vpn-employee.sh | bash
```

**Students:**
```
curl -fsSL https://raw.githubusercontent.com/tgynl/vpn-installer/main/install-ucsd-vpn-student.sh | bash
```

It will ask for your Mac password partway through - that's expected, it's
needed to install software. If macOS blocks the download as "from an
unidentified developer," right-click the downloaded file and choose **Open**
instead of double-clicking it.

### What happens when you run it

1. Installs Cisco Secure Client (skipped automatically if already installed).
2. Employees only: installs the ISE Posture module, which is required for
   employees and not installed for students.
3. Sets up `vpn.ucsd.edu` so it's ready to go in the app - no typing required.
4. Opens Cisco Secure Client.

### Finishing the connection

Once the app opens:

1. Pick **`vpn.ucsd.edu`** from the list, and click **Connect**.
2. Choose your Group (**secure-connect-allthru** or **secure-connect-split**)
   and log in with your Active Directory username and password.
3. Approve the Duo two-step login prompt on your phone (required).
4. Employees only: you may briefly see an ISE Posture compliance check
   window after connecting - this is expected.

---

## About this repo

This repo has two independent parts:

- **Releases** hold the Cisco installer binaries (`.msi`/`.pkg` for the core
  VPN client and the ISE Posture module, in both x64 and ARM64 builds for
  Windows). The scripts always download whichever files are attached to the
  release tagged **`latest`**.
- **The `main` branch** holds the installer scripts themselves
  (`install-ucsd-vpn-employee.ps1`, `install-ucsd-vpn-student.ps1`,
  `install-ucsd-vpn-employee.sh`, `install-ucsd-vpn-student.sh`, plus `.cmd`
  double-click launchers for Windows). `raw.githubusercontent.com` serves
  files from here, which is what the copy-paste commands above pull from.

Keeping these separate means a monthly installer update never touches the
scripts, and a script change never touches the installer files.

### Students vs. employees: ISE Posture

Employees are required to have the Cisco ISE Posture module installed;
students should not have it. That's why there are separate `-student` and
`-employee` scripts, each with its audience already set correctly. The ISE
Posture install step is idempotent and independent of the core client check,
so if someone's status changes (e.g. a student becomes a TA/employee),
running the `-employee` script adds the missing module without touching
anything already installed.

> The "is ISE Posture already installed?" check relies on a best-known
> install path (macOS) / registry lookup (Windows). Cisco's exact layout can
> shift a little between Secure Client versions, so this is worth confirming
> against a real installed copy after any Cisco version update - see the
> `Test-CiscoModuleInstalled` function (Windows) or `is_ise_posture_installed`
> function (macOS) if it ever needs adjusting.

### Windows: x64 vs. ARM64

Both Windows scripts detect the device's processor architecture automatically
and download the matching installer - x64 or ARM64 - for both the core
client and, for employees, the ISE Posture module. This is fully automatic;
there's no separate command or link for ARM64 devices, and nothing changes
for the person running the script. The detected architecture is printed at
the top of the script's output for troubleshooting.

### Monthly updates (new Cisco Secure Client version)

Installer files live in the release tagged `latest`. When Cisco ships a new
version, the outdated asset - core client and/or ISE Posture, x64 and/or
ARM64, whichever changed - gets deleted from that release, and the new
installer is uploaded in its place under the **exact same filename** as
before. Nothing else changes: no script edits, no link swapping, no
re-signing. The download URLs in the scripts always resolve to whatever file
is currently attached to the `latest` tag.

If the VPN gateway supports pushing client updates to already-installed users
automatically, this step mostly only matters for new installs - worth
confirming with whoever manages the VPN headend.

### Updating the scripts themselves

Separately from installer updates, if the script logic changes (not the
Cisco installer, the `.ps1`/`.sh` code), the changed file gets re-uploaded to
the `main` branch with the identical filename, overwriting the old version.
No new release, tag, or link changes needed - the copy-paste commands always
pull whatever is currently on `main`.

### One-time setup (already done for this repo)

1. Create the GitHub repo (public, so downloads don't require
   authentication).
2. Create a release tagged `latest` and attach six installer files to it:
   - `CiscoSecureClient-Windows.msi` - core VPN module, Windows (x64)
   - `CiscoSecureClient-Windows-ARM64.msi` - core VPN module, Windows (ARM64)
   - `CiscoSecureClient-macOS.pkg` - core VPN module, macOS
   - `CiscoISEPosture-Windows.msi` - ISE Posture module, Windows (x64, employees only)
   - `CiscoISEPosture-Windows-ARM64.msi` - ISE Posture module, Windows (ARM64, employees only)
   - `CiscoISEPosture-macOS.pkg` - ISE Posture module, macOS (employees only)
3. Commit the four scripts to `main`
   (`install-ucsd-vpn-employee.ps1`, `install-ucsd-vpn-student.ps1`,
   `install-ucsd-vpn-employee.sh`, `install-ucsd-vpn-student.sh`).
4. Test all combinations (Windows x64 employee/student, Windows ARM64
   employee/student, Mac employee/student) on a clean machine, confirming the
   student copy does *not* end up with ISE Posture installed and the
   employee copy does.

### Windows elevation, technical note

Each script self-elevates (UAC prompt). When run via `irm | iex` there's no
local file to relaunch, so the script instead re-fetches and re-runs itself
from `$ScriptUrl` (set near the top of each `.ps1`) in a new elevated window.
`$ScriptUrl` needs to stay pointed at the correct raw GitHub URL for that copy
of the script if it's ever renamed or moved to a different repo.

### Known limitations

- **The repo is public**, meaning the installers and scripts are downloadable
  by anyone with the URL. Using a private repo instead would require an
  authenticated request (a GitHub token) for every download, adding a step
  for every user - a public repo is usually an acceptable tradeoff for a VPN
  client installer.
- **Windows execution policy**: the `.cmd` wrapper runs the `.ps1` with
  `-ExecutionPolicy Bypass` for that one run only - it does not change any
  permanent system setting.
- **Re-running is safe**: the scripts skip the install step(s) if already
  present, and just re-apply the connection profile and relaunch.
- **Trust boundary**: anyone with push access to `main` can control what the
  copy-paste commands execute with admin/sudo rights on every machine that
  runs them going forward - write access to this repo should be treated like
  any other admin credential.
