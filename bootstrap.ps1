#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Bootstrap script for declarative Windows configuration.

.DESCRIPTION
    Restores applications, clones the canonical repo when available, applies
    Sophia and registry configuration, and creates desktop shortcuts.
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$PromptRestart,
    [switch]$OptionalAppsOnly
)

$ErrorActionPreference = "Continue"
$SetupPath = "C:\Setup"
$LogFile = Join-Path $SetupPath "install.log"
$AppsJson = Join-Path $SetupPath "apps.json"
$OptionalAppsJson = Join-Path $SetupPath "optional-apps.json"
$RestoreScript = Join-Path $SetupPath "restore-backup.ps1"
$SophiaPreset = Join-Path $SetupPath "Sophia-Preset.ps1"
$SophiaMarker = Join-Path $SetupPath "sophia.completed"
$WingetMarker = Join-Path $SetupPath "winget.completed"
$OptionalWingetMarker = Join-Path $SetupPath "optional-winget.completed"
$RegistryConfig = Join-Path $SetupPath "config\registry.json"
$RegistryScript = Join-Path $SetupPath "apply-registry.ps1"
$StateFile = Join-Path $SetupPath "state.json"
$CanonicalRepoPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "declarative-windows"
$CanonicalBootstrap = Join-Path $CanonicalRepoPath "bootstrap.ps1"
$SophiaDir = Join-Path $SetupPath "Sophia-Script"
$SophiaScript = Join-Path $SophiaDir "Sophia.ps1"
$SophiaVersion = "7.1.4"
$SophiaZipName = "Sophia.Script.for.Windows.11.v$SophiaVersion.zip"
$SophiaDownloadUrl = "https://github.com/farag2/Sophia-Script-for-Windows/releases/download/$SophiaVersion/$SophiaZipName"
$FailedInstallsLog = Join-Path $SetupPath "failed-installs.log"
$StepIds = @("winget", "repo", "sophia", "registry", "shortcut", "restoreShortcut", "optionalShortcut", "optionalWinget", "summary")
$SetupState = $null
$SummaryItems = [System.Collections.Generic.List[object]]::new()
$FailedItems = [System.Collections.Generic.List[object]]::new()
$script:BackupManifestPath = $null
$script:BackupManifest = $null

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'ERROR' { Write-Host $logMessage -ForegroundColor Red }
        default { Write-Host $logMessage }
    }

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

function Convert-StepsToHashtable {
    param([object]$Steps)

    $stepsTable = [ordered]@{}
    if ($Steps) {
        foreach ($property in $Steps.PSObject.Properties) {
            $stepsTable[$property.Name] = $property.Value
        }
    }

    return $stepsTable
}

function Initialize-State {
    param(
        [string]$StatePath,
        [string[]]$StepIds
    )

    $state = $null

    if (Test-Path $StatePath) {
        try {
            $state = Get-Content -Path $StatePath -Raw | ConvertFrom-Json
        }
        catch {
            $state = $null
        }
    }

    if (-not $state) {
        $state = [pscustomobject]@{
            version = "1"
            lastUpdated = (Get-Date).ToString("o")
            steps = [ordered]@{}
        }
    }

    $state.steps = Convert-StepsToHashtable -Steps $state.steps

    foreach ($stepId in $StepIds) {
        if (-not $state.steps.Contains($stepId)) {
            $state.steps[$stepId] = [pscustomobject]@{
                status = "pending"
                lastRun = $null
                message = ""
            }
        }
    }

    return $state
}

function Save-State {
    param(
        [Parameter(Mandatory)]
        [object]$State,

        [Parameter(Mandatory)]
        [string]$StatePath
    )

    $State.lastUpdated = (Get-Date).ToString("o")
    $State | ConvertTo-Json -Depth 6 | Set-Content -Path $StatePath -Force
}

function Set-StepState {
    param(
        [Parameter(Mandatory)]
        [string]$StepId,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $SetupState.steps.Contains($StepId)) {
        $SetupState.steps[$StepId] = [pscustomobject]@{
            status = "pending"
            lastRun = $null
            message = ""
        }
    }

    $SetupState.steps[$StepId].status = $Status
    $SetupState.steps[$StepId].lastRun = (Get-Date).ToString("o")
    $SetupState.steps[$StepId].message = $Message
    Save-State -State $SetupState -StatePath $StateFile
}

function Should-RunStep {
    param([string]$StepId)

    if ($Force) {
        return $true
    }

    if (-not $SetupState) {
        return $true
    }

    if (-not $SetupState.steps.Contains($StepId)) {
        return $true
    }

    return $SetupState.steps[$StepId].status -ne "done"
}

function Add-FailedItem {
    param(
        [Parameter(Mandatory)]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$Item,

        [string]$Reason = ""
    )

    $FailedItems.Add([pscustomobject]@{
        Category = $Category
        Item     = $Item
        Reason   = $Reason
    })
}

