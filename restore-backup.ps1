#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ManifestPath,

    [string]$DestinationProfileRoot,

    [ValidateSet("Merge", "SkipExisting", "Overwrite")]
    [string]$Mode = "Merge",

    [string[]]$IncludeTags,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-Success {
    param([string]$Message)
    Write-Host "[ OK ] $Message" -ForegroundColor Green
}

function Find-BackupManifest {
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object {
        $_.Root -ne "$($env:SystemDrive)\"
    }

    $candidates = foreach ($drive in $drives) {
        $root = $drive.Root
        $container = Join-Path $root "declarative-windows-backup"
        if (-not (Test-Path $container)) {
            continue
        }

        Get-ChildItem -Path $container -Filter "backup-manifest.json" -Recurse -File -ErrorAction SilentlyContinue
    }

    return ($candidates | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).FullName
}

function Resolve-RestoreTargetPath {
    param(
        [string]$Path,
        [string]$ProfileRoot,
        [string]$OriginalOsDrive,
        [hashtable]$RestoreTargetMap
    )

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)

    # Profile remapping takes priority
    if ($DestinationProfileRoot) {
        $currentProfile = [Environment]::ExpandEnvironmentVariables("%USERPROFILE%")
        if ($expandedPath.StartsWith($currentProfile, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relativePath = $expandedPath.Substring($currentProfile.Length).TrimStart('\')
            return Join-Path $ProfileRoot $relativePath
        }
    }

    # OS drive remapping
    if ($OriginalOsDrive -and $env:SystemDrive -ne $OriginalOsDrive) {
        $osDriveSlash = $OriginalOsDrive + "\"
        if ($expandedPath.StartsWith($osDriveSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
            $currentOsDriveSlash = $env:SystemDrive + "\"
            $relativePath = $expandedPath.Substring($OriginalOsDrive.Length)
            $newPath = $currentOsDriveSlash + $relativePath.TrimStart('\')
            # Check restore target map for remapping
            foreach ($key in $RestoreTargetMap.Keys) {
                if ($newPath -and $RestoreTargetMap[$key]) {
                    $mapKeySlash = $key + "\"
                    $mapValueSlash = $RestoreTargetMap[$key] + "\"
                    if ($newPath.StartsWith($mapKeySlash, [System.StringComparison]::OrdinalIgnoreCase)) {
                        return $newPath.Replace($mapKeySlash, $mapValueSlash)
                    }
                }
            }
            return $newPath
        }
    }

    # Check restore target map for other remappings
    if ($RestoreTargetMap -and $RestoreTargetMap.Count -gt 0) {
        foreach ($key in $RestoreTargetMap.Keys) {
            if ($key -and $RestoreTargetMap[$key]) {
                $keySlash = $key + "\"
                if ($expandedPath.StartsWith($keySlash, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $valueSlash = $RestoreTargetMap[$key] + "\"
                    return $expandedPath.Replace($keySlash, $valueSlash)
                }
            }
        }
    }

    # Warn if absolute path with drive letter cannot be remapped
    if ($expandedPath -match '^[A-Za-z]:\\') {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "Warning: Absolute path '$expandedPath' cannot be remapped - returning as-is"
        } else {
            Write-Warning "Absolute path '$expandedPath' cannot be remapped - returning as-is"
        }
    }

    return $expandedPath
}

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

if (-not $ManifestPath) {
    $ManifestPath = Find-BackupManifest
}

if (-not $ManifestPath) {
    throw "Backup manifest not found automatically. Pass -ManifestPath explicitly."
}

$resolvedManifestPath = (Resolve-Path $ManifestPath).Path
$manifestDir = Split-Path $resolvedManifestPath -Parent
$manifest = Get-Content -Path $resolvedManifestPath -Raw | ConvertFrom-Json

if (-not $DestinationProfileRoot) {
    $DestinationProfileRoot = $env:USERPROFILE
}

$restoreReport = New-Object System.Collections.Generic.List[object]

# Check if backup.json is in the repo files list
$backupJsonEntry = $manifest.repoFiles | Where-Object { $_.relativePath -eq "config\backup.json" }
if ($backupJsonEntry) {
    $restoreBackupJson = $false
    if ($PSCmdlet.ShouldProcess("config\backup.json", "Prompt for restore")) {
        $response = Read-Host "Restore config\backup.json? This file contains paths from your OLD machine. It is recommended to customize from backup.template.json on the new machine instead. [Y] Restore, [N] Skip (default: N)"
        $restoreBackupJson = $response -eq 'Y'
    }

    if (-not $restoreBackupJson) {
        Write-Host "Skipping config\backup.json restore — customize from backup.template.json on the new machine"
        # Remove from list so it's not processed in the loop below
        $manifest.repoFiles = [array]($manifest.repoFiles | Where-Object { $_.relativePath -ne "config\backup.json" })
    }
}

foreach ($repoFile in $manifest.repoFiles) {
    $repoTargetRoot = [Environment]::ExpandEnvironmentVariables($manifest.repo.restorePath)
    $destination = Join-Path $repoTargetRoot $repoFile.relativePath
    $destinationParent = Split-Path -Path $destination -Parent

    if ($destinationParent -and -not (Test-Path $destinationParent)) {
        if ($PSCmdlet.ShouldProcess($destinationParent, "Create repo restore directory")) {
            New-Item -Path $destinationParent -ItemType Directory -Force | Out-Null
        }
    }

    if ((Test-Path $destination) -and $Mode -eq "SkipExisting") {
        $restoreReport.Add([pscustomobject]@{ type = "repoFile"; path = $destination; status = "skipped" })
        continue
    }

    if ($PSCmdlet.ShouldProcess($destination, "Restore repo file")) {
        $sourcePath = Join-Path $manifestDir $repoFile.backupPath
        Copy-Item -Path $sourcePath -Destination $destination -Force:($Mode -eq "Overwrite")
    }

    $restoreReport.Add([pscustomobject]@{ type = "repoFile"; path = $destination; status = "restored" })
}

# Build restore target map from manifest
$originalOsDrive = $manifest.machine.osDrive
$restoreTargetMap = @{}
if ($manifest.restoreTargets) {
    foreach ($prop in $manifest.restoreTargets.PSObject.Properties) {
        $restoreTargetMap[$prop.Name] = $prop.Value
    }
}

foreach ($rule in $manifest.rules) {
    if (-not $rule.success) {
        continue
    }

    if ($IncludeTags -and @($rule.tags | Where-Object { $IncludeTags -contains $_ }).Count -eq 0) {
        continue
    }

    $targetPath = Resolve-RestoreTargetPath -Path $rule.restorePath -ProfileRoot $DestinationProfileRoot -OriginalOsDrive $originalOsDrive -RestoreTargetMap $restoreTargetMap
    $sourcePath = Join-Path $manifestDir $rule.backupPath
    $success = Copy-Tree -Source $sourcePath -Destination $targetPath -RobocopyMode $Mode
    $restoreReport.Add([pscustomobject]@{
        type = "content"
        path = $targetPath
        status = if ($success) { "restored" } else { "failed" }
    })
}

$reportPath = Join-Path (Split-Path -Path $resolvedManifestPath -Parent) "restore-report.json"
$restoreReport | ConvertTo-Json -Depth 5 | Set-Content -Path $reportPath -Force
Write-Success "Restore report written to $reportPath"
