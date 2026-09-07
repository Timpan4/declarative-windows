# declarative-windows

> Declarative Windows configuration management - like NixOS, but for Windows

**Goal:** Reinstall Windows every 2 months without manual reconfiguration.

---

## ⚠️ Project Status: Implementation Phase

**MVP scripts exist** (`bootstrap.ps1`, `build-iso.ps1`) and are in active development.

See [TODO.md](TODO.md) for remaining implementation tasks.

---

## Overview

Fully automated Windows setup through:

- **WinGet** - Declarative app installation from apps.json
- **Sophia Script** - OS tweaks and debloating
- **AutoUnattend.xml** - Automated Windows installation
- **Custom ISO** - One-command ISO generation

### MVP Workflow

```powershell
# 0. Back up files and personal repo config to another drive
.\preflight-backup.ps1 -DestinationRoot "E:\"

# 1. Generate custom Windows ISO (one command)
.\build-iso.ps1 -SourceISO "Win11.iso" -OutputISO "Win11_Custom.iso"

# 2. Boot from ISO - choose the target disk/partition in Windows Setup

# 3. Restore files later from the desktop shortcut
```

Windows Setup still requires you to choose the install disk and partition layout manually. After first login, the repo is restored by cloning the original remote into `%USERPROFILE%\Documents\declarative-windows`. If cloning fails, setup continues from `C:\Setup` and the summary tells you to retry the clone later.

---

## Pre-installed Windows Optimization (Planned)

This project will also support running on an existing Windows 11 install (no ISO needed). The planned “local mode” will:

- Apply app installs via WinGet
- Run Sophia Script tweaks (auto-download Sophia if missing)
- Perform bloat removal on the existing system
- Create a system restore point before changes
- Work from the repo directory (no `C:\Setup` required)

See `TODO.md` for implementation tasks.

---

## Getting Started

### 1. Export Your Apps

```powershell
# Export all WinGet-managed apps
winget export -o apps.json

# Or only from winget source (cleaner)
winget export -o apps.json --source winget
```

**Note:** Only captures apps installed via WinGet.

For personal usage, keep `apps.json`, `optional-apps.json`, and `config\backup.json` out of git. The repo ships `apps-template.json`, `optional-apps-template.json`, and `config\backup.template.json`, and the backup workflow preserves your personal files so they can be restored into the cloned repo after reinstall.

If you want a second-stage app list, create `optional-apps.json` alongside `apps.json`. Start from `optional-apps-template.json` if you want an example. `apps.json` installs automatically during bootstrap, while `optional-apps.json` is offered with a yes/no prompt after first login and can also be installed later from a desktop shortcut.

### Backup Before Reinstall

Create a personal backup config by copying `config\backup.template.json` to `config\backup.json`, then enable the known folders and extra paths you want to preserve.

`excludePatterns` accepts recursive directory exclusions such as `**\node_modules\**` and filename patterns such as `*.tmp` or `private.txt`. Directory names are matched at every depth; filename patterns apply at every depth. Escape backslashes in JSON. Other path patterns are rejected before backup directories are created. These exclusions apply to configured folder copies, not the separate personal repo-file backup.

Enabled rules must have distinct names or labels after punctuation is replaced with hyphens and case is normalized. Empty normalized labels are rejected. Each backup also needs a new session name. An existing session is never resumed or overwritten, including with `-Force`.

```powershell
.\preflight-backup.ps1 -DestinationRoot "E:\"
```

This backs up:

- Standard folders such as Desktop, Documents, and Pictures
- Extra declarative paths from `config\backup.json`
- Personal repo files like `apps.json` and `config\backup.json`
- A backup manifest containing the original repo remote URL

### 2. Edit Your App List

Copy `apps-template.json` to `apps.json`, then remove unwanted apps:

```json
{
  "$schema": "https://aka.ms/winget-packages.schema.2.0.json",
  "Sources": [
    {
      "Packages": [
        {
          "PackageIdentifier": "Mozilla.Firefox"
        },
        {
          "PackageIdentifier": "7zip.7zip"
        }
      ],
      "SourceDetails": {
        "Name": "winget"
      }
    }
  ]
}
```

### 3. Test Your App List

```powershell
# Read-only inspection of the requested package IDs and versions
$manifest = Get-Content -LiteralPath .\apps.json -Raw | ConvertFrom-Json
$manifest.Sources.Packages | Select-Object PackageIdentifier, Version

# Installs applications (test in a disposable VM)
winget import apps.json --accept-package-agreements --accept-source-agreements
```

JSON inspection does not resolve package availability or predict installation results.

