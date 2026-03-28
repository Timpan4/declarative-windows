# TODO - Declarative Windows Project

> **Goal:** Enable quick Windows reinstallation every 2 months without manual reconfiguration
>
> **Last Updated:** 2025-10-02
>
> **Note:** Research tasks have been moved to [RESEARCH.md](RESEARCH.md)

---

## Legend

- **Priority:** 🔴 High | 🟡 Medium | 🟢 Low
- **Type:** 🛠️ Implementation | ✅ Testing | 📝 Documentation
- **Status:** Use `[ ]` for incomplete, `[x]` for complete

---

# Phase 1: MVP (Minimum Viable Product)

## Component: WinGet (Application Management)

> **Research:** See [RESEARCH.md - WinGet](RESEARCH.md#component-winget-application-management) for investigation tasks

### Implementation Tasks

- [x] 🔴 🛠️ Export current apps to `apps.json` from personal machine
- [ ] 🟡 🛠️ Document manually-installed apps that need to be added to apps.json
- [x] 🟡 🛠️ Create apps.json template with common apps for friends to customize
- [ ] 🟢 🛠️ Add WinGet update logic to bootstrap script

---

## Component: Sophia Script (OS Tweaks & Registry)

> **Research:** See [RESEARCH.md - Sophia Script](RESEARCH.md#component-sophia-script-os-tweaks--registry) for investigation tasks

### Implementation Tasks

- [ ] 🔴 🛠️ Download Sophia Script and add to repository
- [x] 🔴 🛠️ Create customized `Sophia.ps1` preset file
- [x] 🟡 🛠️ Document which Sophia options are enabled/disabled
- [x] 🟡 🛠️ Analyze overlap between AutoUnattend.xml and Sophia Script
- [x] 🟡 🛠️ Resolve taskbar search conflict (changed to -SearchIcon)
- [ ] 🟡 🛠️ Create fallback registry.json for tweaks not covered by Sophia
- [x] 🟢 🛠️ Add error handling for Sophia Script execution in bootstrap

---

## Component: AutoUnattend.xml (Automated Installation)

> **Research:** See [RESEARCH.md - AutoUnattend](RESEARCH.md#component-autounattendxml-automated-installation) for investigation tasks

### Implementation Tasks

- [x] 🔴 🛠️ Create/obtain base autounattend.xml file
- [x] 🔴 🛠️ Add FirstLogonCommands to execute bootstrap.ps1
- [x] 🟡 🛠️ Configure execution policy bypass in FirstLogonCommands
- [ ] 🟡 🛠️ Add network wait logic before running bootstrap

---

## Component: Bootstrap Script (Orchestration)

### Implementation Tasks

- [x] 🔴 🛠️ Create `bootstrap.ps1` main orchestration script
- [x] 🔴 🛠️ Add administrator privilege check to bootstrap.ps1
- [x] 🔴 🛠️ Implement **idempotent** WinGet import logic (check if installed first)
- [x] 🔴 🛠️ Implement **idempotent** Sophia Script execution
- [x] 🔴 🛠️ Add desktop summary log creation (visual status with emojis)
- [x] 🔴 🛠️ Add desktop shortcut creation for manual re-runs
- [x] 🟡 🛠️ Add network connectivity check and wait loop
- [x] 🟡 🛠️ Add detailed logging to C:\Setup\install.log
- [x] 🟡 🛠️ Add progress indicators (Write-Host with colors)
- [ ] 🟡 🛠️ Add "continue where left off" logic for failed runs
- [ ] 🟢 🛠️ Add optional restart prompt at end of bootstrap
- [x] 🟢 🛠️ Add dry-run mode (preview without making changes)

### Pre-installed Windows (Local Mode)

- [ ] 🔴 🛠️ Add local mode flag (run from repo dir, not C:\Setup)
- [ ] 🔴 🛠️ Add system restore point creation before changes
- [ ] 🔴 🛠️ Add bloat removal path for existing installs (Appx + features)
- [ ] 🔴 🛠️ Auto-download Sophia Script when missing (version-pinned)
- [ ] 🟡 🛠️ Add safety prompt for destructive steps (with -Force override)
- [ ] 🟡 🛠️ Add local-mode logging path (same format as C:\Setup)
- [ ] 🟢 🛠️ Add local-mode desktop shortcut/summary (optional)

---

## Component: Driver Installation Helper

### Implementation Tasks

- [ ] 🟡 🛠️ Create `install-basic-drivers.ps1` standalone script
- [ ] 🟡 🛠️ Add CPU manufacturer detection (AMD/Intel via Get-CimInstance Win32_Processor)
- [ ] 🟡 🛠️ Add GPU manufacturer detection (NVIDIA/AMD/Intel via Get-CimInstance Win32_VideoController)
- [ ] 🟡 🛠️ Display detected hardware and recommended drivers
- [ ] 🟡 🛠️ Add user prompt: "Install drivers automatically? (Y/N)"
- [ ] 🟡 🛠️ Install drivers via Chocolatey packages (nvidia-display-driver, amd-ryzen-chipset, intel-graphics-driver)
- [ ] 🟡 🛠️ Add error handling if Chocolatey not available (with instructions to install via WinGet)
- [ ] 🟡 🛠️ If automated install fails, display manufacturer download links as fallback
- [ ] 🟡 🛠️ Copy script to C:\Setup during ISO generation
- [ ] 🟡 🛠️ Create desktop shortcut "Install Basic Drivers.lnk" pointing to script
- [ ] 🟢 🛠️ Handle edge cases (multiple GPUs, iGPU + dGPU combos)
- [ ] 🟢 🛠️ Add logging to C:\Setup\driver-install.log

---

## Component: Config Files (Optional Registry/Features)

### Implementation Tasks

- [ ] 🟡 🛠️ Create `config/registry.json` structure and schema
- [ ] 🟡 🛠️ Create `config/features.json` for Windows features toggles
- [ ] 🟡 🛠️ Create `config/settings.json` for miscellaneous OS settings
- [ ] 🟢 🛠️ Create PowerShell scripts to apply each config file type
- [ ] 🟢 🛠️ Integrate config file application into bootstrap.ps1

---

## Component: ISO Generation

> **Research:** See [RESEARCH.md - ISO Generation](RESEARCH.md#component-iso-generation) for investigation tasks

### Implementation Tasks

- [x] 🔴 🛠️ Create `build-iso.ps1` script for automated ISO generation
- [ ] 🔴 🛠️ Add oscdimg.exe downloader (from Windows ADK)
- [x] 🔴 🛠️ Implement ISO extraction logic
- [x] 🔴 🛠️ Implement $OEM$ folder structure creation
- [x] 🔴 🛠️ Implement file injection (autounattend.xml, bootstrap.ps1, apps.json, Sophia.ps1)
- [x] 🟡 🛠️ Implement ISO rebuild with oscdimg (BIOS + UEFI boot support)
- [ ] 🟡 🛠️ Add source ISO validation (checksum verification)
- [x] 🟡 🛠️ Add progress indicators for ISO creation steps
- [ ] 🟢 🛠️ Add option to customize ISO label/name
- [x] 🟢 🛠️ Add cleanup of temporary extraction folders
- [x] 🟢 🛠️ Validate boot images before ISO build
- [x] 🟢 ✅ Run Pester in GitHub Actions

### Testing Tasks

- [ ] 🔴 ✅ Test generated ISO boots in VM (UEFI mode)
- [ ] 🔴 ✅ Test generated ISO boots in VM (BIOS/Legacy mode)
- [ ] 🟡 ✅ Verify all files copied to C:\Setup during installation
- [ ] 🟡 ✅ Test ISO on real hardware
- [ ] 🟢 ✅ Validate ISO checksum consistency across builds

---

## Component: Testing

### Testing Tasks

- [ ] 🔴 ✅ Test bootstrap.ps1 **idempotency** (run multiple times safely)
- [ ] 🔴 ✅ Test bootstrap.ps1 on current system (non-destructive mode)
- [x] 🟡 ✅ Add Pester smoke tests for scripts
- [ ] 🔴 ✅ Create Windows VM for testing full fresh install workflow
- [ ] 🔴 ✅ Test automatic execution via FirstLogonCommands
- [ ] 🔴 ✅ Test manual execution via desktop shortcut
- [ ] 🔴 ✅ Test WinGet import with apps.json on fresh Windows
- [ ] 🟡 ✅ Test Sophia Script execution on fresh Windows
- [ ] 🟡 ✅ Verify desktop summary log is created correctly
- [ ] 🟡 ✅ Test "continue where left off" after simulated failure
- [ ] 🟢 ✅ Verify all scripts work with Windows 11 (24H2 or later)

---

## Component: Documentation

### Documentation Tasks

- [x] 🔴 📝 Update README.md with project overview and ISO generation workflow
- [x] 🔴 📝 Document how to export apps.json from current system
- [x] 🔴 📝 Document how to manually edit apps.json (remove unwanted apps)
- [x] 🔴 📝 Document how to test apps.json before using in automation
- [x] 🔴 📝 Document how to find package identifiers for apps.json
- [x] 🔴 📝 Create .gitignore file for sensitive data protection
- [x] 🔴 📝 Create SECURITY.md with security best practices
- [x] 🔴 📝 Create FAQ.md with frequently asked questions
- [x] 🔴 📝 Create docs/TROUBLESHOOTING.md with common issues
- [x] 🔴 📝 Add Windows 11 version support statement to README
- [x] 🔴 📝 Add Known Limitations section to README
- [x] 🔴 📝 Add Security Warning section to README
- [ ] 🔴 📝 Document how to use build-iso.ps1 (prerequisites, usage, outputs)
- [x] 🟡 📝 Document how to customize Sophia.ps1 preset
- [ ] 🟡 📝 Create docs/ISO-GENERATION.md with detailed ISO creation guide
- [ ] 🟡 📝 Document $OEM$ folder structure
- [ ] 🟡 📝 Document bootstrap.ps1 log format and location
- [ ] 🟡 📝 Document manual re-run process (desktop shortcut)
- [ ] 🟢 📝 Document how friends can fork/customize for their own setups
- [ ] 🟢 📝 Add screenshots of desktop summary log

---

# Phase 2: Enhancements

## Component: WinGet Enhancements

> **Research:** See [RESEARCH.md - WinGet Enhancements](RESEARCH.md#component-winget-enhancements) for investigation tasks

### Implementation Tasks

- [ ] 🟡 🛠️ Add WinGet source configuration (winget/msstore priorities)
- [ ] 🟡 🛠️ Create multiple apps.json profiles (minimal, full, dev-focused)
- [ ] 🟢 🛠️ Add post-install verification (check if all apps installed successfully)

---

## Component: Sophia Script Enhancements

### Implementation Tasks

- [ ] 🟡 🛠️ Create Sophia preset variations for different use cases
- [ ] 🟢 🛠️ Add interactive Sophia customization script for friends

---

## Component: Config Management

> **Research:** See [RESEARCH.md - Config Management](RESEARCH.md#component-config-management) for investigation tasks

### Implementation Tasks

- [ ] 🟡 🛠️ Expand registry.json with commonly-requested tweaks
- [ ] 🟡 🛠️ Create features.json with developer-focused features (WSL, SSH, etc.)
- [ ] 🟢 🛠️ Add validation for config files (JSON schema)

---

## Component: Git/Cloud Integration

> **Research:** See [RESEARCH.md - Git/Cloud Integration](RESEARCH.md#component-gitcloud-integration) for investigation tasks

### Implementation Tasks

- [ ] 🟡 🛠️ Add Git clone option to bootstrap.ps1 for pulling latest configs
- [ ] 🟢 🛠️ Create version tracking for config files
- [ ] 🟢 🛠️ Add rollback capability for failed installations

---

## Component: Advanced Automation

### Implementation Tasks

- [ ] 🟡 🛠️ Add dotfiles management (PowerShell profile, terminal configs)
- [ ] 🟢 🛠️ Create post-install checklist generator
- [ ] 🟢 🛠️ Add system restore point creation before applying changes

---

# Phase 3: Polish & Sharing

## Component: User Experience

### Implementation Tasks

- [ ] 🟡 🛠️ Create interactive configuration wizard for first-time users
- [ ] 🟡 🛠️ Add dry-run mode to preview changes without applying
- [ ] 🟢 🛠️ Create GUI wrapper for bootstrap script (optional)

---

## Component: Testing & Validation

### Testing Tasks

- [ ] 🟡 ✅ Test on multiple Windows 11 versions (Home, Pro, Enterprise)
- [ ] 🟡 ✅ Test with different hardware configurations
- [ ] 🟢 ✅ Create automated testing pipeline for config validation

---

## Component: Community/Sharing

### Documentation Tasks

- [ ] 🟡 📝 Create example configurations for different user types
- [ ] 🟡 📝 Create video walkthrough for friends
- [ ] 🟢 📝 Create contribution guide for adding new tweaks
- [ ] 🟢 📝 Document security best practices (what NOT to commit to Git)

---

## Component: Optimization

### Implementation Tasks

- [ ] 🟢 🛠️ Optimize bootstrap script for parallel installations
- [ ] 🟢 🛠️ Add caching for WinGet packages to reduce download time
- [ ] 🟢 🛠️ Profile script execution time and optimize bottlenecks

---

# Backlog / Future Ideas

> **Research:** See [RESEARCH.md - Backlog](RESEARCH.md#backlog--future-research) for future investigation tasks

- [ ] 🟢 🛠️ Add browser extension/bookmark export/import
- [ ] 🟢 🛠️ Create scheduled task for periodic config drift detection
- [ ] 🟢 🛠️ Add telemetry to track which configs are most popular among friends
- [ ] 🟢 📝 Create comparison doc: This project vs. Ansible/DSC/NixOS-WSL

---

## Quick Start Checklist (When MVP is Ready)

1. [ ] Export apps.json from current system
2. [ ] Customize Sophia.ps1 preset
3. [ ] Test bootstrap.ps1 locally
4. [x] Create autounattend.xml with FirstLogonCommands
5. [ ] Setup USB with $OEM$ folder structure
6. [ ] Test fresh install in VM
7. [ ] Document and share with friends

---

**Notes:**

- Prioritize Phase 1 MVP tasks to get a working prototype
- Test frequently in VM to avoid breaking personal system
- Backup current system before testing destructive changes
- Keep security in mind - never commit passwords/tokens to Git
