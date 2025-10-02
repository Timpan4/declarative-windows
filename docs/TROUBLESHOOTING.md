# Troubleshooting Guide

Common issues and their solutions for the declarative-windows project.

---

## WinGet Issues

### WinGet Command Not Found

**Symptoms:**

```
'winget' is not recognized as an internal or external command
```

**Solutions:**

1. **Update WinGet (App Installer):**
   - Open Microsoft Store
   - Search for "App Installer"
   - Click "Update"

2. **Or install from PowerShell:**

   ```powershell
   Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
   ```

3. **Restart PowerShell** after updating

---

### WinGet Import Fails with "No package found"

**Symptoms:**

```
No package found matching input criteria
```

**Causes:**

- Package ID is incorrect
- Package not available in WinGet
- Typo in apps.json

**Solutions:**

1. **Verify package ID:**

   ```powershell
   winget search <app-name>
   winget show <package-id>
   ```

2. **Check apps.json syntax:**
   - Ensure proper JSON format
   - Check for typos in PackageIdentifier
   - Validate with: https://jsonlint.com/

3. **Test individual package:**
   ```powershell
   winget install --id <package-id>
   ```

---

### WinGet Fails with Network Errors

**Symptoms:**

```
An unexpected error occurred while executing the command
Failed to download package
```

**Solutions:**

1. **Check internet connection:**

   ```powershell
   Test-Connection -ComputerName 8.8.8.8 -Count 4
   ```

2. **Disable VPN temporarily** (if using one)

3. **Check proxy settings:**

   ```powershell
   netsh winhttp show proxy
   ```

4. **Reset WinGet sources:**
   ```powershell
   winget source reset --force
   ```

---

### WinGet Hangs During Installation

**Symptoms:**

- Installation stuck at "Downloading..."
- No progress for 10+ minutes

**Solutions:**

