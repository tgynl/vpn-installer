# UCSD VPN Installer Scripts - Setup Guide (for IT/admin)

These scripts automate the parts of our VPN setup instructions that trip people
up most: finding the download, running the installer, restarting, and typing
`vpn.ucsd.edu` correctly. Students/faculty just run one file, then pick a Group
and log in with Duo.

**GitHub repo configured:** `tgynl/vpn-installer` (create this repo before distributing anything).

## Files

| File | Platform | Audience |
|---|---|---|
| `install-ucsd-vpn-student.ps1` + `install-ucsd-vpn-student.cmd` | Windows | Students |
| `install-ucsd-vpn-employee.ps1` + `install-ucsd-vpn-employee.cmd` | Windows | Employees |
| `install-ucsd-vpn-student.sh` | macOS | Students |
| `install-ucsd-vpn-employee.sh` | macOS | Employees |

Each `.cmd` is just a double-click launcher for its matching `.ps1` - always keep them in the same folder.

## Students vs. employees: ISE Posture

Employees are required to have the Cisco ISE Posture module installed;
students should **not** have it. That's why there are separate `-student` and
`-employee` files - each has its `Audience`/`AUDIENCE` setting already set
correctly, so you just need to distribute the right file to the right group
(e.g. a student portal page and a staff portal page).

The ISE Posture install step is idempotent and separate from the core client
check, so if someone's status changes (e.g. a student becomes a TA/employee),
having them run the `-employee` script will add the missing module without
touching anything already installed.

> The script's ISE Posture "already installed?" check uses a best-known
> install path (macOS) / registry lookup (Windows). Cisco's exact layout can
> shift a little between Secure Client versions, so it's worth confirming
> this check actually detects a real installed copy before wide distribution
> - see the `Test-CiscoModuleInstalled` function (Windows) or
> `is_ise_posture_installed` function (macOS) if you need to adjust it.

## One-time setup before you share these

1. **Create the GitHub repo** `tgynl/vpn-installer` (public is simplest -
   no auth needed for downloads).
2. **Create a release tagged `latest`** and upload four installer files to it:
   - `CiscoSecureClient-Windows.msi` - core VPN module, Windows
   - `CiscoSecureClient-macOS.pkg` - core VPN module, macOS
   - `CiscoISEPosture-Windows.msi` - ISE Posture module, Windows (employees only)
   - `CiscoISEPosture-macOS.pkg` - ISE Posture module, macOS (employees only)

   GitHub gives release assets a permanent alias URL that always points at
   whatever file currently has that name under the `latest` tag - that's what
   makes monthly updates painless (see below).

3. **Test all four combinations** (Windows student, Windows employee, Mac
   student, Mac employee) on a clean (or VM) machine before distributing.
   Specifically confirm the student copy does *not* end up with ISE Posture
   installed, and the employee copy does.

## Monthly update process (when Cisco ships a new client)

1. Go to your GitHub repo → Releases → the `latest` release.
2. Delete the old asset(s) - core client and/or ISE Posture, whichever changed.
3. Upload the new installer(s) with the **exact same filenames** as before.

That's it - no script edits, no link swapping, no re-signing. The download
URLs in both scripts always resolve to whatever file is currently attached to
that tag.

If your VPN gateway supports pushing client updates to already-installed
users automatically, this monthly step mostly only matters for *new* installs
- worth confirming with whoever manages the VPN headend.

## Distributing to students/faculty

- **Windows users**: give students `install-ucsd-vpn-student.ps1` +
  `install-ucsd-vpn-student.cmd` (same folder), and give employees
  `install-ucsd-vpn-employee.ps1` + `install-ucsd-vpn-employee.cmd`. Tell them
  to double-click the `.cmd` file. It will prompt for admin approval (UAC) -
  that's expected.
- **macOS users**: give students `install-ucsd-vpn-student.sh` and employees
  `install-ucsd-vpn-employee.sh`. Tell them to open Terminal, `cd` to the
  folder it's in, and run e.g. `./install-ucsd-vpn-student.sh`. It will ask
  for their Mac password (that's `sudo`, needed to install software).
  - If macOS blocks it as "from an unidentified developer," they can instead
    right-click the file → **Open**, or run `chmod +x install-ucsd-vpn-student.sh` first.

## What each script does, step by step

1. Checks whether Cisco Secure Client is already installed - if so, skips
   straight to the next step so re-runs are harmless.
2. Downloads the installer from your GitHub Release and installs it
   silently (no click-through wizard).
3. **Employee copies only:** checks whether the ISE Posture module is already
   installed, and if not, downloads and installs it too. Student copies skip
   this entirely.
4. Writes a small connection profile so `vpn.ucsd.edu` shows up automatically
   in the client - no typing required.
5. Launches Cisco Secure Client. The user's only remaining steps are picking
   their Group (e.g. `2-Step Secured - allthruucsd`) and logging in with their
   AD username/password + Duo.

## Known limitations / things to watch

- **Group selection isn't pre-set.** The Group dropdown is populated by the
  VPN server itself after the host is selected, so we can't safely hardcode
  which group (split vs. allthruucsd vs. 2-Step variants) every user should
  pick - that depends on what they're doing. If your users are overwhelmingly
  one profile, let me know and I can look at whether it's safe to default it.
- **Public repo means the installers are downloadable by anyone with the
  URL**, same as the Google Drive link would have been. If that's a concern,
  use a private repo instead, but note that raw/asset downloads from a private
  repo require an authenticated request (a GitHub token), which adds a step
  for every user - most schools find a public repo an acceptable tradeoff for
  something that's just a VPN client installer.
- **Windows execution policy**: the `.cmd` wrapper runs the `.ps1` with
  `-ExecutionPolicy Bypass` for that one run only - it does not change any
  permanent system setting.
- **Re-running is safe**: both scripts skip the install step if the client is
  already present, and just re-apply the connection profile and relaunch.

## Updating for a new Cisco Secure Client version

See "Monthly update process" above - just replace the release asset, keeping
the filename identical. No script changes needed.
