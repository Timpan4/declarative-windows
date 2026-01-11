#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Builds a custom Windows 11 ISO with declarative-windows configuration baked in.

.DESCRIPTION
    This script takes a source Windows 11 ISO and creates a customized version with:
    - autounattend.xml for unattended installation
    - bootstrap.ps1, apps.json, and Sophia-Preset.ps1 copied via $OEM$ structure
    - Fully automated setup that runs on first login

.PARAMETER SourceISO
    Path to the source Windows 11 ISO file.

.PARAMETER OutputISO
    Path where the customized ISO will be saved.

.PARAMETER KeepTemp
    If specified, keeps the temporary working directory for debugging.

.EXAMPLE
    .\build-iso.ps1 -SourceISO "Win11_English_x64.iso" -OutputISO "Win11_Custom.iso"

.NOTES
    Requirements:
    - Windows ADK (for oscdimg.exe) - https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
    - Administrator privileges
    - At least 10GB free disk space
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$SourceISO,

    [Parameter(Mandatory = $true)]
    [string]$OutputISO,

    [Parameter(Mandatory = $false)]
    [switch]$KeepTemp
)

# Script configuration
$ErrorActionPreference = "Stop"
$ScriptRoot = $PSScriptRoot
$TempDir = Join-Path $env:TEMP "declarative-windows-iso-$(Get-Random)"
$MountDir = Join-Path $TempDir "mount"
$WorkDir = Join-Path $TempDir "work"

# Color output functions
function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Gray
}

# Function to find oscdimg.exe from Windows ADK
function Find-OscdImg {
    Write-Step "Locating oscdimg.exe from Windows ADK"

    $possiblePaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            Write-Success "Found oscdimg.exe at: $path"
            return $path
        }
    }

    # Try searching the registry for ADK installation path
    try {
        $adkPath = (Get-ItemProperty "HKLM:\Software\WOW6432Node\Microsoft\Windows Kits\Installed Roots" -ErrorAction SilentlyContinue).KitsRoot10
        if ($adkPath) {
            $oscdimgPath = Join-Path $adkPath "Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
            if (Test-Path $oscdimgPath) {
                Write-Success "Found oscdimg.exe at: $oscdimgPath"
                return $oscdimgPath
            }
        }
    }
    catch {
        # Continue to error below
    }

    Write-ErrorMessage "oscdimg.exe not found!"
    Write-Host "`nPlease install Windows ADK from:" -ForegroundColor Yellow
    Write-Host "https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install" -ForegroundColor Yellow
    throw "Windows ADK is required to build ISO files."
}