function Write-FailedInstallsReport {
    param([string]$DesktopPath)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $lines = @(
        "Failed Installs - $timestamp",
        "========================================"
    )

    if ($FailedItems.Count -eq 0) {
        $lines += ""
        $lines += "No failures recorded. Everything installed successfully."
    }
    else {
        $categories = $FailedItems | Select-Object -ExpandProperty Category -Unique
        foreach ($category in $categories) {
            $lines += ""
            $lines += "${category}:"
            foreach ($entry in ($FailedItems | Where-Object { $_.Category -eq $category })) {
                $detail = if ($entry.Reason) { " - $($entry.Reason)" } else { "" }
                $lines += "  - $($entry.Item)$detail"
            }
        }
        $lines += ""
        $lines += "========================================"
        $lines += "Review the items above and install/apply them manually."
    }

    $lines | Set-Content -Path $FailedInstallsLog -Force

    if ($DesktopPath) {
        $desktopReport = Join-Path $DesktopPath "Failed Installs.txt"
        $lines | Set-Content -Path $desktopReport -Force
        return $desktopReport
    }

    return $FailedInstallsLog
}

function Get-SophiaScript {
    if (Test-Path $SophiaScript) {
        Write-Log "Sophia Script already extracted at $SophiaDir" -Level INFO
        return $SophiaScript
    }

    Write-Log "Sophia Script not found; downloading v$SophiaVersion..." -Level INFO

    $zipPath = Join-Path $SetupPath $SophiaZipName

    try {
        Invoke-WebRequest -Uri $SophiaDownloadUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
        Write-Log "Downloaded $SophiaZipName" -Level SUCCESS
    }
    catch {
        Write-Log "Failed to download Sophia Script: $($_.Exception.Message)" -Level WARNING
        return $null
    }

    try {
        if (Test-Path $SophiaDir) {
            Remove-Item -Path $SophiaDir -Recurse -Force
        }

        Expand-Archive -Path $zipPath -DestinationPath $SetupPath -Force

        # The zip extracts to a versioned subfolder; find Sophia.ps1 wherever it landed
        $sophiaPs1 = Get-ChildItem -Path $SetupPath -Filter "Sophia.ps1" -Recurse -File |
            Select-Object -First 1

        if (-not $sophiaPs1) {
            Write-Log "Sophia.ps1 not found after extraction" -Level WARNING
            return $null
        }

        # Normalise to the known $SophiaDir path so the marker stays consistent
        $extractedDir = $sophiaPs1.DirectoryName
        if ($extractedDir -ne $SophiaDir) {
            if (Test-Path $SophiaDir) { Remove-Item -Path $SophiaDir -Recurse -Force }
            Rename-Item -Path $extractedDir -NewName (Split-Path $SophiaDir -Leaf)
        }

        Write-Log "Sophia Script extracted to $SophiaDir" -Level SUCCESS
        return $SophiaScript
    }
    catch {
        Write-Log "Failed to extract Sophia Script: $($_.Exception.Message)" -Level WARNING
        return $null
    }
    finally {
        if (Test-Path $zipPath) {
            Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        }
    }
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
            if (Test-NetConnection -ComputerName $httpsHost -Port $httpsPort -InformationLevel Quiet) {
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

function Invoke-WingetManifestInstall {
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,

        [Parameter(Mandatory)]
        [string]$StepId,

        [Parameter(Mandatory)]
        [string]$SummaryStep,

        [Parameter(Mandatory)]
        [string]$MarkerPath,

        [Parameter(Mandatory)]
        [string]$ManifestLabel,

        [Parameter(Mandatory)]
        [string]$MissingManifestMessage
    )

    $tempAppsJson = $null

    if (Test-Path $ManifestPath) {
        try {
            Write-Log "Found $ManifestLabel at $ManifestPath" -Level INFO

            if (-not (Wait-ForNetwork)) {
                Add-SummaryItem -Step $SummaryStep -Status "FAIL" -Message "Network unavailable; skipped install"
                Set-StepState -StepId $StepId -Status "failed" -Message "Network unavailable"
                return $false
            }

            $appsData = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json
            $packageIds = Get-WingetPackageIdsFromJson -Path $ManifestPath

            if (-not $packageIds -or $packageIds.Count -eq 0) {
                Write-Log "$ManifestLabel contains no packages to install" -Level WARNING
                Add-SummaryItem -Step $SummaryStep -Status "WARN" -Message "No packages found in $ManifestLabel"
                Set-StepState -StepId $StepId -Status "done" -Message "No packages found"
                return $true
            }

            $appsHash = (Get-FileHash -Path $ManifestPath -Algorithm SHA256).Hash
            $markerHash = $null
            if (Test-Path $MarkerPath) {
                $markerHash = (Get-Content -Path $MarkerPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
            }

            $missingPackages = foreach ($packageId in $packageIds) {
                if (-not (Test-WingetPackageInstalled -PackageId $packageId)) {
                    $packageId
                }
            }

            if (-not $missingPackages) {
                Write-Log "All packages from $ManifestLabel are already installed" -Level SUCCESS
                Set-Content -Path $MarkerPath -Value $appsHash -Force
                Add-SummaryItem -Step $SummaryStep -Status "OK" -Message "Already up to date ($MarkerPath)"
                Set-StepState -StepId $StepId -Status "done" -Message "Already up to date"
                return $true
            }

            if ($markerHash -and $markerHash -ne $appsHash) {
                Write-Log "$ManifestLabel changed since last WinGet run" -Level INFO
            }

            $tempAppsJson = Join-Path $env:TEMP "apps-missing-$(Get-Random).json"
            Write-FilteredAppsJson -AppsData $appsData -PackageIds $missingPackages -OutputPath $tempAppsJson

            Write-Log "Installing $($missingPackages.Count) missing packages from $ManifestLabel" -Level INFO
            $null = winget import $tempAppsJson --accept-package-agreements --accept-source-agreements 2>&1

            $stillMissing = foreach ($packageId in $missingPackages) {
                if (-not (Test-WingetPackageInstalled -PackageId $packageId)) {
                    $packageId
                }
            }

            foreach ($packageId in $stillMissing) {
                Add-FailedItem -Category $SummaryStep -Item $packageId -Reason "Not installed after import from $ManifestLabel"
                Write-Log "WARNING: $packageId still not installed after WinGet import from $ManifestLabel" -Level WARNING
            }

            if (-not $stillMissing) {
                Write-Log "WinGet import from $ManifestLabel completed successfully" -Level SUCCESS
                Set-Content -Path $MarkerPath -Value $appsHash -Force
                Add-SummaryItem -Step $SummaryStep -Status "OK" -Message "Installed $($missingPackages.Count) packages"
                Set-StepState -StepId $StepId -Status "done" -Message "Installed $($missingPackages.Count) packages"
                return $true
            }

            $failCount = @($stillMissing).Count
            Write-Log "WinGet import from $ManifestLabel finished; $failCount package(s) failed" -Level WARNING
            Add-SummaryItem -Step $SummaryStep -Status "WARN" -Message "$failCount package(s) failed - see Failed Installs.txt"
            Set-StepState -StepId $StepId -Status "failed" -Message "$failCount package(s) failed"
            return $false
        }
        catch {
            Write-Log "ERROR during WinGet import from ${ManifestLabel}: $($_.Exception.Message)" -Level ERROR
            Add-SummaryItem -Step $SummaryStep -Status "FAIL" -Message "WinGet import failed"
            Set-StepState -StepId $StepId -Status "failed" -Message "WinGet import failed"
            return $false
        }
        finally {
            if ($tempAppsJson -and (Test-Path $tempAppsJson)) {
                Remove-Item -Path $tempAppsJson -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Log "WARNING: $ManifestLabel not found at $ManifestPath - skipping application import" -Level WARNING
    Add-SummaryItem -Step $SummaryStep -Status "WARN" -Message $MissingManifestMessage
    Set-StepState -StepId $StepId -Status "done" -Message $MissingManifestMessage
    return $false
}

function New-DesktopShortcut {
    param(
        [Parameter(Mandatory)]
        [string]$ShortcutPath,

        [Parameter(Mandatory)]
        [string]$TargetPath,

        [Parameter(Mandatory)]
        [string]$Arguments,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory)]
        [string]$Description
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = $Description
    $shortcut.Save()
}

function Find-BackupManifest {
    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object {
        $_.Root -ne "$($env:SystemDrive)\"
    }

    $matches = foreach ($drive in $drives) {
        $candidateRoot = Join-Path $drive.Root "declarative-windows-backup"
        if (-not (Test-Path $candidateRoot)) {
            continue
        }

        Get-ChildItem -Path $candidateRoot -Filter "backup-manifest.json" -Recurse -File -ErrorAction SilentlyContinue
    }

    $newestMatch = $matches | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($newestMatch) {
        return $newestMatch.FullName
    }

    return $null
}

function Get-BackupManifestData {
    if (-not $script:BackupManifestPath) {
        $script:BackupManifestPath = Find-BackupManifest
    }

    if (-not $script:BackupManifestPath -or -not (Test-Path $script:BackupManifestPath)) {
        return $null
    }

    if (-not $script:BackupManifest) {
        try {
            $script:BackupManifest = Get-Content -Path $script:BackupManifestPath -Raw | ConvertFrom-Json
        }
        catch {
            Write-Log "WARNING: Failed to read backup manifest at $script:BackupManifestPath" -Level WARNING
            $script:BackupManifest = $null
        }
    }

    return $script:BackupManifest
}

function Ensure-CanonicalRepo {
    param([object]$Manifest)

    if (Test-Path (Join-Path $CanonicalRepoPath ".git")) {
        Write-Log "Using existing cloned repo at $CanonicalRepoPath" -Level SUCCESS
        return $true
    }

    if ((Test-Path $CanonicalRepoPath) -and -not (Test-Path (Join-Path $CanonicalRepoPath ".git"))) {
        Write-Log "Canonical repo path exists but is not a git repository: $CanonicalRepoPath" -Level WARNING
        return $false
    }

    if (-not $Manifest -or -not $Manifest.repo.remoteUrl) {
        Write-Log "Backup manifest does not contain an origin remote URL" -Level WARNING
        return $false
    }

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        Write-Log "Git is not available yet; skipping canonical repo clone" -Level WARNING
        return $false
    }

    try {
        $documentsPath = Split-Path -Path $CanonicalRepoPath -Parent
        if (-not (Test-Path $documentsPath)) {
            New-Item -Path $documentsPath -ItemType Directory -Force | Out-Null
        }

        $cloneOutput = & $gitCommand.Source clone $Manifest.repo.remoteUrl $CanonicalRepoPath 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $CanonicalRepoPath ".git"))) {
            Write-Log "Cloned repo to $CanonicalRepoPath" -Level SUCCESS
            return $true
        }

        Write-Log "Git clone failed: $($cloneOutput | Out-String)" -Level WARNING
    }
    catch {
        Write-Log "Git clone failed: $($_.Exception.Message)" -Level WARNING
    }

    return $false
}

