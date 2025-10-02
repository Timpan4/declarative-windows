# RESEARCH - Declarative Windows Project

> **Purpose:** Investigation and testing tasks to inform implementation decisions
>
> **Last Updated:** 2025-10-02

---

## Legend

- **Priority:** 🔴 High | 🟡 Medium | 🟢 Low
- **Status:** Use `[ ]` for incomplete, `[x]` for complete
- **Note:** Once research is complete, update corresponding implementation tasks in TODO.md

---

# Phase 1: MVP Research

## Component: WinGet (Application Management)

### High Priority

- [ ] 🔴 Test `winget export -o apps.json` on current system
  - **Goal:** Verify the export captures all WinGet-installed apps
  - **Commands:**
    - `winget export -o apps.json`
    - `winget export -o apps.json --source winget` (cleaner)
  - **Output:** Document any apps missing from export
  - **Next Step:** Update apps.json with missing apps or note in README

- [ ] 🔴 Verify exported apps.json captures all WinGet-installed apps
  - **Goal:** Compare `winget list` output with apps.json
  - **Commands:**
    - `winget list` (see all apps WinGet knows about)
    - Compare with apps.json package count
  - **Output:** List of any discrepancies
  - **Next Step:** Document manual installation requirements

- [ ] 🔴 Test manual JSON editing workflow
  - **Goal:** Verify removing apps from apps.json doesn't break import
  - **Process:**
    1. Export apps.json
    2. Manually remove several apps
    3. Test import with edited file
  - **Output:** Confirm editing process is user-friendly
  - **Next Step:** Update README with any gotchas

### Medium Priority

- [ ] 🟡 Test `winget import apps.json` behavior on fresh Windows install
  - **Goal:** Understand import process, timing, and error handling
  - **Environment:** Windows VM or test machine
  - **Commands:**
    - `winget import apps.json` (dry run - shows what will install)
    - `winget import apps.json --accept-package-agreements --accept-source-agreements`
  - **Output:** Document any issues, timeouts, or failures
  - **Next Step:** Add error handling to bootstrap.ps1

- [ ] 🟡 Investigate WinGet behavior with `--ignore-versions` flag
  - **Goal:** Determine if flag prevents version conflicts on import
  - **Commands:**
    - `winget import apps.json --ignore-versions`
  - **Output:** Document when to use vs. not use this flag (latest vs. specific version)
  - **Next Step:** Update bootstrap.ps1 with appropriate flags

- [ ] 🟡 Test finding package identifiers for new apps
  - **Goal:** Verify workflow for adding apps to apps.json
  - **Commands:**
    - `winget search <app-name>`
    - `winget search --id <partial-id>`
    - `winget show <package-id>` (get details)
  - **Output:** Document best practices for finding package IDs
  - **Next Step:** Add tips section to README

### Low Priority

