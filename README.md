# declarative-windows

> Declarative Windows configuration management - like NixOS, but for Windows

**Goal:** Reinstall Windows every 2 months without manual reconfiguration.

---

## ⚠️ Project Status: Planning Phase

**No scripts exist yet.** This is currently planning and documentation.

See [TODO.md](TODO.md) for implementation tasks.

---

## Overview

Fully automated Windows setup through:

- **WinGet** - Declarative app installation from apps.json
- **Sophia Script** - OS tweaks and debloating
- **AutoUnattend.xml** - Automated Windows installation
- **Custom ISO** - One-command ISO generation

### Planned Workflow

```powershell
# 1. Generate custom Windows ISO (one command)
.\build-iso.ps1 -SourceISO "Win11.iso" -OutputISO "Win11_Custom.iso"

# 2. Boot from ISO - everything installs automatically

# 3. (Optional) Re-run setup anytime from desktop shortcut
```

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
Invoke-WebRequest -Uri "https://github.com/farag2/Sophia-Script-for-Windows/releases/latest/download/Sophia.Script.for.Windows.11.v6.9.1.zip" -OutFile "SophiaScript.zip"

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
├── apps.json              # Your WinGet package list (create this)
├── Sophia-Preset.ps1      # Custom Sophia Script configuration
├── autounattend.xml       # Windows unattended install config
├── bootstrap.ps1          # Main orchestration script (planned)
├── build-iso.ps1          # ISO generation script (planned)
│
└── config/                # Optional configs (planned)
    ├── registry.json
    ├── features.json
    └── settings.json
```

---

## Windows Version Support

**Supported:** Windows 11 (22H2 or later)

**Not Supported:** Windows 10

---

## Security Warning

⚠️ Configuration files can contain sensitive information.

See [SECURITY.md](SECURITY.md) for what to avoid committing to Git.

---

## Documentation

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
