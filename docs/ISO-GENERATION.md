# ISO Generation

This guide explains how to build a custom Windows 11 ISO with declarative-windows baked in.

## Prerequisites

- Windows 11 (22H2 or later) ISO
- Windows ADK **or** a direct `oscdimg.exe` download URL
- Administrator privileges
- At least 10GB of free disk space

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
- `-OutputISO` (required): Path for the generated ISO.
- `-SourceIsoHash` (optional): Expected SHA256 hash for the source ISO.
- `-IsoLabel` (optional): ISO label passed to `oscdimg`.
- `-OscdimgDownloadUrl` (optional): Direct URL to `oscdimg.exe` or a ZIP containing it.
- `-KeepTemp` (optional): Retain temporary extraction files for debugging.

## ISO Contents

The ISO generator injects files into the root and `$OEM$` structure:

```
Custom-ISO:\
├── autounattend.xml
└── $OEM$\
    └── $1\
        └── Setup\
            ├── bootstrap.ps1
            ├── apps.json
            ├── Sophia-Preset.ps1
            ├── restore-backup.ps1
            ├── apply-registry.ps1
            └── config\
                ├── backup.template.json
                └── registry.json
```

## On the Installed System

During installation, you still choose the target disk and partition in Windows Setup. After Windows copies the `$OEM$` payload, the setup files land in `C:\Setup`.

```
C:\Setup\
├── bootstrap.ps1
├── apps.json
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

After first login, bootstrap attempts to clone the original repo remote into `%USERPROFILE%\Documents\declarative-windows`. `C:\Setup` remains the staging area and fallback location if cloning fails.

## Install Flow

1. Boot from the custom ISO.
2. Choose the destination disk and partition layout manually in Windows Setup.
3. Complete the normal Windows account setup flow.
4. Let `bootstrap.ps1` continue the app install and post-install configuration automatically after first login.

## Logs and Resume State

- `C:\Setup\install.log`: full execution log
- `C:\Setup\state.json`: step resume state
- `C:\Users\<User>\Desktop\Setup Summary.txt`: summary report

## Manual Re-run

Use the desktop shortcut or run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\Setup\bootstrap.ps1
```

## Backup And Restore Flow

Before reinstall, run:

```powershell
.\preflight-backup.ps1 -DestinationRoot "E:\"
```

This writes a backup manifest under `declarative-windows-backup\<timestamp>\backup-manifest.json` on the destination root. After reinstall, use `Restore My Files.lnk` from the desktop to merge files back in.