# Main execution
try {
    Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║      Declarative Windows - Custom ISO Builder               ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

    # Validate required files exist
    Write-Step "Validating project files"

    $requiredFiles = @{
        "autounattend.xml" = Join-Path $ScriptRoot "autounattend.xml"
        "bootstrap.ps1" = Join-Path $ScriptRoot "bootstrap.ps1"
        "apps.json" = Join-Path $ScriptRoot "apps.json"
        "Sophia-Preset.ps1" = Join-Path $ScriptRoot "Sophia-Preset.ps1"
    }

    foreach ($file in $requiredFiles.GetEnumerator()) {
        if (Test-Path $file.Value) {
            Write-Success "$($file.Key) found"
        }
        else {
            Write-ErrorMessage "$($file.Key) not found at: $($file.Value)"
            throw "Missing required file: $($file.Key)"
        }
    }

    # Find oscdimg.exe
    $oscdimgPath = Find-OscdImg

    # Create temporary directories
    Write-Step "Creating temporary directories"
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
    New-Item -Path $MountDir -ItemType Directory -Force | Out-Null
    New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
    Write-Success "Temporary directories created at: $TempDir"

    # Mount source ISO
    Write-Step "Mounting source ISO"
    Write-Info "Source: $SourceISO"

    $mount = Mount-DiskImage -ImagePath (Resolve-Path $SourceISO).Path -PassThru
    $driveLetter = ($mount | Get-Volume).DriveLetter
    $sourceRoot = "${driveLetter}:\"

    Write-Success "ISO mounted at: $sourceRoot"

    # Copy ISO contents to working directory
    Write-Step "Copying ISO contents (this may take a few minutes)"
    Write-Info "Destination: $WorkDir"

    Copy-Item -Path "$sourceRoot*" -Destination $WorkDir -Recurse -Force
    Write-Success "ISO contents copied successfully"

    # Unmount source ISO
    Write-Step "Unmounting source ISO"
    Dismount-DiskImage -ImagePath (Resolve-Path $SourceISO).Path | Out-Null
    Write-Success "Source ISO unmounted"

    # Copy autounattend.xml to root
    Write-Step "Injecting autounattend.xml"
    Copy-Item -Path $requiredFiles["autounattend.xml"] -Destination $WorkDir -Force
    Write-Success "autounattend.xml copied to ISO root"

    # Create $OEM$ folder structure
    Write-Step "Creating `$OEM`$ folder structure"
    $oemPath = Join-Path $WorkDir "`$OEM`$"
    $setupPath = Join-Path $oemPath "`$1\Setup"
    New-Item -Path $setupPath -ItemType Directory -Force | Out-Null
    Write-Success "`$OEM`$\`$1\Setup folder created"

    # Copy setup files to $OEM$\$1\Setup
    Write-Step "Copying setup files to `$OEM`$\`$1\Setup"

    $filesToCopy = @(
        @{ Name = "bootstrap.ps1"; Path = $requiredFiles["bootstrap.ps1"] },
        @{ Name = "apps.json"; Path = $requiredFiles["apps.json"] },
        @{ Name = "Sophia-Preset.ps1"; Path = $requiredFiles["Sophia-Preset.ps1"] }
    )

    foreach ($file in $filesToCopy) {
        Copy-Item -Path $file.Path -Destination $setupPath -Force
        Write-Success "$($file.Name) copied"
    }

    # Create desktop shortcut script
    Write-Step "Creating desktop shortcut script"
    $shortcutScript = @'
# Create desktop shortcut for re-running bootstrap
$WshShell = New-Object -ComObject WScript.Shell
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "Run Windows Setup.lnk"
$shortcut = $WshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-ExecutionPolicy Bypass -File C:\Setup\bootstrap.ps1"
$shortcut.WorkingDirectory = "C:\Setup"
$shortcut.WindowStyle = 1
$shortcut.Description = "Re-run declarative Windows setup"
$shortcut.Save()
'@

    $shortcutScriptPath = Join-Path $setupPath "create-shortcut.ps1"
    Set-Content -Path $shortcutScriptPath -Value $shortcutScript -Force
    Write-Success "Desktop shortcut script created"

    # Build the ISO
    Write-Step "Building custom ISO with oscdimg"
    Write-Info "This may take several minutes..."

    $bootImage = Join-Path $WorkDir "boot\etfsboot.com"
    $efiBootImage = Join-Path $WorkDir "efi\microsoft\boot\efisys.bin"

    if (-not (Test-Path $bootImage)) {
        throw "BIOS boot image not found: $bootImage"
    }
    if (-not (Test-Path $efiBootImage)) {
        throw "UEFI boot image not found: $efiBootImage"
    }

    # Resolve output path
    $outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputISO)

    # Ensure output directory exists
    $outputDir = Split-Path $outputPath -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }

    # Build ISO with oscdimg
    # Using same parameters as official Windows ISO creation
    $oscdimgArgs = @(
        "-m",                           # Ignore maximum size limit
        "-o",                           # Optimize storage
        "-u2",                          # UDF file system
        "-udfver102",                   # UDF version 1.02
        "-bootdata:2#p0,e,b`"$bootImage`"#pEF,e,b`"$efiBootImage`"",  # Dual boot (BIOS + UEFI)
        "`"$WorkDir`"",                 # Source directory
        "`"$outputPath`""               # Output ISO
    )

    Write-Info "Running: oscdimg $($oscdimgArgs -join ' ')"

    $process = Start-Process -FilePath $oscdimgPath -ArgumentList $oscdimgArgs -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Success "ISO built successfully!"
    }
    else {
        throw "oscdimg.exe failed with exit code: $($process.ExitCode)"
    }

    # Verify output file was created
    if (Test-Path $outputPath) {
        $fileSize = (Get-Item $outputPath).Length / 1GB
        Write-Success "Output ISO created: $outputPath"
        Write-Info "File size: $($fileSize.ToString('F2')) GB"
    }
    else {
        throw "Output ISO file was not created"
    }

    # Summary
    Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║                  BUILD COMPLETED SUCCESSFULLY                ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Green

    Write-Host "Custom ISO Location:" -ForegroundColor Cyan
    Write-Host "  $outputPath" -ForegroundColor White
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "  1. Burn the ISO to a USB drive (use Rufus or similar)" -ForegroundColor White
    Write-Host "  2. Boot from the USB" -ForegroundColor White
    Write-Host "  3. Windows will install automatically with your configuration" -ForegroundColor White
    Write-Host "  4. bootstrap.ps1 will run on first login" -ForegroundColor White
    Write-Host ""

}
catch {
    Write-Host "`n" -NoNewline
    Write-ErrorMessage "Build failed: $($_.Exception.Message)"
    Write-Host "`nError details:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}
finally {
    # Cleanup
    Write-Step "Cleaning up temporary files"

    # Ensure ISO is unmounted even when keeping temp files
    try {
        if ($mount) {
            Dismount-DiskImage -ImagePath (Resolve-Path $SourceISO).Path -ErrorAction SilentlyContinue | Out-Null
        }
    }
    catch {
        # Ignore cleanup errors
    }

    if (-not $KeepTemp) {
        if (Test-Path $TempDir) {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "Temporary files removed"
        }
    }
    else {
        Write-Info "Temporary files kept at: $TempDir"
    }
}
