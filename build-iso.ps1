#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Builds a custom Windows 11 ISO with declarative-windows configuration baked in.

.DESCRIPTION
    This script takes a source Windows 11 ISO and creates a customized version with:
    - autounattend.xml for unattended installation
    - bootstrap.ps1, apps.json, optional-apps.json, and Sophia-Preset.ps1 copied via sources\$OEM$ structure when present
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
    - Free space for the measured staging and output estimates
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$SourceISO,

    [Parameter(Mandatory = $true)]
    [string]$OutputISO,

    [Parameter(Mandatory = $false)]
    [string]$SourceIsoHash,

    [Parameter(Mandatory = $false)]
    [string]$IsoLabel,

    [Parameter(Mandatory = $false)]
    [string]$OscdimgDownloadUrl,

    [Parameter(Mandatory = $false)]
    [switch]$KeepTemp
)

# Script configuration
$ErrorActionPreference = "Stop"
$ScriptRoot = $PSScriptRoot
$TempDir = Join-Path $env:TEMP "declarative-windows-iso-$(Get-Random)"
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

function Validate-SourceIsoHash {
    param(
        [Parameter(Mandatory)]
        [string]$IsoPath,

        [string]$ExpectedHash
    )

    if (-not $ExpectedHash) {
        Write-Info "Source ISO hash not provided; skipping validation"
        return
    }

    $actualHash = (Get-FileHash -Path $IsoPath -Algorithm SHA256).Hash

    if ($actualHash -ne $ExpectedHash) {
        throw "Source ISO checksum mismatch. Expected $ExpectedHash but got $actualHash."
    }

    Write-Success "Source ISO checksum verified"
}

$ModuleRoot = Join-Path $ScriptRoot "modules"
$StagedSetupPayloadModule = Join-Path $ModuleRoot "StagedSetupPayload.ps1"
if (Test-Path $StagedSetupPayloadModule) {
    . $StagedSetupPayloadModule
}

. (Join-Path $ModuleRoot "IsoBuildPreflight.ps1")

