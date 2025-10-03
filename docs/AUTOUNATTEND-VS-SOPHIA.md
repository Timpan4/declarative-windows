# AutoUnattend.xml vs Sophia Script

**AutoUnattend.xml**: Installation-time tasks + per-user defaults
**Sophia Script**: Post-installation UI tweaks and OS customizations

---

## AutoUnattend.xml

**Handles:**
- Disk partitioning and formatting
- Hardware bypasses (TPM, SecureBoot, RAM)
- Pre-installed bloatware removal (Teams, Bing, Office, Solitaire, Recall)
- PowerShell execution policy
- OOBE skip (EULA, online account screens)
- Default user settings (file extensions, hidden files, taskbar alignment, mouse acceleration, sticky keys)
- Per-user settings (classic context menu, search box mode)
- Launch bootstrap.ps1 on first login

**Does NOT handle:**
- Privacy settings (telemetry, Bing, tips, suggestions)
- Performance settings (hibernation, power plan, storage sense)
- Windows features (WSL, .NET)
- Security settings (Defender, DNS, network protection)

---

## Sophia Script

**Handles:**
- Privacy & telemetry (tracking, feedback, advertising ID)
- UI & personalization (dark mode, file extensions, hidden files, taskbar)
- System config (Storage Sense, hibernation, power plan, WSL, .NET)
- Start menu (app suggestions, pins)
- Gaming (Xbox features)
- Security (Defender, SmartScreen)
- Performance (visual effects, mouse acceleration, Sticky Keys)

**Does NOT handle:**
- Disk partitioning
- Hardware bypasses
- Windows installation
- Application installation (use WinGet)

---

## Installation Timeline

```
1. windowsPE Pass           → AutoUnattend.xml (disk setup, hardware bypasses)
2. specialize Pass          → AutoUnattend.xml (remove bloatware, set policies)
3. oobeSystem Pass          → AutoUnattend.xml (skip OOBE, launch bootstrap)
4. Post-Installation        → bootstrap.ps1 → WinGet (apps) + Sophia (tweaks)
```

---

## Quick Reference

| Task | Tool |
|------|------|
| Disk partitioning | AutoUnattend.xml |
| Remove pre-installed bloat | AutoUnattend.xml |
| Hardware bypasses (TPM, SecureBoot) | AutoUnattend.xml |
| Classic context menu | AutoUnattend.xml |
| Mouse acceleration disable | AutoUnattend.xml |
| Default user settings (file ext, hidden files) | AutoUnattend.xml |
| Disable telemetry | Sophia Script |
| Dark mode | Sophia Script |
| Taskbar customization | Sophia Script |
| Privacy settings | Sophia Script |
| Install applications | WinGet (apps.json) |

## Making Changes

- **Installation behavior**: Edit `AutoUnattend.xml`
- **UI/OS tweaks**: Edit `Sophia-Preset.ps1`
- **Applications**: Edit `apps.json`
