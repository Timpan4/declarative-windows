#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ManifestPath,

    [string]$DestinationProfileRoot,

    [ValidateSet("Merge", "SkipExisting", "Overwrite")]
    [string]$Mode = "Merge",

    [string[]]$IncludeTags,

    [switch]$Force,

    [string]$WorkingDirectory
)

$ErrorActionPreference = "Stop"

if ($WorkingDirectory) {
    Set-Location -LiteralPath $WorkingDirectory -ErrorAction Stop
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-Success {
    param([string]$Message)
    Write-Host "[ OK ] $Message" -ForegroundColor Green
}

$actualBackupRoot = $null

function Copy-Tree {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$RobocopyMode
    )

    $destinationParent = Split-Path -Path $Destination -Parent
    if ($destinationParent -and -not (Test-Path $destinationParent)) {
        New-Item -Path $destinationParent -ItemType Directory -Force | Out-Null
    }

    if (-not $PSCmdlet.ShouldProcess($Destination, "Restore files from $Source")) {
        return $true
    }

    if (-not (Test-Path $Destination)) {
        New-Item -Path $Destination -ItemType Directory -Force | Out-Null
    }

    $robocopyArgs = @(
        $Source,
        $Destination,
        "/E",
        "/R:1",
        "/W:1",
        "/XJ",
        "/NFL",
        "/NDL",
        "/NJH",
        "/NJS",
        "/NP"
    )

    switch ($RobocopyMode) {
        "SkipExisting" { $robocopyArgs += "/XC"; $robocopyArgs += "/XN"; $robocopyArgs += "/XO" }
        "Overwrite" { }
        default { $robocopyArgs += "/XO" }
    }

    $null = & robocopy @robocopyArgs
    return $LASTEXITCODE -lt 8
}

$ModuleRoot = Join-Path $PSScriptRoot "modules"
$BackupManifestModule = Join-Path $ModuleRoot "BackupManifest.ps1"
if (Test-Path $BackupManifestModule) {
    . $BackupManifestModule
}

if (-not $ManifestPath) {
    $ManifestPath = Find-BackupManifest
}

if (-not $ManifestPath) {
    throw "Backup manifest not found automatically. Pass -ManifestPath explicitly."
}

$resolvedManifestPath = (Resolve-Path $ManifestPath).Path
$manifest = Get-Content -Path $resolvedManifestPath -Raw | ConvertFrom-Json
Assert-BackupManifest $manifest
$actualBackupRoot = Split-Path -Parent $resolvedManifestPath
$manifestBackupRoot = Get-BackupManifestRoot -Manifest $manifest
Assert-BackupHashes -Manifest $manifest -BackupRoot $actualBackupRoot

if (-not $DestinationProfileRoot) {
    $DestinationProfileRoot = $env:USERPROFILE
}

$restoreReport = New-Object System.Collections.Generic.List[object]

# Resolve and validate the complete selected plan before the first filesystem write.
$originalOsDrive = $manifest.machine.osDrive
$restoreTargetMap = Get-RestoreTargetMap -Manifest $manifest
$repoTargetRoot = Get-CanonicalBackupPath (Resolve-RestoreTargetPath -Path $manifest.repo.restorePath -ProfileRoot $DestinationProfileRoot -OriginalOsDrive $originalOsDrive -RestoreTargetMap $restoreTargetMap -OriginalProfileRoot $manifest.machine.userProfile)
$repoPlan = @(
    foreach ($repoFile in $manifest.repoFiles) {
        $destination = Resolve-ContainedBackupPath -Path $repoFile.relativePath -Root $repoTargetRoot
        $repoFileSource = Resolve-BackupSourcePath -Path $repoFile.backupPath -ManifestBackupRoot $manifestBackupRoot -ActualBackupRoot $actualBackupRoot
        if (-not (Test-Path -LiteralPath $repoFileSource -PathType Leaf)) { throw "Backup file missing: $repoFileSource" }
        [pscustomobject]@{ relativePath = $repoFile.relativePath; source = $repoFileSource; destination = $destination }
    }
)
$contentPlan = @(
    foreach ($rule in $manifest.rules) {
        if (-not $rule.success -or ($IncludeTags -and @($rule.tags | Where-Object { $IncludeTags -contains $_ }).Count -eq 0)) { continue }
        $sourcePath = Resolve-BackupSourcePath -Path $rule.backupPath -ManifestBackupRoot $manifestBackupRoot -ActualBackupRoot $actualBackupRoot
        $targetPath = Get-CanonicalBackupPath (Resolve-RestoreTargetPath -Path $rule.restorePath -ProfileRoot $DestinationProfileRoot -OriginalOsDrive $originalOsDrive -RestoreTargetMap $restoreTargetMap -OriginalProfileRoot $manifest.machine.userProfile)
        Assert-NoBackupReparsePoint $targetPath
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) { throw "Backup content missing: $sourcePath" }
        [pscustomobject]@{ source = $sourcePath; destination = $targetPath }
    }
)

