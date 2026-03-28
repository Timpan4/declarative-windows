#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)]
    [string]$DestinationRoot,

    [string]$ConfigPath,

    [string]$BackupName,

    [string]$ManifestPath,

    [switch]$VerifyHashes,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$ScriptRoot = $PSScriptRoot
$DefaultConfigPath = Join-Path $ScriptRoot "config\backup.json"
$TemplateConfigPath = Join-Path $ScriptRoot "config\backup.template.json"
$ManifestFileName = "backup-manifest.json"
$BackupContainerName = "declarative-windows-backup"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-Success {
    param([string]$Message)
    Write-Host "[ OK ] $Message" -ForegroundColor Green
}

function Write-BackupProgress {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$Current,
        [int]$Total
    )

    $percentComplete = if ($Total -gt 0) {
        [int][Math]::Floor(($Current / $Total) * 100)
    }
    else {
        100
    }

    Write-Progress -Activity $Activity -Status $Status -PercentComplete $percentComplete
}

function Resolve-EffectiveConfigPath {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        return (Resolve-Path $RequestedPath).Path
    }

    if (Test-Path $DefaultConfigPath) {
        return (Resolve-Path $DefaultConfigPath).Path
    }

    return (Resolve-Path $TemplateConfigPath).Path
}

function Resolve-CanonicalRepoPath {
    param([object]$Config)

    $configuredPath = $Config.restoreTargets.repoPath
    if (-not $configuredPath) {
        $configuredPath = "%USERPROFILE%\\Documents\\declarative-windows"
    }

    return [Environment]::ExpandEnvironmentVariables($configuredPath)
}

function Test-IsSystemDrivePath {
    param([string]$Path)

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $systemRoot = [System.IO.Path]::GetPathRoot($env:SystemDrive)
    $pathRoot = [System.IO.Path]::GetPathRoot($resolvedPath)
    return $pathRoot -eq $systemRoot
}

function Get-RepoRemoteUrl {
    param([string]$RepositoryPath)

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        return $null
    }

    try {
        $remoteUrl = & $gitCommand.Source -C $RepositoryPath remote get-url origin 2>$null
        if ($LASTEXITCODE -eq 0 -and $remoteUrl) {
            return ($remoteUrl | Select-Object -First 1).Trim()
        }
    }
    catch {
        return $null
    }

    return $null
}

function Resolve-KnownFolderPath {
    param([string]$Name)

    switch ($Name) {
        "Desktop" { return [Environment]::GetFolderPath("Desktop") }
        "Documents" { return [Environment]::GetFolderPath("MyDocuments") }
        "Pictures" { return [Environment]::GetFolderPath("MyPictures") }
        "Downloads" { return Join-Path $env:USERPROFILE "Downloads" }
        "Videos" { return [Environment]::GetFolderPath("MyVideos") }
        "Music" { return [Environment]::GetFolderPath("MyMusic") }
        default { throw "Unsupported known folder: $Name" }
    }
}

function Normalize-RuleId {
    param([string]$Value)

    $normalized = $Value -replace '[^A-Za-z0-9_-]', '-'
    return $normalized.Trim('-').ToLowerInvariant()
}

function Get-BackupRules {
    param([object]$Config)

    $rules = New-Object System.Collections.Generic.List[object]

    foreach ($entry in $Config.knownFolders) {
        if (-not $entry.enabled) {
            continue
        }

        $folderPath = Resolve-KnownFolderPath -Name $entry.name
        $rules.Add([pscustomobject]@{
            id = "known-$((Normalize-RuleId -Value $entry.name))"
            source = $folderPath
            kind = "knownFolder"
            label = $entry.name
            required = [bool]$entry.required
            tags = @($entry.tags)
            restorePath = $folderPath
        })
    }

    foreach ($entry in $Config.extraPaths) {
        if (-not $entry.enabled) {
            continue
        }

        $expandedPath = [Environment]::ExpandEnvironmentVariables($entry.path)
        $label = if ($entry.label) { $entry.label } else { $expandedPath }
        $rules.Add([pscustomobject]@{
            id = "extra-$((Normalize-RuleId -Value $label))"
            source = $expandedPath
            kind = "extraPath"
            label = $label
            required = [bool]$entry.required
            tags = @($entry.tags)
            restorePath = $expandedPath
        })
    }

    return $rules
}

function Assert-DestinationRoot {
    param([string]$Path)

    if ((Test-IsSystemDrivePath -Path $Path) -and -not $Force) {
        throw "DestinationRoot must not be on the system drive unless -Force is specified."
    }

    if (-not (Test-Path $Path)) {
        if ($PSCmdlet.ShouldProcess($Path, "Create backup destination root")) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }
    }
}

