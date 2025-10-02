# declarative-windows

> Declarative Windows configuration management - like NixOS, but for Windows

**Goal:** Reinstall Windows every 2 months without manual reconfiguration. One command creates a custom ISO, boot from it, and everything installs automatically.

---

## ⚠️ Project Status: Planning Phase

This project is currently in the planning and documentation phase. Scripts are not yet implemented.

See [TODO.md](TODO.md) for implementation tasks and [RESEARCH.md](RESEARCH.md) for investigation tasks.

---

## Overview

This project enables fully automated Windows setup through:

- **WinGet** - Declarative application installation from apps.json
- **Sophia Script** - OS tweaks, registry modifications, and debloating
- **AutoUnattend.xml** - Automated Windows installation configuration
- **Custom ISO** - One-command ISO generation with all configs baked in

### Key Features (Planned)

- ✅ **Idempotent** - Safe to run multiple times without breaking
- ✅ **Automated** - Runs automatically after Windows install
- ✅ **Recoverable** - Desktop shortcut allows manual re-runs
- ✅ **Transparent** - Clear logs show what succeeded/failed/skipped
- ✅ **Shareable** - Fork and customize for your own setup

---

## Getting Started

### 1. Export Your Current Apps

First, export your currently installed applications to create your `apps.json` file:

```powershell
# Export all WinGet-managed apps to apps.json
winget export -o apps.json

# Or export only from winget source (cleaner list)
winget export -o apps.json --source winget
```

**Note:** This only captures apps installed via WinGet. Manually installed apps won't appear.

**To see what will be exported:**

```powershell
# List all apps WinGet knows about
winget list
```

---

### 2. Review and Edit Your App List

The exported `apps.json` contains all your WinGet apps. You'll likely want to remove some:

#### Option A: Manual JSON Editing

Open `apps.json` in a text editor. The file structure looks like this:

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
          "PackageIdentifier": "Microsoft.VisualStudioCode"
        },
        {
          "PackageIdentifier": "Adobe.Acrobat.Reader.64-bit"
        }
      ],
      "SourceDetails": {
        "Name": "winget"
      }
    }
  ]
}
```

**To remove an app:** Delete the entire package block (including the curly braces and comma).

**Common apps you might want to remove:**

- Bloatware that came pre-installed
- Trial software you don't use
- Apps specific to one machine

#### Option B: Start Fresh (Recommended for First Time)

Instead of editing the export, create a new `apps.json` with only the apps you want:

1. Look at the exported `apps.json` to see package identifiers
2. Create a new `apps.json` with only your essentials
3. Use the structure above as a template

**Example minimal apps.json:**

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
        },
        {
          "PackageIdentifier": "Git.Git"
        }
      ],
      "SourceDetails": {
        "Name": "winget"
      }
    }
  ]
}
```

---

### 3. Test Your App List

Before using `apps.json` in automation, test it manually:

```powershell
# Dry run - see what would be installed without actually installing
winget import apps.json --ignore-versions

# If the above looks good, test the actual import (optional - use in VM)
winget import apps.json --accept-package-agreements --accept-source-agreements
```

**Tips:**

- Use `--ignore-versions` to install latest versions instead of specific versions
- Test in a VM before using in your custom ISO
- Keep a backup of working `apps.json` files

---

### 4. Finding Package Identifiers

To add new apps to your `apps.json`, you need their package identifier:

```powershell
# Search for an app
winget search firefox

# Get exact package ID
winget search --id Mozilla.Firefox

# Show details about a package
winget show Mozilla.Firefox
```

Then add the `PackageIdentifier` to your `apps.json` file.

---

### 5. Review autounattend.xml (Optional)

The repository includes `autounattend.xml` which automates Windows 11 installation.

**What it does:**
- Automates disk partitioning (wipes disk, creates EFI + Windows partitions)
- Skips Windows OOBE screens (privacy, region, etc.)
- Creates local user account named "User"
- Runs `bootstrap.ps1` automatically after first login via FirstLogonCommands

