# AutoUnattend.xml Explained

This file automates only the minimal parts of Windows 11 setup needed for this repo. It intentionally avoids aggressive install-time customization so Windows Setup stays as reliable as possible.

## How It Works

The file runs in three phases during Windows installation:

### 1. windowsPE (Installation Phase)

Runs while Windows is being installed to the disk.

- Bypasses TPM/Secure Boot/RAM checks (helpful for VMs)
- Leaves disk and partition selection to the user in Windows Setup
- Configures language/locale to en-US

### 2. oobeSystem (First Boot)

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

1. Windows completes the normal account setup flow
2. The system waits for network connectivity
3. **bootstrap.ps1 runs automatically** via FirstLogonCommands

Install-time tweaking is intentionally minimal. Bootstrap handles app installation via WinGet and system customization via Sophia Script after first login.

**If bootstrap fails or you want to re-run it:** Just run `C:\Setup\bootstrap.ps1` manually.

## Customization

This file is intentionally minimal. If you add more install-time customization later, keep it small and retest Setup carefully.

## Logs

If something goes wrong, check these logs:

- `C:\Windows\Panther\setupact.log` - Windows setup log

## Security Note

Passwords and product keys are left blank. Windows will prompt you to set them during installation. Safe to commit to Git as-is.
