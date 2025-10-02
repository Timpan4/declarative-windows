# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⚠️ Current Project Phase: PLANNING

This project is currently in the **planning and documentation phase**.

**DO NOT create any PowerShell scripts (.ps1 files) yet.** Only work on:

- Documentation files (README.md, TODO.md, RESEARCH.md, etc.)
- Planning and design documents
- Configuration file schemas and examples

Script implementation will begin after the planning phase is complete.

---

## 🪟 Windows Version Support

**Supported:** Windows 11 (22H2 or later) ONLY

**Not Supported:** Windows 10

This project is designed exclusively for Windows 11. Do not implement or test Windows 10 compatibility. All documentation, scripts, and configurations should assume Windows 11.

---

## Project Overview

**declarative-windows** is a project for declarative Windows configuration management, similar to NixOS but for Windows. The goal is to enable quick reinstallation of Windows every 2 months without manual reconfiguration.

The project aims to provide:

- Declarative application installation via WinGet
- OS-specific settings and registry tweaks
- Windows features configuration
- Shareable configuration for consistent setups across machines

## Current State

This is an early-stage project currently in the planning phase. See `brainstorm.md` for research and design discussions.

## Planned Architecture

Based on brainstorming in `brainstorm.md`, the intended solution combines:

1. **WinGet** - For application installation
   - Export current apps: `winget export -o apps.json`
   - Import on fresh install: `winget import apps.json`

2. **Sophia Script** - For Windows OS tweaks and registry modifications
   - Customizable preset files for system configuration

3. **AutoUnattend.xml Integration** - For automated setup during Windows installation
   - Uses `FirstLogonCommands` to run setup scripts automatically

## Intended Repository Structure

```
declarative-windows/
├── build-iso.ps1          # ISO generation script (one command to build custom ISO)
├── bootstrap.ps1          # Main orchestration script (idempotent, runs auto + manual)
├── apps.json              # WinGet package export
├── Sophia.ps1             # Customized Sophia Script preset
├── autounattend.xml       # Windows unattended installation config
├── config/
│   ├── registry.json      # Registry tweaks
│   ├── features.json      # Windows features to enable/disable
│   └── settings.json      # Other OS settings
├── docs/
│   └── ISO-GENERATION.md  # Detailed ISO creation guide
├── TODO.md                # Implementation tasks
├── RESEARCH.md            # Research and investigation tasks
└── CLAUDE.md              # This file
```

## Workflows

### Workflow 1: Custom ISO Generation (Recommended)

**Goal:** Create a custom Windows ISO with all configs baked in - one command, fully automated

```bash
# 1. Generate custom ISO (one command)
.\build-iso.ps1 -SourceISO "Win11_English_x64.iso" -OutputISO "Win11_Custom.iso"

# 2. Burn ISO to USB or boot in VM

# 3. Boot from ISO - Windows installs automatically with:
#    - autounattend.xml configures Windows setup
#    - Files copied to C:\Setup via $OEM$ folder
#    - bootstrap.ps1 runs automatically after first login
#    - Desktop shortcut created for manual re-runs

# 4. (Optional) Re-run anytime by clicking desktop shortcut
```

**ISO Structure (created by build-iso.ps1):**

```
Custom-ISO:\
├── sources\              # Windows install files
├── autounattend.xml      # Placed in root for auto-execution
└── $OEM$\
    └── $$\
        └── Setup\        # Files copied to C:\Setup during install
            ├── bootstrap.ps1
            ├── apps.json
            └── Sophia.ps1
```

**On installed system:**

```
C:\
├── Setup\
│   ├── bootstrap.ps1
│   ├── apps.json
│   ├── Sophia.ps1
│   └── install.log       # Detailed execution log
└── Users\
    └── [Username]\
        └── Desktop\
            ├── Setup Summary.txt           # Visual status report
            └── Run Windows Setup.lnk       # Shortcut to re-run bootstrap
```

### Workflow 2: Manual USB Setup (Alternative)

If you don't want to generate a custom ISO, manually create USB structure:

```bash
# 1. Create Windows install USB with Rufus/Media Creation Tool
# 2. Copy files to USB in $OEM$ structure (see above)
# 3. Copy autounattend.xml to USB root
# 4. Boot from USB
```

## Key Features

### Idempotency

`bootstrap.ps1` is **idempotent** - safe to run multiple times:

- Checks if apps already installed before installing
- Skips registry tweaks already applied
- Creates logs showing: ✓ completed, ⚠ skipped, ✗ failed

### Dual Execution Mode

1. **Automatic:** Runs via `FirstLogonCommands` in autounattend.xml
2. **Manual:** Desktop shortcut allows re-running anytime

### Comprehensive Logging

- **Desktop Summary:** `C:\Users\[User]\Desktop\Setup Summary.txt` - Quick visual status
- **Detailed Log:** `C:\Setup\install.log` - Full execution details for troubleshooting

## Key References

- [Sophia Script](https://github.com/farag2/Sophia-Script-for-Windows) - Windows tweaking script
- [Schneegans Unattend Generator](https://schneegans.de/windows/unattend-generator/) - Web-based autounattend.xml generator
- [Windows ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) - Contains oscdimg.exe for ISO creation
- WinGet documentation for package management

## Design Principles

1. **Declarative:** Configuration defined in files (apps.json, Sophia.ps1), not imperative scripts
2. **Idempotent:** Safe to run multiple times, won't duplicate or break
3. **Automated:** Runs automatically on first boot, no interaction needed
4. **Recoverable:** Can re-run manually if anything fails
5. **Transparent:** Clear logs show exactly what happened
6. **Shareable:** Friends can fork and customize for their own setups

---

## Security Guidelines

### Sensitive Files - Never Create With Real Data

When implementing scripts, **never hardcode sensitive data**. These files may contain secrets:

- **autounattend.xml** - May contain passwords, product keys, Wi-Fi credentials
- **apps.json** (personal) - May reveal personal/work information
- **config files** - May contain API keys, personal paths

### File Handling Rules

1. **Create templates only:** Use placeholders like `<PASSWORD_HERE>` or `YOUR_PRODUCT_KEY`
2. **Use .gitignore:** All sensitive files are already in .gitignore
3. **Document security:** Remind users to sanitize files before sharing

### Example Placeholders

```xml
<!-- autounattend.xml template -->
<Password>
  <Value><![CDATA[YOUR_PASSWORD_HERE]]></Value>
</Password>
```

See [SECURITY.md](SECURITY.md) for complete security guidelines.
