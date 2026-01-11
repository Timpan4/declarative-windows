#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Bootstrap script for declarative Windows configuration.

.DESCRIPTION
    Main orchestration script that:
    - Imports applications from apps.json via WinGet
    - Executes Sophia Script preset for OS tweaks
    - Creates logs and status reports

.NOTES
    Version: 0.1.0 (Minimal Viable Product)
    This script is designed to be idempotent - safe to run multiple times.
#>

[CmdletBinding()]
param()

# Script configuration
$ErrorActionPreference = "Continue"
$SetupPath = "C:\Setup"
$LogFile = Join-Path $SetupPath "install.log"
$AppsJson = Join-Path $SetupPath "apps.json"
$SophiaPreset = Join-Path $SetupPath "Sophia-Preset.ps1"
$SophiaMarker = Join-Path $SetupPath "sophia.completed"
$WingetMarker = Join-Path $SetupPath "winget.completed"
$SummaryItems = [System.Collections.Generic.List[object]]::new()

# Initialize logging
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Console output with colors
    switch ($Level) {
        'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
        default   { Write-Host $logMessage }
    }

    # File output
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

function Add-SummaryItem {
    param(
        [Parameter(Mandatory)]
        [string]$Step,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $SummaryItems.Add([pscustomobject]@{
        Step = $Step
        Status = $Status
        Message = $Message
    })
}

function Write-SummaryReport {
    param([string]$DesktopPath)

    $summaryPath = Join-Path $DesktopPath "Setup Summary.txt"
    $summaryLines = @(
        "Declarative Windows Setup Summary",
        "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        ""
    )

    foreach ($item in $SummaryItems) {
        $summaryLines += "{0} {1}: {2}" -f $item.Status, $item.Step, $item.Message
    }

    Set-Content -Path $summaryPath -Value $summaryLines -Force
    return $summaryPath
}

function Wait-ForNetwork {
    param(
        [int]$TimeoutSeconds = 300,
        [int]$DelaySeconds = 5
    )

    $startTime = Get-Date
    $pingTargets = @("8.8.8.8", "1.1.1.1")
    $httpsHost = "winget.azureedge.net"
    $httpsPort = 443
    $httpsUri = "https://$httpsHost"
    $canTestNetConnection = Get-Command Test-NetConnection -ErrorAction SilentlyContinue
    $canInvokeWebRequest = Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue

    Write-Log "Waiting for network connectivity..." -Level INFO

    while ((Get-Date) -lt $startTime.AddSeconds($TimeoutSeconds)) {
        foreach ($target in $pingTargets) {
            if (Test-Connection -ComputerName $target -Count 1 -Quiet) {
                Write-Log "Network connectivity confirmed via ping ($target)" -Level SUCCESS
                return $true
            }
        }

        if ($canTestNetConnection) {
            $httpsSuccess = Test-NetConnection -ComputerName $httpsHost -Port $httpsPort -InformationLevel Quiet
            if ($httpsSuccess) {
                Write-Log "Network connectivity confirmed via HTTPS ($httpsHost)" -Level SUCCESS
                return $true
            }
        }
        elseif ($canInvokeWebRequest) {
            try {
                Invoke-WebRequest -Uri $httpsUri -Method Head -UseBasicParsing -TimeoutSec 5 | Out-Null
                Write-Log "Network connectivity confirmed via HTTPS ($httpsHost)" -Level SUCCESS
                return $true
            }
            catch {
                # continue waiting
            }
        }

        Start-Sleep -Seconds $DelaySeconds
    }

    Write-Log "Network connectivity check timed out after ${TimeoutSeconds}s" -Level ERROR
    return $false
}

function Get-WingetPackageIdsFromJson {
    param([string]$Path)

    $content = Get-Content -Path $Path -Raw
    $data = $content | ConvertFrom-Json
    $packageIds = @()

    foreach ($source in $data.Sources) {
        foreach ($package in $source.Packages) {
            if ($package.PackageIdentifier) {
                $packageIds += $package.PackageIdentifier
            }
        }
    }

    return $packageIds | Sort-Object -Unique
}

function Test-WingetPackageInstalled {
    param([string]$PackageId)

    $result = winget list --id $PackageId --exact 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return $result -match [regex]::Escape($PackageId)
}

function Write-FilteredAppsJson {
    param(
        [object]$AppsData,
        [string[]]$PackageIds,
        [string]$OutputPath
    )

    $filteredSources = foreach ($source in $AppsData.Sources) {
        $filteredPackages = $source.Packages | Where-Object {
            $PackageIds -contains $_.PackageIdentifier
        }

        if ($filteredPackages.Count -gt 0) {
            [pscustomobject]@{
                Packages = $filteredPackages
                SourceDetails = $source.SourceDetails
            }
        }
    }

    $filteredData = [pscustomobject]@{
        '$schema' = $AppsData.'$schema'
        Sources = $filteredSources
    }

    $filteredData | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Force
}

# Main execution
try {
    Write-Log "========================================" -Level INFO
    Write-Log "Windows Setup Bootstrap - Starting" -Level INFO
    Write-Log "========================================" -Level INFO

    # Verify admin privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Log "ERROR: This script must be run as Administrator" -Level ERROR
        exit 1
    }
    Write-Log "Administrator privileges verified" -Level SUCCESS

    # Check if setup files exist
    if (-not (Test-Path $SetupPath)) {
        Write-Log "ERROR: Setup directory not found at $SetupPath" -Level ERROR
        exit 1
    }

    # Step 1: Import applications via WinGet
    Write-Log "Step 1: Importing applications from WinGet" -Level INFO

    if (Test-Path $AppsJson) {
        $tempAppsJson = $null

        try {
            Write-Log "Found apps.json at $AppsJson" -Level INFO

            if (-not (Wait-ForNetwork)) {
                Add-SummaryItem -Step "WinGet" -Status "✗" -Message "Network unavailable; skipped app install"
            }
            else {
                $appsData = Get-Content -Path $AppsJson -Raw | ConvertFrom-Json
                $packageIds = Get-WingetPackageIdsFromJson -Path $AppsJson

                if (-not $packageIds -or $packageIds.Count -eq 0) {
                    Write-Log "apps.json contains no packages to install" -Level WARNING
                    Add-SummaryItem -Step "WinGet" -Status "⚠" -Message "No packages found in apps.json"
                }
                else {
                    $appsHash = (Get-FileHash -Path $AppsJson -Algorithm SHA256).Hash
                    $markerHash = $null

                    if (Test-Path $WingetMarker) {
                        $markerHash = (Get-Content -Path $WingetMarker -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
                    }

                    $missingPackages = @()

                    foreach ($packageId in $packageIds) {
                        if (-not (Test-WingetPackageInstalled -PackageId $packageId)) {
                            $missingPackages += $packageId
                        }
                    }

                    if ($missingPackages.Count -eq 0) {
                        Write-Log "All WinGet packages already installed" -Level SUCCESS
                        Set-Content -Path $WingetMarker -Value $appsHash -Force

                        if ($markerHash -and $markerHash -eq $appsHash) {
                            Add-SummaryItem -Step "WinGet" -Status "✓" -Message "Already up to date ($WingetMarker)"
                        }
                        else {
                            Add-SummaryItem -Step "WinGet" -Status "✓" -Message "All packages already installed ($WingetMarker)"
                        }
                    }
                    else {
                        if ($markerHash -and $markerHash -ne $appsHash) {
                            Write-Log "apps.json changed since last WinGet run" -Level INFO
                        }

                        $tempAppsJson = Join-Path $env:TEMP "apps-missing-$(Get-Random).json"
                        Write-FilteredAppsJson -AppsData $appsData -PackageIds $missingPackages -OutputPath $tempAppsJson

                        Write-Log "Installing $($missingPackages.Count) missing packages" -Level INFO
                        Write-Log "Running: winget import $tempAppsJson --accept-package-agreements --accept-source-agreements" -Level INFO

                        $wingetResult = winget import $tempAppsJson --accept-package-agreements --accept-source-agreements 2>&1

                        if ($LASTEXITCODE -eq 0) {
                            Write-Log "WinGet import completed successfully" -Level SUCCESS
                            Set-Content -Path $WingetMarker -Value $appsHash -Force
                            Add-SummaryItem -Step "WinGet" -Status "✓" -Message "Installed $($missingPackages.Count) packages ($WingetMarker)"
                        }
                        else {
                            Write-Log "WinGet import completed with warnings (exit code: $LASTEXITCODE)" -Level WARNING
                            Add-SummaryItem -Step "WinGet" -Status "⚠" -Message "WinGet import completed with warnings"
                        }
                    }
                }
            }
        }
        catch {
            Write-Log "ERROR during WinGet import: $($_.Exception.Message)" -Level ERROR
            Add-SummaryItem -Step "WinGet" -Status "✗" -Message "WinGet import failed"
        }
        finally {
            if ($tempAppsJson -and (Test-Path $tempAppsJson)) {
                Remove-Item -Path $tempAppsJson -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        Write-Log "WARNING: apps.json not found at $AppsJson - skipping application import" -Level WARNING
        Add-SummaryItem -Step "WinGet" -Status "⚠" -Message "apps.json not found"
    }

    # Step 2: Execute Sophia Script preset
    Write-Log "Step 2: Executing Sophia Script preset" -Level INFO

    if (Test-Path $SophiaPreset) {
        $presetHash = (Get-FileHash -Path $SophiaPreset -Algorithm SHA256).Hash
        $markerHash = $null

        if (Test-Path $SophiaMarker) {
            $markerHash = (Get-Content -Path $SophiaMarker -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
        }

        if ($markerHash -and $markerHash -eq $presetHash) {
            Write-Log "Sophia Script already applied; skipping" -Level INFO
            Add-SummaryItem -Step "Sophia" -Status "✓" -Message "Already applied ($SophiaMarker)"
        }
        else {
            if ($markerHash) {
                Write-Log "Sophia preset changed since last run; reapplying" -Level INFO
            }

            try {
                Write-Log "Found Sophia preset at $SophiaPreset" -Level INFO
                Write-Log "Executing Sophia Script..." -Level INFO

                $global:LASTEXITCODE = $null
                & $SophiaPreset
                $exitCode = $global:LASTEXITCODE

                if ($? -and ($null -eq $exitCode -or $exitCode -eq 0)) {
                    Write-Log "Sophia Script execution completed" -Level SUCCESS
                    Set-Content -Path $SophiaMarker -Value $presetHash -Force
                    Add-SummaryItem -Step "Sophia" -Status "✓" -Message "Sophia preset applied ($SophiaMarker)"
                } else {
                    Write-Log "Sophia Script completed with exit code: $exitCode" -Level WARNING
                    Add-SummaryItem -Step "Sophia" -Status "⚠" -Message "Sophia completed with warnings"
                }
            }
            catch {
                Write-Log "ERROR during Sophia Script execution: $($_.Exception.Message)" -Level ERROR
                Add-SummaryItem -Step "Sophia" -Status "✗" -Message "Sophia execution failed"
            }
        }
    }
    else {
        Write-Log "WARNING: Sophia preset not found at $SophiaPreset - skipping OS tweaks" -Level WARNING
        Add-SummaryItem -Step "Sophia" -Status "⚠" -Message "Sophia preset not found"
    }

    # Step 3: Create desktop shortcut and summary report
    Write-Log "Step 3: Creating desktop assets" -Level INFO

    $desktopPath = [Environment]::GetFolderPath("Desktop")

    try {
        $shortcutPath = Join-Path $desktopPath "Run Windows Setup.lnk"
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "powershell.exe"
        $shortcut.Arguments = "-ExecutionPolicy Bypass -File C:\Setup\bootstrap.ps1"
        $shortcut.WorkingDirectory = "C:\Setup"
        $shortcut.Description = "Re-run declarative Windows setup"
        $shortcut.Save()

        Write-Log "Desktop shortcut created at $shortcutPath" -Level SUCCESS
        Add-SummaryItem -Step "Shortcut" -Status "✓" -Message "Run Windows Setup.lnk created"
    }
    catch {
        Write-Log "WARNING: Failed to create desktop shortcut: $($_.Exception.Message)" -Level WARNING
        Add-SummaryItem -Step "Shortcut" -Status "⚠" -Message "Failed to create shortcut"
    }

    try {
        $summaryPath = Write-SummaryReport -DesktopPath $desktopPath
        Write-Log "Summary report written to $summaryPath" -Level SUCCESS
    }
    catch {
        Write-Log "WARNING: Failed to write summary report: $($_.Exception.Message)" -Level WARNING
    }

    # Completion
    Write-Log "========================================" -Level INFO
    Write-Log "Windows Setup Bootstrap - Completed" -Level SUCCESS
    Write-Log "========================================" -Level INFO
    Write-Log "Log file saved to: $LogFile" -Level INFO

}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}
