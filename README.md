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

For personal usage, keep `apps.json` out of git. The repo ships `apps-template.json`, and the backup workflow preserves your personal `apps.json` so it can be restored into the cloned repo after reinstall.

If you want a second-stage app list, create `optional-apps.json` alongside `apps.json`. `apps.json` installs automatically during bootstrap, while `optional-apps.json` is offered with a yes/no prompt after first login and can also be installed later from a desktop shortcut.

### Backup Before Reinstall

Create a personal backup config by copying `config\backup.template.json` to `config\backup.json`, then enable the known folders and extra paths you want to preserve.

```powershell
.\preflight-backup.ps1 -DestinationRoot "E:\"
```

This backs up:

- Standard folders such as Desktop, Documents, and Pictures
- Extra declarative paths from `config\backup.json`
- Personal repo files like `apps.json` and `config\backup.json`
- A backup manifest containing the original repo remote URL

### 2. Edit Your App List

Open `apps.json` and remove unwanted apps:

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
# Dry run
winget import apps.json --ignore-versions

# Actual import (test in VM)
winget import apps.json --accept-package-agreements --accept-source-agreements
```

Optional apps can use the same manifest format:

```powershell
Copy-Item apps.json optional-apps.json
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
Invoke-WebRequest -Uri "https://github.com/farag2/Sophia-Script-for-Windows/releases/latest/download/Sophia.Script.for.Windows.11.v7.1.4.zip" -OutFile "SophiaScript.zip"

# 2. Extract the archive
Expand-Archive -Path "SophiaScript.zip" -DestinationPath ".\SophiaScript" -Force

# 3. Copy the preset file to Sophia folder
Copy-Item ".\Sophia-Preset.ps1" -Destination ".\SophiaScript\"

# 4. Run with custom preset (as Administrator)
cd .\SophiaScript
.\Sophia.ps1 -Preset .\Sophia-Preset.ps1
```

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
├── apps.json              # Auto-installed WinGet package list
├── optional-apps.json     # Prompted/later WinGet package list (optional)
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

**Supported:** Windows 11 (24H2 or later)

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