**Passwords & Product Keys:**
- Password field is LEFT BLANK - Windows prompts during installation
- Product key is LEFT BLANK - Windows prompts or activates automatically
- **Safe to commit** - no secrets in the file

**Customize if needed:**
- Change username from "User" to your preferred name
- Change timezone from "UTC" to your timezone
- Adjust locale/language settings (default: en-US)

**To use a different autounattend.xml:**
- Generate your own at [Schneegans Unattend Generator](https://schneegans.de/windows/unattend-generator/)
- Make sure to add FirstLogonCommands to run `C:\Setup\bootstrap.ps1`
- See CLAUDE.md for FirstLogonCommands template

---

## Planned Workflow (Not Yet Implemented)

Once scripts are complete, the workflow will be:

```powershell
# 1. Generate custom Windows ISO (one command)
.\build-iso.ps1 -SourceISO "Win11.iso" -OutputISO "Win11_Custom.iso"

# 2. Burn ISO to USB or boot in VM

# 3. Boot from ISO - everything installs automatically
#    - Windows setup runs with autounattend.xml
#    - Files copied to C:\Setup
#    - Apps installed from apps.json
#    - OS tweaks applied via Sophia Script
#    - Desktop shortcut created for re-runs

# 4. (Optional) Re-run setup anytime from desktop shortcut
```

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
├── autounattend.xml       # Windows unattended install config (planned)
├── bootstrap.ps1          # Main orchestration script (planned)
├── build-iso.ps1          # ISO generation script (planned)
│
└── config/                # Optional additional configs (planned)
    ├── registry.json      # Registry tweaks
    ├── features.json      # Windows features to enable/disable
    └── settings.json      # Other OS settings
```

---

## Windows Version Support

**Supported:** Windows 11 (22H2 or later)

**Not Supported:** Windows 10

This project is designed specifically for Windows 11 and uses features/tools that may not be available or work correctly on Windows 10.

---

## Known Limitations

While this project automates most of the Windows setup process, there are some limitations:

- **WinGet-only apps:** Only applications available in the WinGet repository can be installed automatically. Not all software is in WinGet.
- **Manual apps:** Applications installed outside of WinGet must be added manually after automation completes.
- **BIOS/UEFI settings:** Cannot configure hardware-level settings (boot order, secure boot, etc.)
- **Restart required:** Many Windows tweaks require a restart to take effect fully.
- **Network dependency:** WinGet requires an internet connection. Offline installation is not supported.
- **Sophia Script compatibility:** Some tweaks may be Windows version-specific or require certain Windows editions.
- **FirstLogonCommands timing:** Scripts run during first login, so very early Windows setup steps cannot be automated.

---

## Security Warning

⚠️ **IMPORTANT:** This project involves configuration files that can contain sensitive information.

**Never commit these files to Git:**

- `autounattend.xml` (may contain passwords, product keys, Wi-Fi credentials)
- `apps.json` (your personal app list - may reveal private information)
- Any file with sensitive personal data

**The included `.gitignore` file protects most sensitive files automatically.**

See [SECURITY.md](SECURITY.md) for detailed security guidelines before sharing your configuration with friends.

---

## Additional Documentation

- [FAQ.md](FAQ.md) - Frequently asked questions
- [SECURITY.md](SECURITY.md) - Security best practices
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [TODO.md](TODO.md) - Implementation tasks
- [RESEARCH.md](RESEARCH.md) - Investigation tasks

---

## Resources

- [WinGet Documentation](https://learn.microsoft.com/en-us/windows/package-manager/winget/)
- [Sophia Script](https://github.com/farag2/Sophia-Script-for-Windows) - Windows tweaking framework
- [Schneegans Unattend Generator](https://schneegans.de/windows/unattend-generator/) - Create autounattend.xml files
- [Windows ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) - Contains oscdimg.exe for ISO creation

---

## About This Project

This is a personal project for managing Windows 11 installations. It's designed for personal use and sharing with friends. Feel free to fork and customize for your own setup.
