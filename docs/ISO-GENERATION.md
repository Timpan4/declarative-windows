# ISO Generation

This guide explains how to build a custom Windows 11 ISO with declarative-windows baked in.

## Prerequisites

- Windows 11 24H2 or later amd64 ISO. Every selectable edition must be a client image with version 10.0, build 26100 or later, and DISM architecture 9. Server, ARM64, older releases, and missing or invalid metadata are rejected before staging.
- [Windows ADK Deployment Tools](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install), including Windows System Image Manager and `oscdimg.exe`. Use the current compatible ADK and servicing patch listed by Microsoft for your host and target Windows release.
- Administrator privileges
- Free space for the expanded source files plus selected payload in both TEMP and the output location. The builder measures inputs before staging and combines the estimates when both locations share a volume. Filesystem and ISO metadata overhead and concurrent disk use can still exhaust space during a build.

The builder requires the Windows SIM schema DLL to validate `autounattend.xml` before staging. A standalone `oscdimg.exe` download cannot replace this prerequisite. The validator reports a missing schema before mounting the ISO; after schema and policy checks, it reads each image's detailed metadata. Disk and partition selection remain manual.

From an elevated PowerShell session, check the installed prerequisites and source image before building:

```powershell
.\validate-unattend.ps1 -UnattendPath .\autounattend.xml -SourceISO "Win11_English_x64.iso"
```

This must complete successfully. The validator's `-SchemaDllPath` option supports a schema DLL at a nonstandard location for standalone validation; `build-iso.ps1` uses the standard ADK locations. Install Deployment Tools in the standard location for the build command below. The release boundary follows [Microsoft's Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information).

## Basic Usage

```powershell
# Build a custom ISO
.\build-iso.ps1 -SourceISO "Win11_English_x64.iso" -OutputISO "Win11_Custom.iso"
```

## Recommended Usage (Checksum + Label)

```powershell
.\build-iso.ps1 \
  -SourceISO "Win11_English_x64.iso" \
  -OutputISO "Win11_Custom.iso" \
  -SourceIsoHash "YOUR_ISO_SHA256_HASH" \
  -IsoLabel "DECLARATIVE_WIN11"
```

## Parameters

- `-SourceISO` (required): Path to the source Windows 11 ISO.
- `-OutputISO` (required): New path for the generated ISO. Existing files and directories are rejected before staging. The output is published only after oscdimg succeeds, without replacing files created by another process.
- `-SourceIsoHash` (optional): Expected SHA256 hash for the source ISO.
- `-IsoLabel` (optional): ISO label passed to `oscdimg`.
- `-OscdimgDownloadUrl` (optional): Direct URL to `oscdimg.exe` or a ZIP containing it, used only if an installed copy is not found. It does not supply Windows SIM or bypass schema validation; ADK Deployment Tools remain required.
- `-OscdimgSha256` (required when downloading oscdimg): Expected SHA-256 of the downloaded EXE or ZIP, obtained from a trusted source independently of the download. The builder rejects a mismatch before extraction or execution and logs the verified digest. ZIP downloads must contain exactly one `oscdimg.exe`.
- `-KeepTemp` (optional): Retain temporary extraction files for debugging.

## ISO Contents

Before staging, the builder prints the selected source and destination paths without reading configuration contents to the console. Only the declared setup scripts, runtime modules, apps.json, optional-apps.json when present, Sophia-Preset.ps1, config/registry.json and config/backup.template.json are selected. Other files in config, including ignored backup.json, restore.json and personal files, are excluded.

The ISO generator injects files into the root and `sources\$OEM$` structure:

```
Custom-ISO:\
├── autounattend.xml
└── sources\
    └── $OEM$\
        └── $1\
            └── Setup\
                ├── bootstrap.ps1
                ├── apps.json
                ├── optional-apps.json (optional)
                ├── Sophia-Preset.ps1
                ├── restore-backup.ps1
                ├── apply-registry.ps1
                └── config\
                    ├── backup.template.json
                    └── registry.json
```

## On the Installed System

During installation, you still choose the target disk and partition in Windows Setup. After Windows copies the `sources\$OEM$` payload, the setup files land in `C:\Setup`.

```
C:\Setup\
├── bootstrap.ps1
├── apps.json
├── optional-apps.json (optional)
├── Sophia-Preset.ps1
├── apply-registry.ps1
├── state.json
├── install.log
└── config\
    └── registry.json
```

A desktop shortcut is created for manual re-runs:

- `Run Windows Setup.lnk`
- `Restore My Files.lnk`
- `Install Optional Apps.lnk` (only when `optional-apps.json` exists)

After first login, bootstrap attempts to clone the original repo remote into `%USERPROFILE%\Documents\declarative-windows`. `C:\Setup` remains the staging area and fallback location if cloning fails.

## Install Flow

1. Boot from the custom ISO.
2. Choose the destination disk and partition layout manually in Windows Setup.
3. Complete the normal Windows account setup flow.
4. Let `bootstrap.ps1` continue the core app install and post-install configuration automatically after first login.
5. If `optional-apps.json` exists, answer the yes/no prompt to install optional apps now or use the desktop shortcut later.

## Logs and Resume State

- `C:\Setup\install.log`: full execution log
- `C:\Setup\state.json`: step resume state
- `C:\Users\<User>\Desktop\Setup Summary.txt`: summary report

Only one bootstrap run may own `C:\Setup\state.json` at a time. A competing launch exits without rewriting the owner's reports. State publication is atomic and retains the previous committed file as `state.json.previous`. Corrupt state stops setup and remains untouched. Review the saved state and its previous copy before recovering it; deleting state can repeat completed actions.

User-scope retries publish a complete JSON result before the parent reads it. On timeout or cancellation, bootstrap stops the scheduled task and checks its state before deleting runner files. If termination cannot be confirmed, it retains the task and files and reports their identity in `install.log`; settle that task before retrying setup.

## Manual Re-run

Use the desktop shortcut or run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\Setup\bootstrap.ps1
```

To install optional apps later without rerunning the whole flow:

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\Setup\bootstrap.ps1 -OptionalAppsOnly
```

## Backup And Restore Flow

Before reinstall, run:

```powershell
.\preflight-backup.ps1 -DestinationRoot "E:\"
```

This writes a backup manifest under `declarative-windows-backup\<timestamp>\backup-manifest.json` on the destination root. After reinstall, use `Restore My Files.lnk` from the desktop to merge files back in.
