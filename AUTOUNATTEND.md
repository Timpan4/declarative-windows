# AutoUnattend.xml Explained

This file automates Windows 11 installation and applies tweaks during setup. It runs before you even log in for the first time.

## How It Works

The file runs in three phases during Windows installation:

### 1. windowsPE (Installation Phase)

Runs while Windows is being installed to the disk.

- Bypasses TPM/Secure Boot/RAM checks (helpful for VMs)
- Sets up disk partitions (EFI + MSR + Windows)
- Configures language/locale to en-US

### 2. specialize (Pre-OOBE Phase)

Runs after Windows is installed but before you see the setup screen.

**Bloatware Removal:**
- Bing Search
- Office Hub
- OneNote
- Skype
- Solitaire Collection
- Microsoft Teams
- Recall feature

**System Tweaks:**
- Disable Chat auto-install
- Set password to never expire
- Set PowerShell execution policy to RemoteSigned
- Empty Start menu pins
- Disable sticky keys prompt

**Default User Settings (applies to all accounts):**
- Show file extensions
- Show hidden files
- Left-align taskbar
- Disable mouse pointer precision
- Classic right-click context menu
- Search icon-only mode

### 3. oobeSystem (First Boot)

Runs when Windows boots for the first time.

- Hides EULA page
- Hides OEM registration
- Forces local account creation (no Microsoft account)
- Sets privacy to minimal data collection

**You'll still see:**
- Region/language selection
- Keyboard layout
- User account creation (you choose username/password)
- Network setup

## What Happens on First Login

1. Windows applies user-specific tweaks (classic context menu, search icon)
2. Explorer restarts to apply changes
3. **bootstrap.ps1 runs automatically** via FirstLogonCommands

The embedded tweaks handle OS-level stuff during install. Bootstrap handles app installation via WinGet and Sophia Script tweaks.

**If bootstrap fails or you want to re-run it:** Just run `C:\Setup\bootstrap.ps1` manually.

## Customization

All the tweaks are defined in the `<Extensions>` section at the bottom of the XML file. The scripts are embedded directly in the XML.

**To add a tweak:** Edit the relevant script section (Specialize.ps1, DefaultUser.ps1, or UserOnce.ps1)

**To remove a tweak:** Delete or comment out the script block

**To add/remove bloatware:** Edit the `$selectors` array in RemovePackages.ps1

## Logs

If something goes wrong, check these logs:

- `C:\Windows\Setup\Scripts\Specialize.log` - Bloatware removal and system tweaks
- `C:\Windows\Setup\Scripts\RemovePackages.log` - App removal details
- `C:\Windows\Setup\Scripts\RemoveFeatures.log` - Feature removal details
- `C:\Windows\Setup\Scripts\DefaultUser.log` - Default user registry tweaks
- `%TEMP%\UserOnce.log` - Per-user tweaks log
- `C:\Windows\Panther\setupact.log` - Windows setup log

## Security Note

Passwords and product keys are left blank. Windows will prompt you to set them during installation. Safe to commit to Git as-is.