# Check if backup.json is in the repo files list
$backupJsonEntry = $manifest.repoFiles | Where-Object { $_.relativePath -eq "config\backup.json" }
if ($backupJsonEntry) {
    $restoreBackupJson = $false
    if ($PSCmdlet.ShouldProcess("config\backup.json", "Prompt for restore")) {
        $response = Read-Host "Restore config\backup.json? This file contains paths from your OLD machine. It is recommended to customize from backup.template.json on the new machine instead. [Y] Restore, [N] Skip (default: N)"
        $restoreBackupJson = $response -eq 'Y'
    }

    if (-not $restoreBackupJson) {
        Write-Host "Skipping config\backup.json restore. Customize from backup.template.json on the new machine"
        # Remove from list so it's not processed in the loop below
        $repoPlan = @($repoPlan | Where-Object { $_.relativePath -ne "config\backup.json" })
    }
}

foreach ($repoFile in $repoPlan) {
    $destination = $repoFile.destination
    try {
        $destinationParent = Split-Path -Path $destination -Parent

        if ($destinationParent -and -not (Test-Path $destinationParent)) {
            if ($PSCmdlet.ShouldProcess($destinationParent, "Create repo restore directory")) {
                New-Item -Path $destinationParent -ItemType Directory -Force | Out-Null
            }
        }

        $repoFileSource = $repoFile.source

        if ((Test-Path $destination) -and $Mode -eq "SkipExisting") {
            $restoreReport.Add([pscustomobject]@{ type = "repoFile"; path = $destination; status = "skipped" })
            continue
        }

        if ($PSCmdlet.ShouldProcess($destination, "Restore repo file")) {
            Copy-Item -LiteralPath $repoFileSource -Destination $destination -Force:($Mode -eq "Overwrite")
        }

        $restoreReport.Add([pscustomobject]@{ type = "repoFile"; path = $destination; status = "restored" })
    }
    catch {
        $restoreReport.Add([pscustomobject]@{ type = "repoFile"; path = $destination; status = "failed"; message = $_.Exception.Message })
    }
}

foreach ($rule in $contentPlan) {
    $sourcePath = $rule.source
    $targetPath = $rule.destination
    try {
        $success = Copy-Tree -Source $sourcePath -Destination $targetPath -RobocopyMode $Mode
        $message = if ($success) { $null } else { "robocopy exit code $LASTEXITCODE" }
    }
    catch {
        $success = $false
        $message = $_.Exception.Message
    }
    $restoreReport.Add([pscustomobject]@{
        type = "content"
        path = $targetPath
        status = if ($success) { "restored" } else { "failed" }
        message = $message
    })
}

$reportPath = Join-Path (Split-Path -Path $resolvedManifestPath -Parent) "restore-report.json"
ConvertTo-Json -InputObject $restoreReport.ToArray() -Depth 5 | Set-Content -Path $reportPath -Force
if (@($restoreReport | Where-Object { $_.status -eq 'failed' }).Count -gt 0) {
    throw "Restore completed with failures. Review $reportPath before retrying."
}
Write-Success "Restore report written to $reportPath"