1. **Cancel and retry:**
   - Press `Ctrl+C` to cancel
   - Re-run `bootstrap.ps1` (it's idempotent)

2. **Check disk space:**

   ```powershell
   Get-PSDrive C | Select-Object Used,Free
   ```

3. **Clear WinGet cache:**
   ```powershell
   Remove-Item "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalCache\*" -Recurse -Force
   ```

---

## Sophia Script Issues

### Sophia Script Not Found

**Symptoms:**

```
.\Sophia.ps1 : The term '.\Sophia.ps1' is not recognized
```

**Solutions:**

1. **Download Sophia Script:**
   - Go to https://github.com/farag2/Sophia-Script-for-Windows
   - Download the latest Windows 11 version
   - Extract to your project folder

2. **Check file path in bootstrap.ps1:**
   ```powershell
   # Ensure this path is correct
   .\Sophia.ps1
   # Or use full path:
   C:\Setup\Sophia.ps1
   ```

---

### Sophia Script Execution Policy Error

**Symptoms:**

```
cannot be loaded because running scripts is disabled on this system
```

**Solutions:**

1. **Run PowerShell as Administrator:**

   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```

2. **Or run with bypass flag:**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\bootstrap.ps1
   ```

---

### Sophia Script Made Unwanted Changes

**Symptoms:**

- Something broke after running Sophia Script
- Setting you wanted is now disabled

**Solutions:**

1. **Use System Restore:**
   - Open "Create a restore point" in Windows search
   - Click "System Restore"
   - Choose restore point before running Sophia

2. **Manually revert changes:**
   - Check `Sophia.ps1` to see what it changed
   - Use Windows Settings or Registry Editor to revert

3. **Customize Sophia.ps1:**
   - Open Sophia.ps1 in a text editor
   - Comment out (add `#`) tweaks you don't want
   - Re-run the script

---

## AutoUnattend.xml Issues

### AutoUnattend.xml Didn't Run

**Symptoms:**

- Windows installed normally
- No automatic configuration happened
- bootstrap.ps1 didn't run

**Solutions:**

1. **Check file location:**
   - autounattend.xml must be in the **root** of the ISO/USB
   - Not in a subfolder

2. **Verify $OEM$ folder structure:**

   ```
   USB:\
   ├── autounattend.xml          ← Root!
   └── $OEM$\$$\Setup\
       ├── bootstrap.ps1
       ├── apps.json
       └── Sophia.ps1
   ```

3. **Check autounattend.xml syntax:**
   - Use an XML validator
   - Ensure `FirstLogonCommands` are present

4. **Check setup logs:**
   ```powershell
   Get-Content C:\Windows\Panther\setupact.log | Select-String "unattend"
   ```

---

### FirstLogonCommands Didn't Execute bootstrap.ps1

**Symptoms:**

- autounattend.xml ran
- bootstrap.ps1 didn't execute

**Solutions:**

1. **Check files were copied:**

   ```powershell
   Get-ChildItem C:\Setup\
   ```

2. **Manually run bootstrap.ps1:**

   ```powershell
   cd C:\Setup
   powershell.exe -ExecutionPolicy Bypass -File .\bootstrap.ps1
   ```

3. **Check FirstLogonCommands in autounattend.xml:**
   ```xml
   <CommandLine>powershell -ExecutionPolicy Bypass -File C:\Setup\bootstrap.ps1</CommandLine>
   ```

---

## ISO Generation Issues

### oscdimg.exe Not Found

**Symptoms:**

```
oscdimg.exe is not recognized
```

**Solutions:**

1. **Download Windows ADK:**
   - https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
   - Install only "Deployment Tools" component

2. **Add oscdimg.exe to PATH:**

   ```powershell
   $env:PATH += ";C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg"
   ```

3. **Or use full path in build-iso.ps1**

---

### ISO Won't Boot in VM

**Symptoms:**

- ISO created successfully
- VM won't boot from ISO
- "No bootable device" error

**Solutions:**

1. **Check boot mode:**
   - VM must be set to **UEFI** (not BIOS/Legacy)
   - Or regenerate ISO with BIOS boot support

2. **Verify ISO integrity:**

   ```powershell
   Get-FileHash -Path Win11_Custom.iso -Algorithm SHA256
   ```

3. **Try different VM software:**
   - Hyper-V Quick Create
   - VMware Workstation
   - VirtualBox

4. **Recreate ISO:**
   - Delete and regenerate the ISO
   - Verify source ISO is good

---

### ISO Creation Fails with "Access Denied"

**Symptoms:**

```
Access to the path is denied
```

**Solutions:**

1. **Run PowerShell as Administrator**

2. **Check file permissions:**
   - Ensure you have write access to output directory

3. **Close any programs using the ISO:**
   - Close File Explorer windows
   - Unmount any mounted ISOs

---

## Bootstrap Script Issues

### Script Won't Run - Execution Policy

**Symptoms:**

```
cannot be loaded because running scripts is disabled
```

**Solutions:**

1. **Run as Administrator with bypass:**

   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\bootstrap.ps1
   ```

2. **Or set policy for current session:**
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\bootstrap.ps1
   ```

---

### No Desktop Shortcut Created

**Symptoms:**

- Script ran successfully
- No "Run Windows Setup" shortcut on desktop

**Solutions:**

1. **Check if shortcut creation is implemented:**
   - Look for shortcut creation code in bootstrap.ps1
   - Might not be implemented yet (check TODO.md)

2. **Manually create shortcut:**
   - Right-click Desktop → New → Shortcut
   - Target: `powershell.exe -ExecutionPolicy Bypass -File C:\Setup\bootstrap.ps1`
   - Name: "Run Windows Setup"

---

### Desktop Summary Log Not Created

**Symptoms:**

- Script ran
- No `Setup Summary.txt` on desktop

**Solutions:**

1. **Check logs in C:\Setup:**

   ```powershell
   Get-Content C:\Setup\install.log
   ```

2. **Verify logging is implemented:**
   - Check bootstrap.ps1 for logging code
   - Might be planned but not implemented yet

3. **Check user desktop path:**
   ```powershell
   $desktopPath = [Environment]::GetFolderPath("Desktop")
   Write-Host $desktopPath
   ```

---

## Network & Connectivity

### No Network During FirstLogonCommands

**Symptoms:**

- WinGet fails immediately
- "No internet connection" errors
- bootstrap.ps1 can't download anything

**Solutions:**

1. **Add network wait to bootstrap.ps1:**

   ```powershell
   Write-Host "Waiting for network..."
   while (!(Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet)) {
       Start-Sleep 2
   }
   ```

2. **Check Windows network drivers:**
   - Ensure network drivers are included in Windows install
   - Or add drivers to autounattend.xml

3. **Manual network configuration:**
   - Configure network manually after Windows install
   - Then run bootstrap.ps1

---

## File & Permission Issues

### Files Missing from C:\Setup

**Symptoms:**

- Checked C:\Setup after install
- bootstrap.ps1 or other files missing

**Solutions:**

1. **Verify $OEM$ folder structure on USB/ISO:**

   ```
   $OEM$\$$\Setup\
   ```

   - Must use exact folder names (case-sensitive on some systems)

2. **Check source files:**
   - Ensure all files are in the right place before creating ISO

3. **Recreate ISO/USB:**
   - Delete and recreate with correct structure

---

### Cannot Modify Registry - Access Denied

**Symptoms:**

```
Set-ItemProperty : Requested registry access is not allowed
```

**Solutions:**

1. **Run PowerShell as Administrator:**
   - Right-click PowerShell → "Run as administrator"

2. **Check registry permissions:**
   - Some keys require TrustedInstaller ownership
   - May need to take ownership first

3. **Use Sophia Script instead:**
   - Sophia handles permissions correctly
   - Safer than manual registry edits

---

## General Troubleshooting Steps

### When Something Goes Wrong

1. **Check the logs:**
   - `C:\Setup\install.log` (detailed log)
   - `C:\Windows\Panther\setupact.log` (Windows setup log)

2. **Re-run bootstrap.ps1:**
   - It's idempotent - safe to run multiple times
   - Will skip completed steps

3. **Test in a VM first:**
   - Never test destructive changes on your main machine
   - Use Hyper-V Quick Create for fast testing

4. **Create a System Restore Point:**
   - Before running any tweaks
   - Easy rollback if something breaks

5. **Review changes before applying:**
   - Read through Sophia.ps1
   - Understand what each step does
   - Comment out anything uncertain

---

## Getting More Help

If you're still stuck:

1. **Check FAQ.md** for common questions
2. **Review SECURITY.md** if it's a permissions/access issue
3. **Check GitHub Issues** for Sophia Script or WinGet
4. **Test individual components:**
   - Test WinGet separately
   - Test Sophia Script separately
   - Test autounattend.xml separately

---

## Debugging Tips

### Enable Verbose Logging

Add to top of bootstrap.ps1:

```powershell
$VerbosePreference = "Continue"
$DebugPreference = "Continue"
```

### Check PowerShell Version

```powershell
$PSVersionTable
```

Requires PowerShell 5.1 or later.

### Verify JSON Syntax

```powershell
Get-Content apps.json | ConvertFrom-Json
# If no errors, JSON is valid
```

### Test Network Connectivity

```powershell
Test-Connection -ComputerName 8.8.8.8 -Count 4
Test-Connection -ComputerName winget.azureedge.net -Count 4
```

---

**Remember:** Most issues can be resolved by re-running the script. It's designed to be idempotent and resilient to failures.