function Copy-DirectoryWithRobocopy {
    param(
        [string]$Source,
        [string]$Destination,
        [string[]]$ExcludePatterns
    )

    if (-not (Test-Path $Source)) {
        return [pscustomobject]@{
            Success = $false
            Message = "Source path missing"
        }
    }

    if (-not $PSCmdlet.ShouldProcess($Destination, "Copy backup content from $Source")) {
        return [pscustomobject]@{
            Success = $true
            Message = "WhatIf"
        }
    }

    New-Item -Path $Destination -ItemType Directory -Force | Out-Null

    $robocopyArgs = @(
        $Source,
        $Destination,
        "/E",
        "/R:1",
        "/W:1",
        "/XJ",
        "/NDL",
        "/NJH",
        "/NJS"
    )

    foreach ($pattern in $ExcludePatterns) {
        $leaf = Split-Path -Path $pattern -Leaf
        if ($leaf -and $leaf -notmatch '[\*\?]') {
            $robocopyArgs += @("/XF", $leaf)
        }
    }

    & robocopy @robocopyArgs 2>&1 | ForEach-Object {
        $line = $_.ToString().Trim()
        if ($line) {
            Write-Host "    $line"
        }
    }
    $exitCode = $LASTEXITCODE
    $success = $exitCode -lt 8

    return [pscustomobject]@{
        Success = $success
        Message = "robocopy exit code $exitCode"
    }
}

function Get-RepoFilesToBackup {
    param([string]$RepositoryPath)

    $files = @(
        "apps.json",
        "config\backup.json"
    )

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($relativePath in $files) {
        $fullPath = Join-Path $RepositoryPath $relativePath
        if (Test-Path $fullPath) {
            $results.Add([pscustomobject]@{
                relativePath = $relativePath
                source = $fullPath
            })
        }
    }

    return $results
}

function Export-WingetInventory {
    param([string]$OutputPath)

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        return $false
    }

    if (-not $PSCmdlet.ShouldProcess($OutputPath, "Export WinGet inventory")) {
        return $true
    }

    & $winget.Source export -o $OutputPath --source winget | Out-Null
    return $LASTEXITCODE -eq 0
}

$effectiveConfigPath = Resolve-EffectiveConfigPath -RequestedPath $ConfigPath
$config = Get-Content -Path $effectiveConfigPath -Raw | ConvertFrom-Json

if (-not $BackupName) {
    $BackupName = Get-Date -Format "yyyyMMdd-HHmmss"
}

Assert-DestinationRoot -Path $DestinationRoot

$backupRoot = Join-Path $DestinationRoot $BackupContainerName
$sessionRoot = Join-Path $backupRoot $BackupName
$filesRoot = Join-Path $sessionRoot "files"
$repoFilesRoot = Join-Path $sessionRoot "repo-files"
$exportsRoot = Join-Path $sessionRoot "exports"
$reportsRoot = Join-Path $sessionRoot "reports"

if (-not $ManifestPath) {
    $ManifestPath = Join-Path $sessionRoot $ManifestFileName
}

$rules = Get-BackupRules -Config $config
$repoRemoteUrl = Get-RepoRemoteUrl -RepositoryPath $ScriptRoot
$repoFiles = if ($config.options.backupRepoFiles) { Get-RepoFilesToBackup -RepositoryPath $ScriptRoot } else { @() }
$canonicalRepoPath = Resolve-CanonicalRepoPath -Config $config
$excludePatterns = @($config.excludePatterns)

foreach ($path in @($sessionRoot, $filesRoot, $repoFilesRoot, $exportsRoot, $reportsRoot)) {
    if ($PSCmdlet.ShouldProcess($path, "Create backup working directory")) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }
}

$manifestRules = New-Object System.Collections.Generic.List[object]
$failedRules = New-Object System.Collections.Generic.List[object]
$totalRuleCount = @($rules).Count
$currentRuleIndex = 0

foreach ($rule in $rules) {
    $currentRuleIndex++
    Write-BackupProgress -Activity "Backing up configured folders" -Status "[$currentRuleIndex/$totalRuleCount] $($rule.label)" -Current $currentRuleIndex -Total $totalRuleCount

    if (-not (Test-Path $rule.source)) {
        if ($rule.required) {
            $failedRules.Add([pscustomobject]@{ id = $rule.id; message = "Required source path not found" })
        }
        continue
    }

    $ruleDestination = Join-Path $filesRoot $rule.id
    $copyResult = Copy-DirectoryWithRobocopy -Source $rule.source -Destination $ruleDestination -ExcludePatterns $excludePatterns

    $manifestRules.Add([pscustomobject]@{
        id = $rule.id
        label = $rule.label
        source = $rule.source
        restorePath = $rule.restorePath
        kind = $rule.kind
        tags = $rule.tags
        backupPath = $ruleDestination
        success = $copyResult.Success
        message = $copyResult.Message
    })

    if (-not $copyResult.Success) {
        $failedRules.Add([pscustomobject]@{ id = $rule.id; message = $copyResult.Message })
    }
}

