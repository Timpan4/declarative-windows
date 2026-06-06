function Find-BackupManifest {
    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object {
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

function Get-BackupManifestRoot {
    param([object]$Manifest)

    if ($Manifest.backup -and $Manifest.backup.backupRoot) {
        return [Environment]::ExpandEnvironmentVariables($Manifest.backup.backupRoot)
    }

    return $null
}

function Get-RestoreTargetMap {
    param([object]$Manifest)

    $restoreTargetMap = @{}
    if ($Manifest.restoreTargets) {
        foreach ($prop in $Manifest.restoreTargets.PSObject.Properties) {
            $restoreTargetMap[$prop.Name] = $prop.Value
        }
    }

    return $restoreTargetMap
}

function Resolve-BackupSourcePath {
    param(
        [string]$Path,

        [string]$ManifestBackupRoot,
        [string]$ActualBackupRoot
    )

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)
    if (-not [System.IO.Path]::IsPathRooted($expandedPath)) {
        if ($ActualBackupRoot) {
            return Join-Path $ActualBackupRoot $expandedPath
        }

        return $expandedPath
    }

    if (Test-Path $expandedPath) {
        return $expandedPath
    }

    if ($ManifestBackupRoot -and $ActualBackupRoot -and $expandedPath.StartsWith($ManifestBackupRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $expandedPath.Substring($ManifestBackupRoot.Length).TrimStart('\\')
        $candidatePath = if ($relativePath) {
            Join-Path $ActualBackupRoot $relativePath
        }
        else {
            $ActualBackupRoot
        }

        if (Test-Path $candidatePath) {
            if (Get-Command Write-Info -ErrorAction SilentlyContinue) {
                Write-Info "Using remapped backup path: $candidatePath"
            }
            return $candidatePath
        }
    }

    return $expandedPath
}

function Resolve-RestoreTargetPath {
    param(
        [string]$Path,
        [string]$ProfileRoot,
        [string]$OriginalOsDrive,
        [hashtable]$RestoreTargetMap
    )

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)

    if ($ProfileRoot) {
        $currentProfile = [Environment]::ExpandEnvironmentVariables("%USERPROFILE%")
        if ($expandedPath.StartsWith($currentProfile, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relativePath = $expandedPath.Substring($currentProfile.Length).TrimStart('\')
            return Join-Path $ProfileRoot $relativePath
        }
    }

    if ($OriginalOsDrive -and $env:SystemDrive -ne $OriginalOsDrive) {
        $osDriveSlash = $OriginalOsDrive + "\"
        if ($expandedPath.StartsWith($osDriveSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
            $currentOsDriveSlash = $env:SystemDrive + "\"
            $relativePath = $expandedPath.Substring($OriginalOsDrive.Length)
            $newPath = $currentOsDriveSlash + $relativePath.TrimStart('\')

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

    if ($expandedPath -match '^[A-Za-z]:\\') {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "Warning: Absolute path '$expandedPath' cannot be remapped - returning as-is"
        }
        else {
            Write-Warning "Absolute path '$expandedPath' cannot be remapped - returning as-is"
        }
    }

    return $expandedPath
}

function New-BackupManifest {
    param(
        [Parameter(Mandatory)][object]$Machine,
        [Parameter(Mandatory)][object]$Repo,
        [Parameter(Mandatory)][object]$Backup,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object[]]$Rules,
        [Parameter(Mandatory)][object[]]$RepoFiles,
        [Parameter(Mandatory)][object]$Exports,
        [Parameter(Mandatory)][object[]]$Failures
    )

    return [ordered]@{
        manifestVersion = 1
        createdAt = (Get-Date).ToString("o")
        machine = $Machine
        repo = $Repo
        backup = $Backup
        config = $Config
        rules = $Rules
        repoFiles = $RepoFiles
        exports = $Exports
        failures = $Failures
    }
}
