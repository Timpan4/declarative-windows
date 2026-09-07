#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Bootstrap script for declarative Windows configuration.

.DESCRIPTION
    Restores applications, clones the canonical repo when available, applies
    Sophia and registry configuration, and creates desktop shortcuts.

.PARAMETER ConfigRoot
    Directory containing apps.json, optional-apps.json, Sophia-Preset.ps1 and
    config\registry.json. Defaults to this script's directory, including when
    launched from the canonical repo. Missing files do not fall back individually
    to staged copies. Logs and state remain in C:\Setup. Runs using configuration
    outside C:\Setup do not restore backup configuration over the repo's edits.
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$PromptRestart,
    [switch]$OptionalAppsOnly,
    [string]$ConfigRoot = $PSScriptRoot,
    [string]$ExpectedUserSid,
    [string]$WorkingDirectory
)

if ($ExpectedUserSid -and [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedUserSid) {
    throw 'Run this setup shortcut as the user who created it. Elevating with another account would configure that account instead.'
}

if ($WorkingDirectory) {
    Set-Location -LiteralPath $WorkingDirectory -ErrorAction Stop
}

$ErrorActionPreference = "Continue"
$SetupPath = "C:\Setup"
$ConfigRoot = (Resolve-Path -LiteralPath $ConfigRoot -ErrorAction Stop).ProviderPath
if (-not (Test-Path -LiteralPath $ConfigRoot -PathType Container)) {
    throw "Configuration root must be a directory: $ConfigRoot"
}
$LogFile = Join-Path $SetupPath "install.log"
$AppsJson = Join-Path $ConfigRoot "apps.json"
$OptionalAppsJson = Join-Path $ConfigRoot "optional-apps.json"
$RestoreScript = Join-Path $SetupPath "restore-backup.ps1"
$SophiaPreset = Join-Path $ConfigRoot "Sophia-Preset.ps1"
$SophiaMarker = Join-Path $SetupPath "sophia.completed"
$WingetMarker = Join-Path $SetupPath "winget.completed"
$OptionalWingetMarker = Join-Path $SetupPath "optional-winget.completed"
$RegistryConfig = Join-Path $ConfigRoot "config\registry.json"
$RegistryScript = Join-Path $PSScriptRoot "apply-registry.ps1"
$StateFile = Join-Path $SetupPath "state.json"
$ProgressFile = Join-Path $SetupPath "progress.json"
$CanonicalRepoPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "declarative-windows"
$CanonicalBootstrap = Join-Path $CanonicalRepoPath "bootstrap.ps1"
$SophiaVersion = '7.3.0'
$SophiaDir = Join-Path $SetupPath "Sophia-Script-$SophiaVersion"
$SophiaScript = Join-Path $SophiaDir "Sophia.ps1"
$SophiaZipName = "Sophia.Script.for.Windows.11.v$SophiaVersion.zip"
$SophiaDownloadUrl = "https://github.com/farag2/Sophia-Script-for-Windows/releases/download/$SophiaVersion/$SophiaZipName"
$FailedInstallsLog = Join-Path $SetupPath "failed-installs.log"
$StepIds = @("winget", "repo", "sophia", "postInstallTweaks", "registry", "shortcut", "restoreShortcut", "optionalShortcut", "optionalWinget", "summary")
$SetupState = $null
$RunStartedAt = (Get-Date).ToString('o')
$RunStepIds = @($StepIds | Where-Object { $_ -notin @('summary', 'optionalWinget') })
if ($OptionalAppsOnly) { $RunStepIds = @('optionalWinget') }
if ($ConfigRoot.TrimEnd('\') -ne $SetupPath.TrimEnd('\')) {
    $RunStepIds = @($RunStepIds | Where-Object { $_ -ne 'repo' })
}
$SummaryItems = [System.Collections.Generic.List[object]]::new()
$FailedItems = [System.Collections.Generic.List[object]]::new()
$script:BackupManifestPath = $null
$script:BackupManifest = $null
$script:ProgressState = [ordered]@{
    phase = "Starting"
    status = "Initializing setup"
    currentPackage = ""
    packageIndex = 0
    packageTotal = 0
    mode = "admin"
    lastUpdated = $null
}

function Update-SetupProgress {
    param(
        [string]$Phase,
        [string]$Status,
        [string]$CurrentPackage,
        [Nullable[int]]$PackageIndex,
        [Nullable[int]]$PackageTotal,
        [string]$Mode,
        [switch]$ResetPackage
    )

    if ($PSBoundParameters.ContainsKey('Phase')) {
        $script:ProgressState.phase = $Phase
    }

    if ($PSBoundParameters.ContainsKey('Status')) {
        $script:ProgressState.status = $Status
    }

    if ($ResetPackage) {
        $script:ProgressState.currentPackage = ""
        $script:ProgressState.packageIndex = 0
        $script:ProgressState.packageTotal = 0
    }

    if ($PSBoundParameters.ContainsKey('CurrentPackage')) {
        $script:ProgressState.currentPackage = $CurrentPackage
    }

    if ($PSBoundParameters.ContainsKey('PackageIndex') -and $null -ne $PackageIndex) {
        $script:ProgressState.packageIndex = $PackageIndex
    }

    if ($PSBoundParameters.ContainsKey('PackageTotal') -and $null -ne $PackageTotal) {
        $script:ProgressState.packageTotal = $PackageTotal
    }

    if ($PSBoundParameters.ContainsKey('Mode')) {
        $script:ProgressState.mode = $Mode
    }

    $script:ProgressState.lastUpdated = (Get-Date).ToString('o')
    [pscustomobject]$script:ProgressState | ConvertTo-Json -Depth 4 | Set-Content -Path $ProgressFile -Encoding UTF8 -Force
}

function Update-WingetProgressFromLine {
    param(
        [string]$Line,
        [string]$Phase,
        [string]$Mode
    )

    if ($Line -match '^\((\d+)/(\d+)\)\s+Found .* \[(.+?)\]') {
        $packageIndex = [int]$Matches[1]
        $packageTotal = [int]$Matches[2]
        $packageId = $Matches[3]
        $lastPackage = $script:ProgressState.currentPackage

        Update-SetupProgress -Phase $Phase -Status ("Installing package {0} of {1}" -f $packageIndex, $packageTotal) -CurrentPackage $packageId -PackageIndex $packageIndex -PackageTotal $packageTotal -Mode $Mode

        if ($lastPackage -ne $packageId) {
            Write-Log ("Installing [{0}/{1}]: {2} ({3})" -f $packageIndex, $packageTotal, $packageId, $Mode) -Level INFO
        }

        return
    }

    if ($Line -match 'Starting package install') {
        $currentPackage = $script:ProgressState.currentPackage
        if ($currentPackage) {
            Update-SetupProgress -Phase $Phase -Status "Running installer" -CurrentPackage $currentPackage -Mode $Mode
        }
        return
    }

    if ($Line -match 'Successfully installed') {
        $currentPackage = $script:ProgressState.currentPackage
        if ($currentPackage) {
            Update-SetupProgress -Phase $Phase -Status "Installed successfully" -CurrentPackage $currentPackage -Mode $Mode
        }
    }
}

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

    if (-not $DryRun) {
        Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
    }
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

function Test-SophiaFramework {
    param([string]$Path)

    $requiredFiles = @(
        'Sophia.ps1', 'Module\Manifest\SophiaScript.psd1', 'Module\Sophia.psm1',
        'Import-TabCompletion.ps1', 'Module\Binaries\LGPO.exe', 'Module\Private\WinAPI.ps1'
    )
    foreach ($name in @('Get-Hash', 'InitialActions', 'PostActions', 'Set-KnownFolderPath', 'Set-Policy', 'Set-UserShellFolder', 'Show-Menu', 'Write-AdditionalKeys', 'Write-ExtensionKeys')) {
        $requiredFiles += "Module\Private\$name.ps1"
    }
    foreach ($culture in @('de-DE', 'en-US', 'es-ES', 'fr-FR', 'hu-HU', 'it-IT', 'pl-PL', 'pt-BR', 'ru-RU', 'tr-TR', 'uk-UA', 'zh-CN')) {
        $requiredFiles += "Module\Localizations\$culture\Sophia.psd1"
    }
    foreach ($file in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $file) -PathType Leaf)) { return $false }
    }
    $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $Path 'Module\Manifest\SophiaScript.psd1')
    return $manifest.ModuleVersion -eq $SophiaVersion
}