function Restore-RepoFilesFromManifest {
    param([object]$Manifest)

    if (-not $Manifest -or -not $Manifest.repoFiles) {
        return $false
    }

    $restored = $false
    foreach ($repoFile in $Manifest.repoFiles) {
        if (-not (Test-Path $repoFile.backupPath)) {
            continue
        }

        $destination = Join-Path $CanonicalRepoPath $repoFile.relativePath
        $destinationParent = Split-Path -Path $destination -Parent
        if (-not (Test-Path $destinationParent)) {
            New-Item -Path $destinationParent -ItemType Directory -Force | Out-Null
        }

        Copy-Item -Path $repoFile.backupPath -Destination $destination -Force
        $restored = $true
    }

    return $restored
}

function Get-RunBootstrapTarget {
    if (Test-Path $CanonicalBootstrap) {
        return $CanonicalBootstrap
    }

    return (Join-Path $SetupPath "bootstrap.ps1")
}

try {
    Write-Log "========================================" -Level INFO
    Write-Log "Windows Setup Bootstrap - Starting" -Level INFO
    Write-Log "========================================" -Level INFO

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Log "ERROR: This script must be run as Administrator" -Level ERROR
        exit 1
    }

    Write-Log "Administrator privileges verified" -Level SUCCESS

    if (-not (Test-Path $SetupPath)) {
        Write-Log "ERROR: Setup directory not found at $SetupPath" -Level ERROR
        exit 1
    }

    $SetupState = Initialize-State -StatePath $StateFile -StepIds $StepIds
    Save-State -State $SetupState -StatePath $StateFile

    if ($DryRun) {
        Write-Log "Dry run mode enabled; no system changes will be applied" -Level WARNING
    }

    if ($OptionalAppsOnly) {
        Write-Log "Optional apps only mode enabled; skipping core setup steps" -Level INFO
    }

    $stepId = "winget"
    if ($OptionalAppsOnly) {
        Write-Log "Step 1: Skipping WinGet core apps (optional apps only mode)" -Level INFO
    }
    elseif (-not (Should-RunStep -StepId $stepId)) {
        Write-Log "Step 1: Skipping WinGet (already completed)" -Level INFO
        Add-SummaryItem -Step "WinGet" -Status "OK" -Message "Skipped (already completed)"
    }
    elseif ($DryRun) {
        Write-Log "Step 1: Dry run - skipping WinGet import" -Level WARNING
        Add-SummaryItem -Step "WinGet" -Status "WARN" -Message "Dry run: WinGet import skipped"
        Set-StepState -StepId $stepId -Status "pending" -Message "Dry run: WinGet import skipped"
    }
    else {
        $null = Invoke-WingetManifestInstall -ManifestPath $AppsJson -StepId $stepId -SummaryStep "WinGet" -MarkerPath $WingetMarker -ManifestLabel "apps.json" -MissingManifestMessage "apps.json not found"
    }

    $stepId = "repo"
    if ($OptionalAppsOnly) {
        Write-Log "Step 2: Skipping canonical repo restore (optional apps only mode)" -Level INFO
    }
    elseif (-not (Should-RunStep -StepId $stepId)) {
        Write-Log "Step 2: Skipping canonical repo restore (already completed)" -Level INFO
        Add-SummaryItem -Step "Repo" -Status "OK" -Message "Skipped (already completed)"
    }
    elseif ($DryRun) {
        Write-Log "Step 2: Dry run - skipping canonical repo restore" -Level WARNING
        Add-SummaryItem -Step "Repo" -Status "WARN" -Message "Dry run: repo clone skipped"
        Set-StepState -StepId $stepId -Status "pending" -Message "Dry run: repo clone skipped"
    }
    else {
        $manifest = Get-BackupManifestData
        if (-not $manifest) {
            Write-Log "No backup manifest found; canonical repo clone skipped" -Level WARNING
            Add-SummaryItem -Step "Repo" -Status "WARN" -Message "Backup manifest not found; using C:\Setup fallback"
            Set-StepState -StepId $stepId -Status "failed" -Message "Backup manifest not found"
        }
        elseif (Ensure-CanonicalRepo -Manifest $manifest) {
            $null = Restore-RepoFilesFromManifest -Manifest $manifest
            Add-SummaryItem -Step "Repo" -Status "OK" -Message "Canonical repo ready at $CanonicalRepoPath"
            Set-StepState -StepId $stepId -Status "done" -Message "Canonical repo ready"
        }
        else {
            Write-Log "Canonical repo unavailable; continuing with C:\Setup assets" -Level WARNING
            Add-SummaryItem -Step "Repo" -Status "WARN" -Message "Clone failed; continuing with C:\Setup"
            Set-StepState -StepId $stepId -Status "failed" -Message "Clone failed; using C:\Setup"
        }
    }

    $stepId = "sophia"
    if ($OptionalAppsOnly) {
        Write-Log "Step 3: Skipping Sophia (optional apps only mode)" -Level INFO
    }
    elseif (-not (Should-RunStep -StepId $stepId)) {
        Write-Log "Step 3: Skipping Sophia (already completed)" -Level INFO
        Add-SummaryItem -Step "Sophia" -Status "OK" -Message "Skipped (already completed)"
    }
    elseif ($DryRun) {
        Write-Log "Step 3: Dry run - skipping Sophia Script" -Level WARNING
        Add-SummaryItem -Step "Sophia" -Status "WARN" -Message "Dry run: Sophia Script skipped"
        Set-StepState -StepId $stepId -Status "pending" -Message "Dry run: Sophia Script skipped"
    }
    elseif (-not (Test-Path $SophiaPreset)) {
        Write-Log "WARNING: Sophia preset not found at $SophiaPreset - skipping OS tweaks" -Level WARNING
        Add-FailedItem -Category "Sophia Script" -Item "Sophia-Preset.ps1" -Reason "Preset file not found at $SophiaPreset"
        Add-SummaryItem -Step "Sophia" -Status "WARN" -Message "Sophia preset not found - see Failed Installs.txt"
        Set-StepState -StepId $stepId -Status "failed" -Message "Sophia preset not found"
    }
    else {
        $presetHash = (Get-FileHash -Path $SophiaPreset -Algorithm SHA256).Hash
        $markerHash = $null
        if (Test-Path $SophiaMarker) {
            $markerHash = (Get-Content -Path $SophiaMarker -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
        }

        if ($markerHash -and $markerHash -eq $presetHash) {
            Write-Log "Sophia Script already applied; skipping" -Level INFO
            Add-SummaryItem -Step "Sophia" -Status "OK" -Message "Already applied"
            Set-StepState -StepId $stepId -Status "done" -Message "Already applied"
        }
        else {
            $sophiaFramework = Get-SophiaScript

            if (-not $sophiaFramework) {
                Write-Log "Sophia Script framework unavailable; skipping OS tweaks" -Level WARNING
                Add-FailedItem -Category "Sophia Script" -Item "Sophia.ps1 framework" -Reason "Download or extraction failed"
                Add-SummaryItem -Step "Sophia" -Status "WARN" -Message "Framework unavailable - see Failed Installs.txt"
                Set-StepState -StepId $stepId -Status "failed" -Message "Sophia framework unavailable"
            }
            else {
                try {
                    # Copy preset into the Sophia directory and run it through the framework
                    $presetInSophiaDir = Join-Path $SophiaDir (Split-Path $SophiaPreset -Leaf)
                    Copy-Item -Path $SophiaPreset -Destination $presetInSophiaDir -Force

                    Write-Log "Running Sophia Script v$SophiaVersion with preset..." -Level INFO
                    $global:LASTEXITCODE = $null

                    & powershell.exe -ExecutionPolicy Bypass -File $sophiaFramework -Preset $presetInSophiaDir

                    $exitCode = $global:LASTEXITCODE

                    if ($? -and ($null -eq $exitCode -or $exitCode -eq 0)) {
                        Write-Log "Sophia Script execution completed" -Level SUCCESS
                        Set-Content -Path $SophiaMarker -Value $presetHash -Force
                        Add-SummaryItem -Step "Sophia" -Status "OK" -Message "Sophia preset applied"
                        Set-StepState -StepId $stepId -Status "done" -Message "Sophia preset applied"
                    }
                    else {
                        Write-Log "Sophia Script completed with exit code: $exitCode" -Level WARNING
                        Add-FailedItem -Category "Sophia Script" -Item "Sophia-Preset.ps1" -Reason "Exited with code $exitCode"
                        Add-SummaryItem -Step "Sophia" -Status "WARN" -Message "Sophia completed with warnings (exit $exitCode) - see Failed Installs.txt"
                        Set-StepState -StepId $stepId -Status "failed" -Message "Sophia exit code $exitCode"
                    }
                }
                catch {
                    Write-Log "ERROR during Sophia Script execution: $($_.Exception.Message)" -Level ERROR
                    Add-FailedItem -Category "Sophia Script" -Item "Sophia-Preset.ps1" -Reason $_.Exception.Message
                    Add-SummaryItem -Step "Sophia" -Status "FAIL" -Message "Sophia execution failed - see Failed Installs.txt"
                    Set-StepState -StepId $stepId -Status "failed" -Message "Sophia execution failed"
                }
            }
        }
    }

    $stepId = "registry"
    if ($OptionalAppsOnly) {
        Write-Log "Step 4: Skipping registry fallback (optional apps only mode)" -Level INFO
    }
    elseif (-not (Should-RunStep -StepId $stepId)) {
        Write-Log "Step 4: Skipping registry fallback (already completed)" -Level INFO
        Add-SummaryItem -Step "Registry" -Status "OK" -Message "Skipped (already completed)"
    }
    elseif ($DryRun) {
        Write-Log "Step 4: Dry run - skipping registry fallback" -Level WARNING
        Add-SummaryItem -Step "Registry" -Status "WARN" -Message "Dry run: registry changes skipped"
        Set-StepState -StepId $stepId -Status "pending" -Message "Dry run: registry changes skipped"
    }
    elseif (-not (Test-Path $RegistryConfig)) {
        Write-Log "WARNING: registry.json not found at $RegistryConfig" -Level WARNING
        Add-SummaryItem -Step "Registry" -Status "WARN" -Message "registry.json not found"
        Set-StepState -StepId $stepId -Status "done" -Message "registry.json not found"
    }
    elseif (-not (Test-Path $RegistryScript)) {
        Write-Log "ERROR: Registry apply script not found at $RegistryScript" -Level ERROR
        Add-SummaryItem -Step "Registry" -Status "FAIL" -Message "Registry script missing"
        Set-StepState -StepId $stepId -Status "failed" -Message "Registry script missing"
    }
    else {
        try {
            $registryResult = & $RegistryScript -ConfigPath $RegistryConfig
            if ($registryResult.Failed -and $registryResult.Failed -gt 0) {
                Write-Log "Registry fallback applied with $($registryResult.Failed) error(s)" -Level ERROR
                Add-FailedItem -Category "Registry" -Item "config\registry.json" -Reason "$($registryResult.Failed) entries failed to apply"
                Add-SummaryItem -Step "Registry" -Status "FAIL" -Message "$($registryResult.Failed) entries failed - see Failed Installs.txt"
                Set-StepState -StepId $stepId -Status "failed" -Message "Registry fallback errors"
            }
            else {
                Write-Log "Registry fallback applied successfully" -Level SUCCESS
                Add-SummaryItem -Step "Registry" -Status "OK" -Message "Registry fallback applied"
                Set-StepState -StepId $stepId -Status "done" -Message "Registry fallback applied"
            }
        }
        catch {
            Write-Log "ERROR during registry fallback: $($_.Exception.Message)" -Level ERROR
            Add-FailedItem -Category "Registry" -Item "config\registry.json" -Reason $_.Exception.Message
            Add-SummaryItem -Step "Registry" -Status "FAIL" -Message "Registry fallback failed - see Failed Installs.txt"
            Set-StepState -StepId $stepId -Status "failed" -Message "Registry fallback failed"
        }
    }

    $desktopPath = [Environment]::GetFolderPath("Desktop")

    $stepId = "shortcut"
    if ($OptionalAppsOnly) {
        Write-Log "Step 5: Skipping desktop shortcut (optional apps only mode)" -Level INFO
    }
    elseif (-not (Should-RunStep -StepId $stepId)) {
        Write-Log "Step 5: Skipping desktop shortcut (already completed)" -Level INFO
        Add-SummaryItem -Step "Shortcut" -Status "OK" -Message "Skipped (already completed)"
    }
    elseif ($DryRun) {
        Write-Log "Step 5: Dry run - skipping desktop shortcut" -Level WARNING
        Add-SummaryItem -Step "Shortcut" -Status "WARN" -Message "Dry run: shortcut not created"
        Set-StepState -StepId $stepId -Status "pending" -Message "Dry run: shortcut not created"
    }
    else {
        try {
            $shortcutPath = Join-Path $desktopPath "Run Windows Setup.lnk"
            $bootstrapTarget = Get-RunBootstrapTarget
            New-DesktopShortcut -ShortcutPath $shortcutPath -TargetPath "powershell.exe" -Arguments "-ExecutionPolicy Bypass -File `"$bootstrapTarget`"" -WorkingDirectory (Split-Path -Path $bootstrapTarget -Parent) -Description "Re-run declarative Windows setup"

            Add-SummaryItem -Step "Shortcut" -Status "OK" -Message "Run Windows Setup.lnk created"
            Set-StepState -StepId $stepId -Status "done" -Message "Shortcut created"
        }
        catch {
            Write-Log "WARNING: Failed to create desktop shortcut: $($_.Exception.Message)" -Level WARNING
            Add-SummaryItem -Step "Shortcut" -Status "WARN" -Message "Failed to create shortcut"
            Set-StepState -StepId $stepId -Status "failed" -Message "Failed to create shortcut"
        }
    }

    $stepId = "restoreShortcut"
    if ($OptionalAppsOnly) {
        Write-Log "Step 6: Skipping restore shortcut (optional apps only mode)" -Level INFO
    }
    elseif (-not (Should-RunStep -StepId $stepId)) {
        Write-Log "Step 6: Skipping restore shortcut (already completed)" -Level INFO
        Add-SummaryItem -Step "Restore" -Status "OK" -Message "Skipped (already completed)"
    }
    elseif ($DryRun) {
        Write-Log "Step 6: Dry run - skipping restore shortcut" -Level WARNING
        Add-SummaryItem -Step "Restore" -Status "WARN" -Message "Dry run: restore shortcut not created"
        Set-StepState -StepId $stepId -Status "pending" -Message "Dry run: restore shortcut not created"
    }
    elseif (-not (Test-Path $RestoreScript)) {
        Write-Log "WARNING: Restore script not found at $RestoreScript" -Level WARNING
        Add-SummaryItem -Step "Restore" -Status "WARN" -Message "Restore script not found"
        Set-StepState -StepId $stepId -Status "failed" -Message "Restore script not found"
    }
    else {
        try {
            $restoreShortcutPath = Join-Path $desktopPath "Restore My Files.lnk"
            New-DesktopShortcut -ShortcutPath $restoreShortcutPath -TargetPath "powershell.exe" -Arguments "-ExecutionPolicy Bypass -File `"$RestoreScript`"" -WorkingDirectory $SetupPath -Description "Restore backed up files after Windows reinstall"

            Add-SummaryItem -Step "Restore" -Status "OK" -Message "Restore My Files.lnk created"
            Set-StepState -StepId $stepId -Status "done" -Message "Restore shortcut created"
        }
        catch {
            Write-Log "WARNING: Failed to create restore shortcut: $($_.Exception.Message)" -Level WARNING
            Add-SummaryItem -Step "Restore" -Status "WARN" -Message "Failed to create restore shortcut"
            Set-StepState -StepId $stepId -Status "failed" -Message "Failed to create restore shortcut"
        }
    }

    $stepId = "optionalShortcut"
    if ($OptionalAppsOnly) {
        Write-Log "Step 7: Skipping optional apps shortcut (optional apps only mode)" -Level INFO
    }
    elseif (-not (Should-RunStep -StepId $stepId)) {
        Write-Log "Step 7: Skipping optional apps shortcut (already completed)" -Level INFO
        Add-SummaryItem -Step "Optional Apps Shortcut" -Status "OK" -Message "Skipped (already completed)"
    }
    elseif ($DryRun) {
        Write-Log "Step 7: Dry run - skipping optional apps shortcut" -Level WARNING
        Add-SummaryItem -Step "Optional Apps Shortcut" -Status "WARN" -Message "Dry run: optional shortcut not created"
        Set-StepState -StepId $stepId -Status "pending" -Message "Dry run: optional shortcut not created"
    }
    elseif (-not (Test-Path $OptionalAppsJson)) {
        Write-Log "optional-apps.json not found at $OptionalAppsJson - skipping optional apps shortcut" -Level INFO
        Add-SummaryItem -Step "Optional Apps Shortcut" -Status "WARN" -Message "optional-apps.json not found"
        Set-StepState -StepId $stepId -Status "done" -Message "optional-apps.json not found"
    }
    else {
        try {
            $optionalShortcutPath = Join-Path $desktopPath "Install Optional Apps.lnk"
            $bootstrapTarget = Get-RunBootstrapTarget
            New-DesktopShortcut -ShortcutPath $optionalShortcutPath -TargetPath "powershell.exe" -Arguments "-ExecutionPolicy Bypass -File `"$bootstrapTarget`" -OptionalAppsOnly" -WorkingDirectory (Split-Path -Path $bootstrapTarget -Parent) -Description "Install optional declarative Windows apps later"

            Add-SummaryItem -Step "Optional Apps Shortcut" -Status "OK" -Message "Install Optional Apps.lnk created"
            Set-StepState -StepId $stepId -Status "done" -Message "Optional apps shortcut created"
        }
        catch {
            Write-Log "WARNING: Failed to create optional apps shortcut: $($_.Exception.Message)" -Level WARNING
            Add-SummaryItem -Step "Optional Apps Shortcut" -Status "WARN" -Message "Failed to create optional shortcut"
            Set-StepState -StepId $stepId -Status "failed" -Message "Failed to create optional shortcut"
        }
    }

    $stepId = "optionalWinget"
    if (-not (Should-RunStep -StepId $stepId) -and -not $OptionalAppsOnly) {
        Write-Log "Step 8: Skipping optional apps (already completed)" -Level INFO
        Add-SummaryItem -Step "Optional Apps" -Status "OK" -Message "Skipped (already completed)"
    }
    elseif ($DryRun) {
        Write-Log "Step 8: Dry run - skipping optional apps import" -Level WARNING
        Add-SummaryItem -Step "Optional Apps" -Status "WARN" -Message "Dry run: optional apps skipped"
        Set-StepState -StepId $stepId -Status "pending" -Message "Dry run: optional apps skipped"
    }
    elseif (-not (Test-Path $OptionalAppsJson)) {
        if ($OptionalAppsOnly) {
            $null = Invoke-WingetManifestInstall -ManifestPath $OptionalAppsJson -StepId $stepId -SummaryStep "Optional Apps" -MarkerPath $OptionalWingetMarker -ManifestLabel "optional-apps.json" -MissingManifestMessage "optional-apps.json not found"
        }
    }
    else {
        $installOptionalApps = $OptionalAppsOnly

        if (-not $installOptionalApps) {
            $optionalAppsResponse = Read-Host "Install optional apps now? (Y/N)"
            if ($optionalAppsResponse -match '^(y|yes)$') {
                $installOptionalApps = $true
            }
            else {
                Write-Log "Optional apps skipped by user" -Level INFO
                Add-SummaryItem -Step "Optional Apps" -Status "WARN" -Message "Skipped by user - use Install Optional Apps.lnk later"
                Set-StepState -StepId $stepId -Status "pending" -Message "Skipped by user"
            }
        }

        if ($installOptionalApps) {
            $null = Invoke-WingetManifestInstall -ManifestPath $OptionalAppsJson -StepId $stepId -SummaryStep "Optional Apps" -MarkerPath $OptionalWingetMarker -ManifestLabel "optional-apps.json" -MissingManifestMessage "optional-apps.json not found"
        }
    }

    $stepId = "summary"
    if (-not (Should-RunStep -StepId $stepId)) {
        Write-Log "Step 9: Skipping summary report (already completed)" -Level INFO
    }
    elseif ($DryRun) {
        Write-Log "Step 9: Dry run - skipping summary report" -Level WARNING
        Set-StepState -StepId $stepId -Status "pending" -Message "Dry run: summary skipped"
    }
    else {
        try {
            $failedReportPath = Write-FailedInstallsReport -DesktopPath $desktopPath
            if ($FailedItems.Count -gt 0) {
                Write-Log "Failed installs report written to $failedReportPath ($($FailedItems.Count) item(s))" -Level WARNING
            }
            else {
                Write-Log "No failed installs - report written to $failedReportPath" -Level SUCCESS
            }

            $summaryPath = Write-SummaryReport -DesktopPath $desktopPath
            Write-Log "Summary report written to $summaryPath" -Level SUCCESS
            Set-StepState -StepId $stepId -Status "done" -Message "Summary report written"
        }
        catch {
            Write-Log "WARNING: Failed to write summary report: $($_.Exception.Message)" -Level WARNING
            Set-StepState -StepId $stepId -Status "failed" -Message "Summary report failed"
        }
    }

    Write-Log "========================================" -Level INFO
    Write-Log "Windows Setup Bootstrap - Completed" -Level SUCCESS
    Write-Log "========================================" -Level INFO
    Write-Log "Log file saved to: $LogFile" -Level INFO

    if ($PromptRestart) {
        $restartResponse = Read-Host "Restart now? (Y/N)"
        if ($restartResponse -match '^(y|yes)$') {
            Write-Log "Restarting system..." -Level WARNING
            Restart-Computer -Force
        }
        else {
            Write-Log "Restart skipped by user" -Level INFO
        }
    }
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}