Bootstrap supports `PackageIdentifier` and an optional exact `Version` for each package. `SourceDetails.Name` selects an already registered source; supplied `Identifier`, `Argument`, and `Type` must match that registration. Source and version remain attached to the request during inventory checks, installation, and user-scope retry. Identical IDs from different sources remain separate requests. Omitting `SourceDetails` keeps WinGet's default source selection. Other installation fields, including `Scope`, `Channel`, and installer override arguments, are rejected before installation.

WinGet must be available through Microsoft App Installer for the current user. An unavailable client produces one prerequisite failure. Bootstrap refreshes its process PATH from the registered machine and user paths so tools installed during setup can be discovered later in the same run.

Package outcomes in `state.json` distinguish `verified`, `unverified`, and `failed`, with the requested source/version, exit code, and diagnostic category. An unverified success is checked again on the next ordinary run; a package that is then discoverable is not reinstalled. Summaries preserve hash-mismatch failures without copying arbitrary installer output. Full native output stays in `install.log`.

[`winget import`](https://learn.microsoft.com/en-us/windows/package-manager/winget/import)
installs applications. `--ignore-versions` installs the latest available versions;
it is not a dry-run option.

Optional apps can use the same manifest format:

```powershell
Copy-Item optional-apps-template.json optional-apps.json
# Then edit optional-apps.json for apps you want to install later
```

### 4. Find Package IDs

```powershell
# Search for an app
winget search firefox

# Show package details
winget show Mozilla.Firefox
```

### 5. Test Sophia Script Locally (Optional)

If you want to test OS tweaks before automation:

```powershell
# 1. Download Sophia Script for Windows 11
Invoke-WebRequest -Uri "https://github.com/farag2/Sophia-Script-for-Windows/releases/download/7.3.0/Sophia.Script.for.Windows.11.v7.3.0.zip" -OutFile "SophiaScript.zip"
if ((Get-FileHash -LiteralPath .\SophiaScript.zip -Algorithm SHA256).Hash -ne 'd342149e13053ea87c6119706a1f9d7d56d08c6e55ced113b1c32a30e7873bf2') {
    throw 'Sophia release SHA-256 mismatch'
}

# 2. Extract the archive
Expand-Archive -Path "SophiaScript.zip" -DestinationPath ".\SophiaScript" -Force

# 3. Run only the custom preset (as Administrator, from this repo)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\modules\Run-SophiaPreset.ps1 `
    -FrameworkRoot ".\SophiaScript\Sophia_Script_for_Windows_11_v7.3.0" `
    -PresetPath ".\Sophia-Preset.ps1" -CompletionPath ".\sophia-test.completed"
```

Bootstrap verifies this [7.3.0 release digest](https://github.com/farag2/Sophia-Script-for-Windows/releases/tag/7.3.0) before extraction. It retains `.release.zip` and checks cached framework files against that archive before reuse. If an older cache lacks the archive or its files have changed, move that Sophia cache directory aside and rerun setup to download a verified copy.

**Important:**
- Always test in a VM first before running on your main PC
- Review `Sophia-Preset.ps1` and customize it for your needs
- Requires Administrator privileges

---

## Project Structure

```
declarative-windows/
├── README.md              # This file
├── TODO.md                # Implementation tasks
├── RESEARCH.md            # Investigation tasks
├── CLAUDE.md              # Project guidance for Claude Code
├── brainstorm.md          # Design discussions
│
├── apps-template.json     # Example auto-installed WinGet package list
├── optional-apps-template.json # Example prompted/later WinGet package list
├── Sophia-Preset.ps1      # Custom Sophia Script configuration
├── autounattend.xml       # Windows unattended install config
├── bootstrap.ps1          # Main orchestration script
├── build-iso.ps1          # ISO generation script
├── apply-registry.ps1     # Registry fallback apply script
│
└── config/                # Optional configs
    ├── registry.json
    ├── features.json
    └── settings.json
```

---

## Windows Version Support

**Supported:** Windows 11 (25H2 or later)

**Not Supported:** Windows 10

---

## Security Warning

⚠️ Configuration files can contain sensitive information.

See [SECURITY.md](SECURITY.md) for what to avoid committing to Git.

---

## Documentation

- [docs/ISO-GENERATION.md](docs/ISO-GENERATION.md) - ISO creation guide
- `config/backup.template.json` - Shared backup template
- [FAQ.md](FAQ.md) - Frequently asked questions
- [SECURITY.md](SECURITY.md) - Security best practices
- [TODO.md](TODO.md) - Implementation tasks
- [RESEARCH.md](RESEARCH.md) - Investigation tasks

---

## Resources

- [WinGet Documentation](https://learn.microsoft.com/en-us/windows/package-manager/winget/)
- [Sophia Script](https://github.com/farag2/Sophia-Script-for-Windows)
- [Schneegans Unattend Generator](https://schneegans.de/windows/unattend-generator/)
- [Windows ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install)