# Function to find oscdimg.exe from Windows ADK
function Find-OscdImg {
    param([string]$DownloadUrl)

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
        # Continue to download option
    }

    if ($DownloadUrl) {
        Write-Step "Downloading oscdimg.exe"

        $cacheDir = Join-Path $env:TEMP "declarative-windows-tools"
        if (-not (Test-Path $cacheDir)) {
            New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
        }

        $extension = [System.IO.Path]::GetExtension($DownloadUrl)
        $downloadPath = $null

        if ($extension -eq ".zip") {
            $downloadPath = Join-Path $cacheDir "oscdimg.zip"
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $downloadPath
            Expand-Archive -Path $downloadPath -DestinationPath $cacheDir -Force

            $oscdimgFile = Get-ChildItem -Path $cacheDir -Filter "oscdimg.exe" -Recurse | Select-Object -First 1
            if ($oscdimgFile) {
                Write-Success "Downloaded oscdimg.exe to: $($oscdimgFile.FullName)"
                return $oscdimgFile.FullName
            }
        }
        else {
            $downloadPath = Join-Path $cacheDir "oscdimg.exe"
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $downloadPath
            if (Test-Path $downloadPath) {
                Write-Success "Downloaded oscdimg.exe to: $downloadPath"
                return $downloadPath
            }
        }

        Write-ErrorMessage "oscdimg.exe download failed"
        throw "Failed to download oscdimg.exe from $DownloadUrl"
    }

    Write-ErrorMessage "oscdimg.exe not found!"
    Write-Host "`nPlease install Windows ADK from:" -ForegroundColor Yellow
    Write-Host "https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install" -ForegroundColor Yellow
    Write-Host "`nOr provide a direct download URL with -OscdimgDownloadUrl" -ForegroundColor Yellow
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

    $validateUnattendScript = Join-Path $ScriptRoot "validate-unattend.ps1"

    $payload = @(Get-IsoSetupPayload -ProjectRoot $ScriptRoot)
    $hasOptionalApps = Test-Path -LiteralPath (Join-Path $ScriptRoot 'optional-apps.json') -PathType Leaf
    Write-Step "Selected setup payload (paths only)"
    foreach ($file in $payload) {
        Write-Info "$($file.Source) -> $($file.RelativePath)"
    }
    if (-not $hasOptionalApps) {
        Write-Info "optional-apps.json not found - skipping optional apps payload"
    }

    # Reject invalid destinations and existing outputs before mounting or staging.
    $outputPath = Get-IsoOutputPath -SourceISO $SourceISO -OutputISO $OutputISO
    $outputDir = Split-Path $outputPath -Parent
    # Validate source ISO checksum if provided
    Validate-SourceIsoHash -IsoPath $SourceISO -ExpectedHash $SourceIsoHash

    # Validate autounattend.xml before doing any expensive ISO work
    Write-Step "Validating autounattend.xml"
    & $validateUnattendScript -UnattendPath (Join-Path $ScriptRoot "autounattend.xml") -SourceISO $SourceISO
    Write-Success "autounattend.xml validation passed"

    # Find oscdimg.exe
    $oscdimgPath = Find-OscdImg -DownloadUrl $OscdimgDownloadUrl

    # Mount source ISO
    Write-Step "Mounting source ISO"
    Write-Info "Source: $SourceISO"

    $mount = Mount-DiskImage -ImagePath (Resolve-Path $SourceISO).Path -PassThru
    $driveLetter = ($mount | Get-Volume).DriveLetter
    $sourceRoot = "${driveLetter}:\"

    Write-Success "ISO mounted at: $sourceRoot"

    # Capture the original ISO volume label for oscdimg
    if (-not $IsoLabel) {
        $IsoLabel = (Get-Volume -DriveLetter $driveLetter).FileSystemLabel
        if ($IsoLabel) {
            Write-Success "Captured original ISO label: $IsoLabel"
        }
        else {
            $IsoLabel = "CCCOMA_X64FRE_EN-US_DV9"
            Write-Info "Could not read original label, using default: $IsoLabel"
        }
    }
    else {
        Write-Info "Using user-provided ISO label: $IsoLabel"
    }

    Assert-IsoBuildSpace -SourceRoot $sourceRoot -Payload $payload -StagingDirectory $env:TEMP -OutputDirectory $outputDir

    # Stage only after destination and measured capacity checks have passed.
    [void][IO.Directory]::CreateDirectory($WorkDir)
    # Copy ISO contents to working directory
    Write-Step "Copying ISO contents (this may take a few minutes)"
    Write-Info "Destination: $WorkDir"

    Copy-Item -Path "$sourceRoot*" -Destination $WorkDir -Recurse -Force
    Write-Success "ISO contents copied successfully"

    # Unmount source ISO
    Write-Step "Unmounting source ISO"
    Dismount-DiskImage -ImagePath (Resolve-Path $SourceISO).Path | Out-Null
    Write-Success "Source ISO unmounted"

    Write-Step 'Copying selected setup payload to sources\$OEM$\$1\Setup'
    Copy-IsoSetupPayload -Payload $payload -WorkRoot $WorkDir
    # Fail the build here if the staged tree does not match the paths unattend will use later.
    Write-Step "Validating staged ISO layout"
    Validate-StagedIsoLayout -WorkRoot $WorkDir -UnattendPath (Join-Path $WorkDir "autounattend.xml") -HasOptionalApps $hasOptionalApps

    # Build the ISO
    Write-Step "Building custom ISO with oscdimg"
    Write-Info "This may take several minutes..."

    $bootImage = Join-Path $WorkDir "boot\etfsboot.com"
    $efiBootImage = Join-Path $WorkDir "efi\microsoft\boot\efisys_noprompt.bin"

    if (-not (Test-Path $bootImage)) {
        throw "BIOS boot image not found: $bootImage"
    }
    if (-not (Test-Path $efiBootImage)) {
        # Fall back to efisys.bin if noprompt variant is missing
        $efiBootImage = Join-Path $WorkDir "efi\microsoft\boot\efisys.bin"
        if (-not (Test-Path $efiBootImage)) {
            throw "UEFI boot image not found. Neither efisys_noprompt.bin nor efisys.bin exist."
        }
        Write-Info "efisys_noprompt.bin not found, falling back to efisys.bin"
    }

    # Build beside the destination, then publish without replacing an existing file.
    $pendingOutputDir = Join-Path $outputDir ("declarative-windows-iso-" + [guid]::NewGuid())
    [void][IO.Directory]::CreateDirectory($pendingOutputDir)
    $pendingOutput = Join-Path $pendingOutputDir 'output.iso'
    # Build ISO with oscdimg
    # Using same parameters as official Windows ISO creation
    $oscdimgArgs = @(
        "-m",                           # Ignore maximum size limit
        "-o",                           # Optimize storage
        "-u2",                          # UDF file system
        "-udfver102",                   # UDF version 1.02
        "-l$IsoLabel",                  # ISO label
        "-bootdata:2#p0,e,b`"$bootImage`"#pEF,e,b`"$efiBootImage`"",  # Dual boot (BIOS + UEFI)
        "`"$WorkDir`"",                 # Source directory
        "`"$pendingOutput`""               # Output ISO
    )

    Write-Info "Running: oscdimg $($oscdimgArgs -join ' ')"

    $process = Start-Process -FilePath $oscdimgPath -ArgumentList $oscdimgArgs -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Success "ISO built successfully!"
    }
    else {
        throw "oscdimg.exe failed with exit code: $($process.ExitCode)"
    }

    [IO.File]::Move($pendingOutput, $outputPath)

    # Verify output file was created
    if (Test-Path -LiteralPath $outputPath) {
        $fileSize = (Get-Item -LiteralPath $outputPath).Length / 1GB
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
    Write-Host "  3. Choose the target disk in Windows Setup, then let post-install automation continue" -ForegroundColor White
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
    if ($pendingOutputDir -and (Test-Path -LiteralPath $pendingOutputDir)) {
        # Only this build's generated ISO is removed; never remove the destination.
        if (Test-Path -LiteralPath $pendingOutput) {
            Remove-Item -LiteralPath $pendingOutput -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $pendingOutputDir -ErrorAction SilentlyContinue
    }
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