- [ ] 🟢 Research WinGet DSC (Desired State Configuration) as alternative format
  - **Goal:** Compare YAML DSC format vs JSON for maintainability
  - **Resources:** [WinGet Configuration docs](https://learn.microsoft.com/en-us/windows/package-manager/configuration/)
  - **Output:** Recommendation: JSON vs YAML
  - **Next Step:** Decide format for Phase 2 enhancements

---

## Component: Sophia Script (OS Tweaks & Registry)

### High Priority

- [ ] 🔴 Download and review latest Sophia Script from GitHub
  - **Goal:** Understand Sophia Script structure and capabilities
  - **URL:** https://github.com/farag2/Sophia-Script-for-Windows
  - **Output:** List of available tweaks and their categories
  - **Next Step:** Map desired tweaks to Sophia options

- [ ] 🔴 Identify which Sophia Script preset file to customize (Windows 11 vs 10)
  - **Goal:** Determine correct version for target Windows
  - **Output:** Selected preset file path
  - **Next Step:** Download and add to repository

### Medium Priority

- [ ] 🟡 Test Sophia Script execution on current system (backup first!)
  - **Goal:** Verify Sophia Script works as expected
  - **Precaution:** Create system restore point before testing
  - **Output:** Document execution time, prompts, and results
  - **Next Step:** Customize preset for personal preferences

- [ ] 🟡 Document desired registry tweaks and map to Sophia Script options
  - **Goal:** Create list of all desired OS tweaks
  - **Output:** Mapping of tweaks to Sophia options or custom registry.json
  - **Next Step:** Enable corresponding Sophia options

### Low Priority

- [ ] 🟢 Research Sophia Script's compatibility with AutoUnattend.xml
  - **Goal:** Identify any conflicts between the two tools
  - **Output:** List of potential issues or order dependencies
  - **Next Step:** Document execution order in bootstrap.ps1

---

## Component: AutoUnattend.xml (Automated Installation)

### High Priority

- [ ] 🔴 Check if existing autounattend.xml exists in `C:\Windows\Panther\`
  - **Goal:** Extract current autounattend.xml if available
  - **Locations to check:**
    - `C:\Windows\Panther\unattend.xml`
    - `C:\Windows\Panther\Unattend\unattend.xml`
    - `C:\Windows\System32\Sysprep\unattend.xml`
  - **Output:** Copy of existing autounattend.xml or note if missing
  - **Next Step:** Use as base template or create new one

### Medium Priority

- [ ] 🟡 Research Schneegans Unattend Generator for creating base template
  - **Goal:** Understand web-based autounattend.xml generation
  - **URL:** https://schneegans.de/windows/unattend-generator/
  - **Output:** Generated autounattend.xml template
  - **Next Step:** Customize for project needs

- [ ] 🟡 Test FirstLogonCommands execution timing and permissions
  - **Goal:** Verify when FirstLogonCommands run and with what privileges
  - **Environment:** Test VM with autounattend.xml
  - **Output:** Document execution context and timing
  - **Next Step:** Add appropriate privilege escalation to bootstrap.ps1

- [ ] 🟡 Verify $OEM$ folder structure copies files correctly to C:\Setup
  - **Goal:** Confirm files are copied during Windows installation
  - **Environment:** Test VM with USB containing $OEM$ folder
  - **Output:** Screenshot/verification of files in C:\Setup
  - **Next Step:** Document folder structure in README.md

### Low Priority

- [ ] 🟢 Research autounattend.xml partitioning and user account automation
  - **Goal:** Automate disk partitioning and user creation
  - **Output:** Additional autounattend.xml configurations
  - **Next Step:** Add to autounattend.xml template

---

## Component: ISO Generation

### High Priority

- [ ] 🔴 Research oscdimg.exe boot parameters for BIOS + UEFI support
  - **Goal:** Understand correct oscdimg command-line flags for dual-boot ISO
  - **Resources:** Windows ADK documentation, oscdimg /?
  - **Output:** Correct oscdimg command template
  - **Next Step:** Implement in build-iso.ps1

- [ ] 🔴 Test ISO extraction and rebuild process
  - **Goal:** Verify we can extract and rebuild an ISO without corruption
  - **Environment:** Windows with 7-Zip or built-in tools
  - **Output:** Document extraction method and rebuild verification
  - **Next Step:** Add to build-iso.ps1

- [ ] 🔴 Research Windows ADK oscdimg.exe download/install automation
  - **Goal:** Enable automatic download of oscdimg.exe without full ADK install
  - **Output:** Direct download link or minimal install method
  - **Next Step:** Add downloader to build-iso.ps1

### Medium Priority

- [ ] 🟡 Research $OEM$ folder structure requirements
  - **Goal:** Confirm exact folder structure for auto-copying files
  - **Structure to verify:** `$OEM$\$$\Setup\` → `C:\Setup\`
  - **Output:** Documented folder structure with examples
  - **Next Step:** Implement in build-iso.ps1

- [ ] 🟡 Test FirstLogonCommands execution with network-dependent scripts
  - **Goal:** Verify bootstrap.ps1 runs before/after network is available
  - **Environment:** Fresh Windows install in VM
  - **Output:** Document timing and network availability
  - **Next Step:** Add network wait logic to bootstrap.ps1

- [ ] 🟡 Research ISO checksum/hash validation methods
  - **Goal:** Ensure generated ISOs are valid and not corrupted
  - **Output:** SHA256 hash validation process
  - **Next Step:** Add validation to build-iso.ps1

### Low Priority

- [ ] 🟢 Research WIM/ESD image modification with DISM
  - **Goal:** Understand how to pre-install apps or remove bloatware from image
  - **Resources:** DISM documentation, Windows image servicing
  - **Output:** Decision: Keep simple file injection vs. modify WIM
  - **Next Step:** Potentially add to Phase 2 enhancements

- [ ] 🟢 Investigate ISO size optimization techniques
  - **Goal:** Reduce ISO size if possible
  - **Output:** List of optimization opportunities
  - **Next Step:** Add to Phase 3 if needed

---

## Component: Idempotency & Logging

### High Priority

- [ ] 🔴 Research WinGet methods to check if package is installed
  - **Goal:** Find reliable way to detect installed apps before installing
  - **Commands to test:** `winget list --id <package-id>`, exit codes
  - **Output:** Recommended detection method
  - **Next Step:** Implement in bootstrap.ps1

- [ ] 🔴 Design desktop summary log format
  - **Goal:** Create user-friendly log format with status indicators
  - **Output:** Template with emojis/symbols for success/failure/skip
  - **Next Step:** Implement in bootstrap.ps1

### Medium Priority

- [ ] 🟡 Research PowerShell desktop shortcut creation methods
  - **Goal:** Create .lnk file programmatically on user desktop
  - **Output:** PowerShell code snippet for shortcut creation
  - **Next Step:** Add to bootstrap.ps1

- [ ] 🟡 Research registry key detection methods (for idempotency)
  - **Goal:** Check if registry tweaks already applied
  - **Output:** PowerShell methods to read registry values
  - **Next Step:** Implement in Sophia Script wrapper

### Low Priority

- [ ] 🟢 Research state file formats for tracking completed steps
  - **Goal:** Enable "continue where left off" functionality
  - **Options:** JSON state file, registry keys, simple text file
  - **Output:** Recommended approach
  - **Next Step:** Implement in bootstrap.ps1

---

# Phase 2: Enhancement Research

## Component: WinGet Enhancements

### Medium Priority

- [ ] 🟡 Research WinGet DSC YAML format vs JSON
  - **Goal:** Compare formats for readability and tooling support
  - **Output:** Recommendation with pros/cons
  - **Next Step:** Decide on Phase 2 format

### Low Priority

- [ ] 🟢 Investigate WinGet package pinning to prevent unwanted updates
  - **Goal:** Understand how to lock specific package versions
  - **Output:** Documentation on package pinning
  - **Next Step:** Add pinning config to apps.json

---

## Component: Config Management

### Medium Priority

- [ ] 🟡 Research Windows feature dependencies (WSL, Hyper-V, etc.)
  - **Goal:** Map feature dependencies for proper enable order
  - **Output:** Dependency graph or ordered list
  - **Next Step:** Update features.json with dependency metadata

### Low Priority

- [ ] 🟢 Investigate PowerShell DSC for declarative config management
  - **Goal:** Evaluate DSC as alternative to custom scripts
  - **Resources:** [PowerShell DSC docs](https://learn.microsoft.com/en-us/powershell/dsc/)
  - **Output:** Comparison: Custom scripts vs DSC
  - **Next Step:** Decide whether to adopt DSC

---

## Component: Git/Cloud Integration

### Medium Priority

- [ ] 🟡 Research downloading config from private GitHub repo during install
  - **Goal:** Enable pulling latest configs from Git during setup
  - **Challenges:** Authentication without credentials on fresh install
  - **Output:** Authentication strategy (tokens, SSH keys, etc.)
  - **Next Step:** Implement Git clone in bootstrap.ps1

### Low Priority

- [ ] 🟢 Investigate cloud storage alternatives (OneDrive, Dropbox) for configs
  - **Goal:** Compare cloud storage vs Git for config distribution
  - **Output:** Pros/cons of each approach
  - **Next Step:** Choose storage strategy for sharing with friends

---

# Backlog / Future Research

- [ ] 🟢 Research Chocolatey as fallback for apps not in WinGet
  - **Goal:** Understand Chocolatey integration for missing packages
  - **Output:** List of apps only available via Chocolatey
  - **Next Step:** Add Chocolatey support to bootstrap.ps1

- [ ] 🟢 Investigate Chris Titus Tech WinUtil integration
  - **Goal:** Evaluate WinUtil as alternative to Sophia Script
  - **URL:** https://github.com/ChrisTitusTech/winutil
  - **Output:** Comparison: Sophia Script vs WinUtil
  - **Next Step:** Decide whether to integrate or replace

---

## Research Outcomes Template

When completing research tasks, document findings using this format:

```markdown
## [Research Task Name]

**Date Completed:** YYYY-MM-DD
**Researcher:** [Your Name]

### Summary

[1-2 sentence summary of findings]

### Key Findings

- Finding 1
- Finding 2
- Finding 3

### Recommendations

- Recommendation 1
- Recommendation 2

### Resources

- [Link 1](url)
- [Link 2](url)

### Next Actions

- [ ] Update TODO.md task XYZ
- [ ] Create config file ABC
- [ ] Document in README.md
```

---

## Notes

- **Testing Environment:** Use VMs for destructive testing (Hyper-V, VMware, VirtualBox)
- **Backup First:** Always create system restore points before testing on personal machine
- **Document Everything:** Take screenshots, save command outputs, note error messages
- **Version Awareness:** Note which Windows version (11 vs 10) research applies to