function Get-SophiaScript {
    $stagingPath = $null
    try {
        if (Test-Path -LiteralPath $SophiaDir) {
            if (-not (Test-SophiaFramework -Path $SophiaDir)) {
                throw "Existing Sophia directory is incomplete or has the wrong version: $SophiaDir. Move it aside before retrying."
            }
            Write-Log "Sophia Script already extracted at $SophiaDir" -Level INFO
            return $SophiaScript
        }

        $setupRoot = [IO.Path]::GetFullPath($SetupPath).TrimEnd('\')
        $stagingPath = Join-Path $setupRoot ('.sophia-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stagingPath -ErrorAction Stop | Out-Null
        $zipPath = Join-Path $stagingPath $SophiaZipName
        Write-Log "Downloading Sophia Script v$SophiaVersion..." -Level INFO
        Invoke-WebRequest -Uri $SophiaDownloadUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
        Expand-Archive -LiteralPath $zipPath -DestinationPath $stagingPath -ErrorAction Stop

        $extractedDir = Join-Path $stagingPath "Sophia_Script_for_Windows_11_v$SophiaVersion"
        if (-not (Test-SophiaFramework -Path $extractedDir)) {
            throw 'The pinned Sophia release is missing required framework files or has the wrong version.'
        }
        # Publish only the validated release, without searching or removing neighboring setup files.
        Move-Item -LiteralPath $extractedDir -Destination $SophiaDir -ErrorAction Stop
        Write-Log "Sophia Script extracted to $SophiaDir" -Level SUCCESS
        return $SophiaScript
    }
    catch {
        Write-Log "Failed to prepare Sophia Script: $($_.Exception.Message)" -Level WARNING
        return $null
    }
    finally {
        try {
            if ($stagingPath -and (Test-Path -LiteralPath $stagingPath)) {
                $resolvedStagingPath = [IO.Path]::GetFullPath($stagingPath)
                if (-not $resolvedStagingPath.StartsWith($setupRoot + '\.sophia-', [StringComparison]::OrdinalIgnoreCase)) {
                    throw 'Refusing to clean a Sophia staging path outside the setup directory.'
                }
                Remove-Item -LiteralPath $resolvedStagingPath -Recurse -Force -ErrorAction Stop
            }
        }
        catch {
            Write-Log "Sophia staging cleanup failed: $($_.Exception.Message)" -Level WARNING
        }
    }
}
function Invoke-SophiaPreset {
    param([string]$FrameworkRoot, [string]$PresetPath)

    $completionPath = [IO.Path]::GetTempFileName()
    try {
        $runner = Join-Path $PSScriptRoot 'modules\Run-SophiaPreset.ps1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -FrameworkRoot $FrameworkRoot -PresetPath $PresetPath -CompletionPath $completionPath
        $exitCode = $LASTEXITCODE
        $completion = [string](Get-Content -LiteralPath $completionPath -Raw)
        if ($exitCode -ne 0 -or $completion -notmatch '^completed\s*$') {
            throw "Sophia preset did not complete successfully (exit code $exitCode)."
        }
    }
    finally {
        Remove-Item -LiteralPath $completionPath -Force -ErrorAction SilentlyContinue
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

    $filteredSources = @(
        foreach ($source in $AppsData.Sources) {
            $filteredPackages = @($source.Packages | Where-Object {
                $PackageIds -contains $_.PackageIdentifier
            })

            if ($filteredPackages.Count -gt 0) {
                [pscustomobject]@{
                    Packages = $filteredPackages
                    SourceDetails = $source.SourceDetails
                }
            }
        }
    )

    $filteredData = [pscustomobject]@{
        '$schema' = $AppsData.'$schema'
        CreationDate = $AppsData.CreationDate
        Sources = $filteredSources
        WinGetVersion = $AppsData.WinGetVersion
    }

    $filteredData | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8 -Force
}

function Write-WingetOutput {
    param(
        [object[]]$Output,
        [string]$Prefix = "WinGet:"
    )

    foreach ($line in @($Output)) {
        $text = "$line"
        $trimmed = $text.Trim()

        if (-not $trimmed) {
            continue
        }

        if ($trimmed -match '^[\|/\\-]+$') {
            continue
        }

        if ($trimmed -match '\d+(\.\d+)?\s*(KB|MB|GB)\s*/\s*\d+(\.\d+)?\s*(KB|MB|GB)') {
            continue
        }

        Write-Log "$Prefix $text" -Level INFO
    }
}

function Test-WingetRequiresUnelevatedRetry {
    param([object[]]$Output)

    foreach ($line in @($Output)) {
        if ("$line" -match "cannot be run from an administrator context|cannot be run as administrator|administrator context is not supported") {
            return $true
        }
    }

    return $false
}

function Invoke-WingetPackageInstall {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,

        [switch]$Unelevated,

        [string]$Mode = 'admin',

        [int]$PackageIndex = 0,

        [int]$PackageTotal = 0,

        [int]$TimeoutSeconds = 14400
    )

    if (-not $Unelevated) {
        $output = New-Object System.Collections.Generic.List[string]
        $arguments = @(
            'install',
            '--id', $PackageId,
            '--exact',
            '--accept-package-agreements',
            '--accept-source-agreements'
        )

        & winget @arguments 2>&1 | ForEach-Object {
            $line = $_.ToString()
            $output.Add($line)
            Update-WingetProgressFromLine -Line $line -Phase 'Installing packages' -Mode $Mode
        }

        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = @($output)
        }
    }

    $runnerPath = Join-Path $env:TEMP "winget-install-runner-$(Get-Random).ps1"
    $resultPath = Join-Path $env:TEMP "winget-install-result-$(Get-Random).json"
    $taskName = "WingetInstallUnelevated-$(Get-Random)"

    try {
        $escapedPackageId = $PackageId.Replace("'", "''")
        $escapedResultPath = $resultPath.Replace("'", "''")
        $escapedProgressFile = $ProgressFile.Replace("'", "''")
        $runnerContent = @"
`$Host.UI.RawUI.WindowTitle = 'WinGet User-Scope Retry'

function Update-ProgressFile {
    param(
        [string]`$Phase,
        [string]`$Status,
        [string]`$CurrentPackage,
        [int]`$PackageIndex = 0,
        [int]`$PackageTotal = 0
    )

    [pscustomobject]@{
        phase = `$Phase
        status = `$Status
        currentPackage = `$CurrentPackage
        packageIndex = `$PackageIndex
        packageTotal = `$PackageTotal
        mode = 'user'
        lastUpdated = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 4 | Set-Content -Path '$escapedProgressFile' -Encoding UTF8 -Force
}

Write-Host 'Starting user-scope WinGet retry...' -ForegroundColor Cyan
Write-Host 'This window will show package installs that cannot run as administrator.' -ForegroundColor Cyan

`$output = New-Object System.Collections.Generic.List[string]
Update-ProgressFile -Phase 'Retrying user-scope packages' -Status 'Installing package $PackageIndex of $PackageTotal' -CurrentPackage '$escapedPackageId' -PackageIndex $PackageIndex -PackageTotal $PackageTotal
winget install --id '$escapedPackageId' --exact --accept-package-agreements --accept-source-agreements 2>&1 | ForEach-Object {
    `$line = `$_.ToString()
    `$output.Add(`$line)
    Write-Host `$line

    if (`$line -match 'Starting package install') {
        Update-ProgressFile -Phase 'Retrying user-scope packages' -Status 'Running installer' -CurrentPackage '$escapedPackageId' -PackageIndex $PackageIndex -PackageTotal $PackageTotal
    }
    elseif (`$line -match 'Successfully installed') {
        Update-ProgressFile -Phase 'Retrying user-scope packages' -Status 'Installed successfully' -CurrentPackage '$escapedPackageId' -PackageIndex $PackageIndex -PackageTotal $PackageTotal
    }
}

`$exitCode = `$LASTEXITCODE
Write-Host "WinGet retry finished with exit code `$exitCode" -ForegroundColor Cyan
[pscustomobject]@{
    ExitCode = `$exitCode
    Output = @(`$output)
} | ConvertTo-Json -Depth 5 | Set-Content -Path '$escapedResultPath' -Encoding UTF8 -Force
"@

        Set-Content -Path $runnerPath -Value $runnerContent -Encoding UTF8 -Force

        $taskUser = if ($env:USERDOMAIN) { "$($env:USERDOMAIN)\$($env:USERNAME)" } else { $env:USERNAME }
        $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$runnerPath`""
        $taskTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId $taskUser -LogonType Interactive -RunLevel Limited

        try {
            $null = Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Force -ErrorAction Stop
        }
        catch {
            return [pscustomobject]@{
                ExitCode = 1
                Output = @("Failed to create non-admin scheduled task", $_.Exception.Message)
            }
        }

        try {
            Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
        }
        catch {
            return [pscustomobject]@{
                ExitCode = 1
                Output = @("Failed to start non-admin scheduled task", $_.Exception.Message)
            }
        }

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            if (Test-Path $resultPath) {
                break
            }

            Start-Sleep -Seconds 2
        }

        if (-not (Test-Path $resultPath)) {
            return [pscustomobject]@{
                ExitCode = 1
                Output = @("Timed out waiting for non-admin WinGet install to finish")
            }
        }

        $result = Get-Content -Path $resultPath -Raw | ConvertFrom-Json
        $output = @()
        if ($null -ne $result.Output) {
            $output = @($result.Output)
        }

        return [pscustomobject]@{
            ExitCode = [int]$result.ExitCode
            Output = $output
        }
    }
    finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

        if (Test-Path $runnerPath) {
            Remove-Item -Path $runnerPath -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path $resultPath) {
            Remove-Item -Path $resultPath -Force -ErrorAction SilentlyContinue
        }
    }
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
    $retryAppsJson = $null

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

            $missingPackages = New-Object System.Collections.Generic.List[string]
            $installedCount = 0
            $totalPackages = $packageIds.Count

            Update-SetupProgress -Phase 'Scanning packages' -Status ("Checking package 1 of {0}" -f $totalPackages) -CurrentPackage '' -PackageIndex 0 -PackageTotal $totalPackages -Mode 'admin'

            for ($index = 0; $index -lt $totalPackages; $index++) {
                $packageId = $packageIds[$index]
                $currentNumber = $index + 1

                Update-SetupProgress -Phase 'Scanning packages' -Status ("Checking package {0} of {1}" -f $currentNumber, $totalPackages) -CurrentPackage $packageId -PackageIndex $currentNumber -PackageTotal $totalPackages -Mode 'admin'

                Write-Log "[$currentNumber/$totalPackages] Checking package: $packageId" -Level INFO

                if (Test-WingetPackageInstalled -PackageId $packageId) {
                    $installedCount++
                    Write-Log "[$currentNumber/$totalPackages] Already installed: $packageId" -Level INFO
                }
                else {
                    $missingPackages.Add($packageId)
                    Write-Log "[$currentNumber/$totalPackages] Missing: $packageId" -Level INFO
                }
            }

            Write-Log ("Package scan complete for {0}: {1} missing, {2} already installed" -f $ManifestLabel, $missingPackages.Count, $installedCount) -Level INFO

            if ($missingPackages.Count -eq 0) {
                Write-Log "All packages from $ManifestLabel are already installed" -Level SUCCESS
                Set-Content -Path $MarkerPath -Value $appsHash -Force
                Add-SummaryItem -Step $SummaryStep -Status "OK" -Message "Already up to date ($MarkerPath)"
                Set-StepState -StepId $StepId -Status "done" -Message "Already up to date"
                return $true
            }

            if ($markerHash -and $markerHash -ne $appsHash) {
                Write-Log "$ManifestLabel changed since last WinGet run" -Level INFO
            }

            Write-Log "Keep this window open. Some installers may open their own windows or ask for confirmation." -Level INFO
            Write-Log "Installing $($missingPackages.Count) missing packages from $ManifestLabel" -Level INFO
            Update-SetupProgress -Phase 'Installing packages' -Status ("Installing 1 of {0}" -f $missingPackages.Count) -CurrentPackage '' -PackageIndex 0 -PackageTotal $missingPackages.Count -Mode 'admin'

            $installedPackages = [System.Collections.Generic.List[string]]::new()
            $unverifiedPackages = [System.Collections.Generic.List[string]]::new()
            $failedPackages = [System.Collections.Generic.List[string]]::new()
            $packageNumber = 0

            foreach ($packageId in @($missingPackages)) {
                $packageNumber++
                $installed = $false
                $verified = $false
                $unverified = $false

                Write-Log ("Installing [{0}/{1}]: {2} (admin)" -f $packageNumber, $missingPackages.Count, $packageId) -Level INFO
                Update-SetupProgress -Phase 'Installing packages' -Status ("Installing package {0} of {1}" -f $packageNumber, $missingPackages.Count) -CurrentPackage $packageId -PackageIndex $packageNumber -PackageTotal $missingPackages.Count -Mode 'admin'

                $installResult = Invoke-WingetPackageInstall -PackageId $packageId -Mode 'admin' -PackageIndex $packageNumber -PackageTotal $missingPackages.Count
                Write-WingetOutput -Output $installResult.Output -Prefix "WinGet:"

                if (Test-WingetPackageInstalled -PackageId $packageId) {
                    $installed = $true
                    $verified = $true
                }
                elseif (Test-WingetRequiresUnelevatedRetry -Output $installResult.Output) {
                    Write-Log "Retrying $packageId in a non-administrator session" -Level INFO
                    Write-Log "A second PowerShell window may appear for user-scope installers. Leave it open until it finishes." -Level INFO
                    Update-SetupProgress -Phase 'Retrying user-scope packages' -Status ("Retrying package {0} of {1}" -f $packageNumber, $missingPackages.Count) -CurrentPackage $packageId -PackageIndex $packageNumber -PackageTotal $missingPackages.Count -Mode 'user'

                    $retryResult = Invoke-WingetPackageInstall -PackageId $packageId -Unelevated -Mode 'user' -PackageIndex $packageNumber -PackageTotal $missingPackages.Count
                    Write-WingetOutput -Output $retryResult.Output -Prefix "WinGet (user):"

                    if (Test-WingetPackageInstalled -PackageId $packageId) {
                        $installed = $true
                        $verified = $true
                    }
                    elseif ($retryResult.ExitCode -eq 0) {
                        $installed = $true
                        $unverified = $true
                    }
                    else {
                        Write-Log "Non-admin WinGet install exited with code $($retryResult.ExitCode) for $packageId" -Level WARNING
                    }
                }
                elseif ($installResult.ExitCode -eq 0) {
                    $installed = $true
                    $unverified = $true
                }
                else {
                    Write-Log "WinGet install exited with code $($installResult.ExitCode) for $packageId" -Level WARNING
                }

                if ($verified) {
                    $installedPackages.Add($packageId)
                    Write-Log "Successfully installed and verified $packageId" -Level SUCCESS
                    continue
                }

                if ($unverified) {
                    $unverifiedPackages.Add($packageId)
                    Add-FailedItem -Category "$SummaryStep Verification" -Item $packageId -Reason "WinGet reported success but winget list did not verify the package"
                    Write-Log "WARNING: $packageId install reported success, but winget list did not verify it" -Level WARNING
                    continue
                }

                if (-not $installed) {
                    $failedPackages.Add($packageId)
                    Write-Log "WARNING: $packageId failed to install" -Level WARNING
                }
            }

            foreach ($packageId in $failedPackages) {
                Add-FailedItem -Category $SummaryStep -Item $packageId -Reason "Not installed after per-package install from $ManifestLabel"
                Write-Log "WARNING: $packageId still not installed after WinGet install from $ManifestLabel" -Level WARNING
            }

            $failCount = @($failedPackages).Count
            $unverifiedCount = @($unverifiedPackages).Count

            if ($failCount -eq 0) {
                Update-SetupProgress -Phase 'Installing packages' -Status 'Completed' -CurrentPackage '' -PackageIndex $missingPackages.Count -PackageTotal $missingPackages.Count -Mode 'admin'
                Write-Log "WinGet install from $ManifestLabel completed successfully" -Level SUCCESS
                Set-Content -Path $MarkerPath -Value $appsHash -Force

                if ($unverifiedCount -gt 0) {
                    Add-SummaryItem -Step $SummaryStep -Status "WARN" -Message "Installed $($installedPackages.Count) package(s); $unverifiedCount verification warning(s)"
                    Set-StepState -StepId $StepId -Status "done" -Message "Installed with $unverifiedCount verification warning(s)"
                }
                else {
                    Add-SummaryItem -Step $SummaryStep -Status "OK" -Message "Installed $($installedPackages.Count) package(s)"
                    Set-StepState -StepId $StepId -Status "done" -Message "Installed $($installedPackages.Count) package(s)"
                }

                return $true
            }

            Update-SetupProgress -Phase 'Installing packages' -Status ("Completed with {0} failure(s)" -f $failCount) -CurrentPackage '' -PackageIndex ($missingPackages.Count - $failCount) -PackageTotal $missingPackages.Count -Mode 'admin'
            Write-Log "WinGet install from $ManifestLabel finished; $failCount package(s) failed" -Level WARNING

            $warningSuffix = if ($unverifiedCount -gt 0) { "; $unverifiedCount verification warning(s)" } else { "" }
            Add-SummaryItem -Step $SummaryStep -Status "WARN" -Message "$failCount package(s) failed$warningSuffix - see Failed Installs.txt"
            Set-StepState -StepId $StepId -Status "failed" -Message "$failCount package(s) failed$warningSuffix"
            return $false
        }
        catch {
            Write-Log "ERROR during WinGet install from ${ManifestLabel}: $($_.Exception.Message)" -Level ERROR
            Add-SummaryItem -Step $SummaryStep -Status "FAIL" -Message "WinGet install failed"
            Set-StepState -StepId $StepId -Status "failed" -Message "WinGet install failed"
            return $false
        }
        finally {
            # Legacy single-file cleanup (kept for safety if old path is referenced)
            if ($tempAppsJson -and (Test-Path $tempAppsJson)) {
                Remove-Item -Path $tempAppsJson -Force -ErrorAction SilentlyContinue
            }

            if ($retryAppsJson -and (Test-Path $retryAppsJson)) {
                Remove-Item -Path $retryAppsJson -Force -ErrorAction SilentlyContinue
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

    # MS-SHLLINK LinkFlags.RunAsUser requests elevation when Explorer opens the link.
    $shortcutBytes = [IO.File]::ReadAllBytes($ShortcutPath)
    $shortcutBytes[0x15] = $shortcutBytes[0x15] -bor 0x20
    [IO.File]::WriteAllBytes($ShortcutPath, $shortcutBytes)
}

function Set-RegistryValueSafe {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Type
    )

    if (-not (Test-Path $Path -ErrorAction Stop)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }

    if ($Type -eq "DWord") {
        $typedValue = [int]$Value
        $propertyType = "DWord"
    }
    else {
        $typedValue = [string]$Value
        $propertyType = "String"
    }

    if ($Name -eq "(Default)") {
        Set-Item -Path $Path -Value $typedValue -Force -ErrorAction Stop
        return
    }

    New-ItemProperty -Path $Path -Name $Name -Value $typedValue -PropertyType $propertyType -Force -ErrorAction Stop | Out-Null
}

function Remove-ProvisionedAppIfPresent {
    param([Parameter(Mandatory)][string]$DisplayName)

    try {
        $matches = Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $DisplayName }
    }
    catch {
        Add-FailedItem -Category "Post-Install Tweaks" -Item $DisplayName -Reason $_.Exception.Message
        return $false
    }
    if (-not $matches) {
        Write-Log "Provisioned app not present: $DisplayName" -Level INFO
        return $true
    }

    foreach ($match in $matches) {
        try {
            $null = Remove-AppxProvisionedPackage -Online -PackageName $match.PackageName -AllUsers -ErrorAction Stop
            Write-Log "Removed provisioned app: $DisplayName" -Level SUCCESS
        }
        catch {
            Write-Log "Failed to remove provisioned app ${DisplayName}: $($_.Exception.Message)" -Level WARNING
            Add-FailedItem -Category "Post-Install Tweaks" -Item $DisplayName -Reason "Provisioned app removal failed"
            return $false
        }
    }

    return $true
}

function Disable-OptionalFeatureIfPresent {
    param([Parameter(Mandatory)][string]$FeatureName)

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop
    }
    catch {
        Write-Log "Cannot check optional feature ${FeatureName}: $($_.Exception.Message)" -Level WARNING
        Add-FailedItem -Category "Post-Install Tweaks" -Item $FeatureName -Reason $_.Exception.Message
        return $false
    }

    if ($feature.State -in @("Disabled", "DisabledWithPayloadRemoved")) {
        Write-Log "Optional feature already disabled: $FeatureName" -Level INFO
        return $true
    }

    try {
        $null = Disable-WindowsOptionalFeature -Online -FeatureName $FeatureName -Remove -NoRestart -ErrorAction Stop
        Write-Log "Disabled optional feature: $FeatureName" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Failed to disable optional feature ${FeatureName}: $($_.Exception.Message)" -Level WARNING
        Add-FailedItem -Category "Post-Install Tweaks" -Item $FeatureName -Reason "Optional feature removal failed"
        return $false
    }
}

function Invoke-PostInstallTweaks {
    $allSucceeded = $true

    $appsToRemove = @(
        "Microsoft.BingSearch",
        "Microsoft.MicrosoftOfficeHub",
        "Microsoft.Office.OneNote",
        "Microsoft.SkypeApp",
        "Microsoft.MicrosoftSolitaireCollection",
        "MicrosoftTeams",
        "MSTeams"
    )

    foreach ($app in $appsToRemove) {
        if (-not (Remove-ProvisionedAppIfPresent -DisplayName $app)) {
            $allSucceeded = $false
        }
    }

    if (-not (Disable-OptionalFeatureIfPresent -FeatureName "Recall")) {
        $allSucceeded = $false
    }

    try {
        Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications" -Name "ConfigureChatAutoInstall" -Value 0 -Type DWord
        Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start" -Name "ConfigureStartPins" -Value '{"pinnedList":[]}' -Type String
        Set-RegistryValueSafe -Path "Registry::HKEY_USERS\.DEFAULT\Control Panel\Accessibility\StickyKeys" -Name "Flags" -Value "10" -Type String

        Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0 -Type DWord
        Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1 -Type DWord
        Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSuperHidden" -Value 1 -Type DWord
        Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0 -Type DWord
        Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 1 -Type DWord
        Set-RegistryValueSafe -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Name "(Default)" -Value "" -Type String
        Set-RegistryValueSafe -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value "0" -Type String
        Set-RegistryValueSafe -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "0" -Type String
        Set-RegistryValueSafe -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "0" -Type String
        Set-RegistryValueSafe -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name "Flags" -Value "10" -Type String

        Write-Log "Applied post-install debloat and user tweaks" -Level SUCCESS
    }
    catch {
        Write-Log "Failed to apply post-install registry tweaks: $($_.Exception.Message)" -Level WARNING
        Add-FailedItem -Category "Post-Install Tweaks" -Item "Registry Tweaks" -Reason $_.Exception.Message
        $allSucceeded = $false
    }

    try {
        Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object {
            $_.SessionId -eq (Get-Process -Id $PID).SessionId
        } | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Log "Restarted Explorer to apply user tweaks" -Level SUCCESS
    }
    catch {
        Write-Log "Failed to restart Explorer after user tweaks: $($_.Exception.Message)" -Level WARNING
    }

    return $allSucceeded
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
    param(
        [object]$Manifest,
        [string]$ManifestPath = $script:BackupManifestPath
    )

    if (-not $Manifest) {
        return $false
    }

    if (-not $Manifest.repoFiles) {
        return $true
    }

    try {
        $actualBackupRoot = Split-Path -Parent (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
        $manifestBackupRoot = Get-BackupManifestRoot -Manifest $Manifest
    }
    catch {
        Write-Log "Cannot resolve the selected backup manifest: $($_.Exception.Message)" -Level WARNING
        return $false
    }

    $restored = $true
    foreach ($repoFile in $Manifest.repoFiles) {
        try {
            $source = Resolve-BackupSourcePath -Path $repoFile.backupPath -ManifestBackupRoot $manifestBackupRoot -ActualBackupRoot $actualBackupRoot
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                throw "Backup source file is missing: $source"
            }

            $destination = Join-Path $CanonicalRepoPath $repoFile.relativePath
            $destinationParent = Split-Path -Path $destination -Parent
            if (-not (Test-Path -LiteralPath $destinationParent)) {
                New-Item -Path $destinationParent -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }

            Copy-Item -LiteralPath $source -Destination $destination -Force -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to restore repo file '$($repoFile.relativePath)': $($_.Exception.Message)" -Level WARNING
            $restored = $false
        }
    }

    return $restored
}

function Get-RunBootstrapTarget {
    if (Test-Path $CanonicalBootstrap) {
        return $CanonicalBootstrap
    }

    return (Join-Path $SetupPath "bootstrap.ps1")
}

$ModuleRoot = Join-Path $PSScriptRoot "modules"
foreach ($moduleName in @("BootstrapRun.ps1", "BackupManifest.ps1", "WinGetInstall.ps1")) {
    $modulePath = Join-Path $ModuleRoot $moduleName
    if (Test-Path $modulePath) {
        . $modulePath
    }
}

try {
    Write-Log "========================================" -Level INFO
    Write-Log "Windows Setup Bootstrap - Starting" -Level INFO
    Write-Log "========================================" -Level INFO

    Update-SetupProgress -Phase 'Starting' -Status 'Bootstrapping setup' -CurrentPackage '' -PackageIndex 0 -PackageTotal 0 -Mode 'admin'

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "This script must be run as Administrator"
    }

    Write-Log "Administrator privileges verified" -Level SUCCESS

    if (-not (Test-Path $SetupPath)) {
        throw "Setup directory not found at $SetupPath"
    }

    $SetupState = Initialize-State -StatePath $StateFile -StepIds $StepIds
    Save-State -State $SetupState -StatePath $StateFile
    Update-SetupProgress -Phase 'Preparing setup' -Status 'Administrator privileges verified' -CurrentPackage '' -PackageIndex 0 -PackageTotal 0 -Mode 'admin'

    if ($DryRun) {
        Write-Log "Dry run mode enabled; no system changes will be applied" -Level WARNING
    }

    if ($OptionalAppsOnly) {
        Write-Log "Optional apps only mode enabled; skipping core setup steps" -Level INFO
        Update-SetupProgress -Phase 'Preparing setup' -Status 'Optional apps only mode enabled' -CurrentPackage '' -PackageIndex 0 -PackageTotal 0 -Mode 'admin'
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
    elseif ($ConfigRoot.TrimEnd('\') -ne $SetupPath.TrimEnd('\')) {
        Write-Log "Step 2: Using configuration at $ConfigRoot; skipping backup configuration restore" -Level INFO
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
            Set-StepState -StepId $stepId -Status "skipped" -Message "Backup manifest not found; using C:\Setup fallback"
        }
        elseif (Ensure-CanonicalRepo -Manifest $manifest) {
            if (Restore-RepoFilesFromManifest -Manifest $manifest) {
                Add-SummaryItem -Step "Repo" -Status "OK" -Message "Canonical repo ready at $CanonicalRepoPath"
                Set-StepState -StepId $stepId -Status "done" -Message "Canonical repo ready"
            }
            else {
                Add-SummaryItem -Step "Repo" -Status "FAIL" -Message "Personal repo file restore incomplete; retry setup after correcting the backup"
                Set-StepState -StepId $stepId -Status "failed" -Message "Personal repo file restore incomplete"
            }
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
        # Markers from the former stock-preset invocation do not prove custom actions ran.
        $expectedMarker = "custom-preset-v1:${SophiaVersion}:$presetHash"
        $markerHash = $null
        if (Test-Path $SophiaMarker) {
            $markerHash = (Get-Content -Path $SophiaMarker -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
        }

        if ($markerHash -and $markerHash -eq $expectedMarker -and -not $Force) {
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
                    Write-Log "Running Sophia Script v$SophiaVersion with preset..." -Level INFO
                    Invoke-SophiaPreset -FrameworkRoot $SophiaDir -PresetPath $SophiaPreset
                    Write-Log "Sophia Script execution completed" -Level SUCCESS
                    Set-Content -Path $SophiaMarker -Value $expectedMarker -Force
                    Add-SummaryItem -Step "Sophia" -Status "OK" -Message "Sophia preset applied"
                    Set-StepState -StepId $stepId -Status "done" -Message "Sophia preset applied"
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

    $stepId = "postInstallTweaks"
    if ($OptionalAppsOnly) {
        Write-Log "Step 4: Skipping post-install tweaks (optional apps only mode)" -Level INFO
    }
    elseif (-not (Should-RunStep -StepId $stepId)) {
        Write-Log "Step 4: Skipping post-install tweaks (already completed)" -Level INFO
        Add-SummaryItem -Step "Post-Install Tweaks" -Status "OK" -Message "Skipped (already completed)"
    }
    elseif ($DryRun) {
        Write-Log "Step 4: Dry run - skipping post-install tweaks" -Level WARNING
        Add-SummaryItem -Step "Post-Install Tweaks" -Status "WARN" -Message "Dry run: post-install tweaks skipped"
        Set-StepState -StepId $stepId -Status "pending" -Message "Dry run: post-install tweaks skipped"
    }
    else {
        $tweaksSucceeded = Invoke-PostInstallTweaks
        if ($tweaksSucceeded) {
            Add-SummaryItem -Step "Post-Install Tweaks" -Status "OK" -Message "Debloat and user tweaks applied"
            Set-StepState -StepId $stepId -Status "done" -Message "Debloat and user tweaks applied"
        }
        else {
            Add-SummaryItem -Step "Post-Install Tweaks" -Status "WARN" -Message "Some tweaks failed - see Failed Installs.txt"
            Set-StepState -StepId $stepId -Status "failed" -Message "Some tweaks failed"
        }
    }

    $stepId = "registry"
    if ($OptionalAppsOnly) {
        Write-Log "Step 5: Skipping registry fallback (optional apps only mode)" -Level INFO
    }
    elseif (-not (Should-RunStep -StepId $stepId)) {
        Write-Log "Step 5: Skipping registry fallback (already completed)" -Level INFO
        Add-SummaryItem -Step "Registry" -Status "OK" -Message "Skipped (already completed)"
    }
    elseif ($DryRun) {
        Write-Log "Step 5: Dry run - skipping registry fallback" -Level WARNING
        Add-SummaryItem -Step "Registry" -Status "WARN" -Message "Dry run: registry changes skipped"
        Set-StepState -StepId $stepId -Status "pending" -Message "Dry run: registry changes skipped"
    }
    elseif (-not (Test-Path $RegistryConfig)) {
        Write-Log "WARNING: registry.json not found at $RegistryConfig" -Level WARNING
        Add-SummaryItem -Step "Registry" -Status "SKIP" -Message "registry.json not found"
        Set-StepState -StepId $stepId -Status "skipped" -Message "registry.json not found"
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
        Write-Log "Step 6: Skipping desktop shortcut (optional apps only mode)" -Level INFO
    }
    elseif (-not (Should-RunStep -StepId $stepId)) {
        Write-Log "Step 6: Skipping desktop shortcut (already completed)" -Level INFO
        Add-SummaryItem -Step "Shortcut" -Status "OK" -Message "Skipped (already completed)"
    }
    elseif ($DryRun) {
        Write-Log "Step 6: Dry run - skipping desktop shortcut" -Level WARNING
        Add-SummaryItem -Step "Shortcut" -Status "WARN" -Message "Dry run: shortcut not created"
        Set-StepState -StepId $stepId -Status "pending" -Message "Dry run: shortcut not created"
    }
    else {
        try {
            $shortcutPath = Join-Path $desktopPath "Run Windows Setup.lnk"
            $bootstrapTarget = Get-RunBootstrapTarget
            New-DesktopShortcut -ShortcutPath $shortcutPath -TargetPath "powershell.exe" -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$bootstrapTarget`" -ConfigRoot `"$ConfigRoot`" -ExpectedUserSid $([Security.Principal.WindowsIdentity]::GetCurrent().User.Value) -WorkingDirectory `"$(Split-Path -Path $bootstrapTarget -Parent)`"" -WorkingDirectory (Split-Path -Path $bootstrapTarget -Parent) -Description "Re-run declarative Windows setup"

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
        Write-Log "Step 7: Skipping restore shortcut (optional apps only mode)" -Level INFO
    }
    elseif (-not (Should-RunStep -StepId $stepId)) {
        Write-Log "Step 7: Skipping restore shortcut (already completed)" -Level INFO
        Add-SummaryItem -Step "Restore" -Status "OK" -Message "Skipped (already completed)"
    }
    elseif ($DryRun) {
        Write-Log "Step 7: Dry run - skipping restore shortcut" -Level WARNING
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
            New-DesktopShortcut -ShortcutPath $restoreShortcutPath -TargetPath "powershell.exe" -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$RestoreScript`" -DestinationProfileRoot `"$env:USERPROFILE`" -WorkingDirectory `"$SetupPath`"" -WorkingDirectory $SetupPath -Description "Restore backed up files after Windows reinstall"

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
        Write-Log "Step 8: Skipping optional apps shortcut (optional apps only mode)" -Level INFO
    }
    elseif (-not (Should-RunStep -StepId $stepId)) {
        Write-Log "Step 8: Skipping optional apps shortcut (already completed)" -Level INFO
        Add-SummaryItem -Step "Optional Apps Shortcut" -Status "OK" -Message "Skipped (already completed)"
    }
    elseif ($DryRun) {
        Write-Log "Step 8: Dry run - skipping optional apps shortcut" -Level WARNING
        Add-SummaryItem -Step "Optional Apps Shortcut" -Status "WARN" -Message "Dry run: optional shortcut not created"
        Set-StepState -StepId $stepId -Status "pending" -Message "Dry run: optional shortcut not created"
    }
    elseif (-not (Test-Path $OptionalAppsJson)) {
        Write-Log "optional-apps.json not found at $OptionalAppsJson - skipping optional apps shortcut" -Level INFO
        Add-SummaryItem -Step "Optional Apps Shortcut" -Status "SKIP" -Message "optional-apps.json not found"
        Set-StepState -StepId $stepId -Status "skipped" -Message "optional-apps.json not found"
    }
    else {
        try {
            $optionalShortcutPath = Join-Path $desktopPath "Install Optional Apps.lnk"
            $bootstrapTarget = Get-RunBootstrapTarget
            New-DesktopShortcut -ShortcutPath $optionalShortcutPath -TargetPath "powershell.exe" -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$bootstrapTarget`" -OptionalAppsOnly -ConfigRoot `"$ConfigRoot`" -ExpectedUserSid $([Security.Principal.WindowsIdentity]::GetCurrent().User.Value) -WorkingDirectory `"$(Split-Path -Path $bootstrapTarget -Parent)`"" -WorkingDirectory (Split-Path -Path $bootstrapTarget -Parent) -Description "Install optional declarative Windows apps later"

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
        Write-Log "Step 9: Skipping optional apps (already completed)" -Level INFO
        Add-SummaryItem -Step "Optional Apps" -Status "OK" -Message "Skipped (already completed)"
    }
    elseif ($DryRun) {
        Write-Log "Step 9: Dry run - skipping optional apps import" -Level WARNING
        Add-SummaryItem -Step "Optional Apps" -Status "WARN" -Message "Dry run: optional apps skipped"
        Set-StepState -StepId $stepId -Status "pending" -Message "Dry run: optional apps skipped"
    }
    elseif (-not (Test-Path $OptionalAppsJson)) {
        if ($OptionalAppsOnly) {
            Write-Log "WARNING: optional-apps.json not found at $OptionalAppsJson" -Level WARNING
            Add-SummaryItem -Step "Optional Apps" -Status "FAIL" -Message "optional-apps.json not found"
            Set-StepState -StepId $stepId -Status "failed" -Message "optional-apps.json not found"
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
            if ('optionalWinget' -notin $RunStepIds) { $RunStepIds += 'optionalWinget' }
            $null = Invoke-WingetManifestInstall -ManifestPath $OptionalAppsJson -StepId $stepId -SummaryStep "Optional Apps" -MarkerPath $OptionalWingetMarker -ManifestLabel "optional-apps.json" -MissingManifestMessage "optional-apps.json not found"
        }
    }

    $runResult = Complete-BootstrapRun -DesktopPath $desktopPath

    if ($PromptRestart -and -not $DryRun) {
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
    $null = Complete-BootstrapRun -DesktopPath ([Environment]::GetFolderPath("Desktop")) -FailureMessage $_.Exception.Message
    exit 1
}

exit $runResult.ExitCode