Write-Progress -Activity "Backing up configured folders" -Completed

$manifestRepoFiles = New-Object System.Collections.Generic.List[object]
$totalRepoFileCount = @($repoFiles).Count
$currentRepoFileIndex = 0
foreach ($repoFile in $repoFiles) {
    $currentRepoFileIndex++
    Write-BackupProgress -Activity "Backing up personal repo files" -Status "[$currentRepoFileIndex/$totalRepoFileCount] $($repoFile.relativePath)" -Current $currentRepoFileIndex -Total $totalRepoFileCount

    $destination = Join-Path $repoFilesRoot $repoFile.relativePath
    $destinationParent = Split-Path -Path $destination -Parent
    if ($PSCmdlet.ShouldProcess($destinationParent, "Create repo file backup directory")) {
        New-Item -Path $destinationParent -ItemType Directory -Force | Out-Null
    }

    if ($PSCmdlet.ShouldProcess($destination, "Copy personal repo file")) {
        Copy-Item -Path $repoFile.source -Destination $destination -Force
    }

    $entry = [ordered]@{
        relativePath = $repoFile.relativePath
        source = $repoFile.source
        backupPath = $destination
    }

    if ($VerifyHashes -and (Test-Path $destination)) {
        $entry.sha256 = (Get-FileHash -Path $destination -Algorithm SHA256).Hash
    }

    $manifestRepoFiles.Add([pscustomobject]$entry)
}

Write-Progress -Activity "Backing up personal repo files" -Completed

$wingetExportPath = Join-Path $exportsRoot "apps.json"
Write-Progress -Activity "Exporting WinGet inventory" -Status "Running winget export" -PercentComplete 0
$wingetExported = Export-WingetInventory -OutputPath $wingetExportPath
Write-Progress -Activity "Exporting WinGet inventory" -Completed

$manifest = [ordered]@{
    manifestVersion = 1
    createdAt = (Get-Date).ToString("o")
    machine = [ordered]@{
        computerName = $env:COMPUTERNAME
        userProfile = $env:USERPROFILE
        osDrive = $env:SystemDrive
    }
    repo = [ordered]@{
        remoteUrl = $repoRemoteUrl
        name = "declarative-windows"
        restorePath = $canonicalRepoPath
    }
    backup = [ordered]@{
        destinationRoot = (Resolve-Path $DestinationRoot).Path
        backupRoot = $sessionRoot
        filesRoot = $filesRoot
        repoFilesRoot = $repoFilesRoot
        exportsRoot = $exportsRoot
        reportPath = (Join-Path $reportsRoot "backup-report.txt")
    }
    config = [ordered]@{
        sourcePath = $effectiveConfigPath
        templateFallbackUsed = $effectiveConfigPath -eq (Resolve-Path $TemplateConfigPath).Path
    }
    rules = $manifestRules
    repoFiles = $manifestRepoFiles
    exports = [ordered]@{
        wingetPath = if ($wingetExported) { $wingetExportPath } else { $null }
    }
    failures = $failedRules
}

$manifestJson = $manifest | ConvertTo-Json -Depth 8
if ($PSCmdlet.ShouldProcess($ManifestPath, "Write backup manifest")) {
    $manifestJson | Set-Content -Path $ManifestPath -Force
}

$reportLines = @(
    "Declarative Windows Backup Report",
    "Created: $($manifest.createdAt)",
    "Manifest: $ManifestPath",
    "Repo Remote: $repoRemoteUrl",
    "Backup Root: $sessionRoot",
    "",
    "Rules:"
)

foreach ($rule in $manifestRules) {
    $status = if ($rule.success) { "OK" } else { "FAILED" }
    $reportLines += "- [$status] $($rule.label) -> $($rule.backupPath)"
}

if ($manifestRepoFiles.Count -gt 0) {
    $reportLines += ""
    $reportLines += "Personal repo files:"
    foreach ($entry in $manifestRepoFiles) {
        $reportLines += "- $($entry.relativePath)"
    }
}

$reportPath = Join-Path $reportsRoot "backup-report.txt"
if ($PSCmdlet.ShouldProcess($reportPath, "Write backup report")) {
    $reportLines | Set-Content -Path $reportPath -Force
}

Write-Success "Backup manifest written to $ManifestPath"
Write-Success "Backup report written to $reportPath"

if ($failedRules.Count -gt 0) {
    throw "Backup completed with failures. Review the manifest and report before reinstalling."
}
