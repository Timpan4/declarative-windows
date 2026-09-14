function Get-BackupCandidate {
    param([Parameter(Mandatory)][string]$ManifestPath)

    $candidate = [pscustomobject]@{
        ManifestPath = $ManifestPath
        Machine = 'Not recorded'
        Profile = 'Not recorded'
        CreatedAt = 'Not recorded'
        CompletedAt = 'Not recorded'
        Compatibility = 'Unsupported'
        Completeness = 'Unknown'
        Verification = 'Content not verified during discovery'
        Details = ''
    }
    try {
        Assert-NoBackupReparsePoint $ManifestPath
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        # Identity is reported metadata, not proof of ownership or authenticity.
        if ($manifest.machine -is [string]) { $candidate.Machine = $manifest.machine }
        elseif ($manifest.machine.computerName -is [string]) { $candidate.Machine = $manifest.machine.computerName }
        if ($manifest.machine.userProfile -is [string]) { $candidate.Profile = $manifest.machine.userProfile }
        if ($manifest.createdAt -is [string]) { $candidate.CreatedAt = $manifest.createdAt }
        elseif ($manifest.createdAt -is [datetime]) { $candidate.CreatedAt = $manifest.createdAt.ToString('o') }
        if ($manifest.completedAt -is [string]) { $candidate.CompletedAt = $manifest.completedAt }
        elseif ($manifest.completedAt -is [datetime]) { $candidate.CompletedAt = $manifest.completedAt.ToString('o') }
        Assert-BackupManifest $manifest
        $candidate.Compatibility = 'Supported'
    }
    catch {
        $candidate.Details = $_.Exception.Message
        return $candidate
    }

    if ($manifest.failures -is [array]) {
        $candidate.Completeness = if ($manifest.failures.Count) { 'Incomplete' } else { 'Recorded complete' }
    }
    if (@($manifest.rules | Where-Object { -not $_.success -and $_.skipped -ne $true }).Count -or
        ($null -ne $manifest.verification -and $manifest.verification.status -ne 'verified')) {
        $candidate.Completeness = 'Incomplete'
    }
    try {
        $root = Split-Path -Parent $ManifestPath
        foreach ($entry in $manifest.repoFiles) {
            $source = Resolve-BackupSourcePath $entry.backupPath $manifest.backup.backupRoot $root
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing backup file: $source" }
        }
        foreach ($entry in $manifest.rules) {
            if (-not $entry.success) { continue }
            $source = Resolve-BackupSourcePath $entry.backupPath $manifest.backup.backupRoot $root
            if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Missing backup folder: $source" }
        }
        if ($null -ne $manifest.verification) {
            Assert-BackupHashes -Manifest $manifest -BackupRoot $root -MetadataOnly
        }
    }
    catch {
        $candidate.Completeness = 'Incomplete'
        $candidate.Details = $_.Exception.Message
    }
    return $candidate
}

function Find-BackupManifest {
    param([string]$Path)

    $searchErrors = @()
    $explicitFile = $false
    if ($Path) {
        $selected = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $roots = @($selected.FullName)
        $explicitFile = -not $selected.PSIsContainer
    }
    else {
        $roots = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue -ErrorVariable +searchErrors |
            Where-Object { $_.Root -ne "$($env:SystemDrive)\" } |
            ForEach-Object { Join-Path $_.Root 'declarative-windows-backup' })
    }

    $paths = @(foreach ($root in $roots) {
        if ($explicitFile) { $root; continue }
        if (Test-Path -LiteralPath $root -ErrorAction SilentlyContinue -ErrorVariable +searchErrors) {
            Get-ChildItem -LiteralPath $root -Filter 'backup-manifest.json' -Recurse -File -Force -ErrorAction SilentlyContinue -ErrorVariable +searchErrors |
                ForEach-Object { $_.FullName }
        }
    })
    $candidates = @($paths | Sort-Object -Unique | ForEach-Object { Get-BackupCandidate $_ })
    if ($candidates.Count) { $candidates | Format-List | Out-Host }
    else {
        $searched = if ($roots.Count) { $roots -join ', ' } else { 'No non-system filesystem drives available' }
        Write-Warning "No backup manifests found. Searched: $searched. Pass -ManifestPath with a backup file or folder."
    }
    if ($explicitFile) {
        if ($candidates[0].Compatibility -ne 'Supported') {
            throw "Selected backup is unsupported: $Path. $($candidates[0].Details) No other backup was selected."
        }
        # An explicit file retains legacy and partial-restore support. Restore planning
        # still validates the selected content before any writes.
        return $candidates[0].ManifestPath
    }
    if ($searchErrors.Count) {
        Write-Warning "Backup discovery could not inspect every search location: $($searchErrors -join '; '). Pass -ManifestPath with an explicit manifest file."
        return $null
    }
    if ($candidates.Count -eq 1 -and $candidates[0].Compatibility -eq 'Supported' -and $candidates[0].Completeness -eq 'Recorded complete') {
        return $candidates[0].ManifestPath
    }
    if ($candidates.Count) {
        Write-Warning 'Backup selection requires an explicit manifest file. Automatic selection requires exactly one candidate that is supported and recorded complete. Pass -ManifestPath with the chosen file.'
    }
    return $null
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
        $targets = $Manifest.restoreTargets
        $names = if ($targets -is [Collections.IDictionary]) { $targets.Keys } else { $targets.PSObject.Properties.Name }
        foreach ($name in $names) {
            # repoPath selects the repository root; it is not a source-prefix mapping.
            if ($name -eq 'repoPath') { continue }
            $key = Get-CanonicalBackupPath $name
            if ($restoreTargetMap.ContainsKey($key)) { throw "Duplicate restore mapping: $key" }
            $restoreTargetMap[$key] = Get-CanonicalBackupPath $targets.$name
        }
    }

    return $restoreTargetMap
}

function Get-CanonicalBackupPath {
    param([object]$Path)

    if ($Path -isnot [string] -or [string]::IsNullOrWhiteSpace($Path)) {
        throw 'Expected a non-empty filesystem path.'
    }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path).Replace('/', '\')
    if ($expanded -notmatch '^(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+)' -or $expanded -match '[*?"<>|]' -or $expanded -match '^\\\\[?.]\\' -or $expanded.Substring(2).Contains(':')) {
        throw "Expected an absolute filesystem path: $Path"
    }
    $fullPath = [IO.Path]::GetFullPath($expanded)
    if ($fullPath -eq [IO.Path]::GetPathRoot($fullPath)) { return $fullPath }
    return $fullPath.TrimEnd('\')
}

function Test-BackupPathWithin {
    param([string]$Path, [string]$Root)
    return $Path.Equals($Root, [StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith($Root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoBackupReparsePoint {
    param([string]$Path)
    $current = $Path
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse-point paths are not supported for backup or restore: $current. Use the resolved physical folder path."
            }
        }
        $current = Split-Path -Path $current -Parent
    }
}

function Resolve-ContainedBackupPath {
    param([object]$Path, [string]$Root)
    $rootPath = Get-CanonicalBackupPath $Root
    if ($Path -isnot [string] -or [string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)|[:*?"<>|]|[. ]([\\/]|$)') {
        throw "Expected a contained relative backup path: $Path"
    }
    $candidate = Get-CanonicalBackupPath (Join-Path $rootPath $Path)
    if ($candidate -eq $rootPath -or -not (Test-BackupPathWithin $candidate $rootPath)) {
        throw "Path escapes its backup or repository root: $Path"
    }
    Assert-NoBackupReparsePoint $candidate
    return $candidate
}

function Resolve-BackupSourcePath {
    param(
        [string]$Path,

        [string]$ManifestBackupRoot,
        [string]$ActualBackupRoot
    )

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)
    if ([IO.Path]::IsPathRooted($expandedPath)) {
        $expandedPath = Get-CanonicalBackupPath $expandedPath
        $recordedRoot = Get-CanonicalBackupPath $ManifestBackupRoot
        if (-not (Test-BackupPathWithin $expandedPath $recordedRoot)) {
            throw "Backup source is outside the recorded backup root: $Path"
        }
        $expandedPath = $expandedPath.Substring($recordedRoot.TrimEnd('\').Length).TrimStart('\')
    }
    return Resolve-ContainedBackupPath -Path $expandedPath -Root $ActualBackupRoot
}

function Resolve-RestoreTargetPath {
    param(
        [string]$Path,
        [string]$ProfileRoot,
        [string]$OriginalOsDrive,
        [hashtable]$RestoreTargetMap,
        [string]$OriginalProfileRoot
    )

    $expandedPath = Get-CanonicalBackupPath $Path
    # Explicit mappings take priority over automatic profile and drive remapping.
    foreach ($key in @($RestoreTargetMap.Keys | Sort-Object Length -Descending)) {
        $sourceRoot = Get-CanonicalBackupPath $key
        if (Test-BackupPathWithin $expandedPath $sourceRoot) {
            $targetRoot = Get-CanonicalBackupPath $RestoreTargetMap[$key]
            $suffix = $expandedPath.Substring($sourceRoot.TrimEnd('\').Length).TrimStart('\')
            if (-not $suffix) { return $targetRoot }
            return Join-Path $targetRoot $suffix
        }
    }

    if ($ProfileRoot) {
        # Legacy manifests without profile metadata retain the current-profile fallback.
        $sourceProfile = if ($OriginalProfileRoot) { $OriginalProfileRoot } else { $env:USERPROFILE }
        $sourceProfile = [Environment]::ExpandEnvironmentVariables($sourceProfile).Replace('/', '\').TrimEnd('\')
        $profilePath = $expandedPath.Replace('/', '\')
        if ($sourceProfile -and $profilePath.TrimEnd('\').Equals($sourceProfile, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $ProfileRoot
        }
        if ($sourceProfile -and $profilePath.StartsWith($sourceProfile + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            $relativePath = $profilePath.Substring($sourceProfile.Length).TrimStart('\')
            return Join-Path $ProfileRoot $relativePath
        }
    }

    if ($OriginalOsDrive -and $env:SystemDrive -ne $OriginalOsDrive) {
        $osDriveSlash = $OriginalOsDrive + "\"
        if ($expandedPath.StartsWith($osDriveSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
            $currentOsDriveSlash = $env:SystemDrive + "\"
            $relativePath = $expandedPath.Substring($OriginalOsDrive.Length)
            return $currentOsDriveSlash + $relativePath.TrimStart('\')
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

function Assert-BackupObject {
    param([object]$Value, [string]$Name)
    if ($Value -isnot [pscustomobject] -and $Value -isnot [Collections.IDictionary]) { throw "$Name must be an object." }
}

function Assert-BackupVersion {
    param([object]$Value, [string]$Name)
    # Unversioned legacy inputs use the same v1 fields and are validated below.
    if ($null -ne $Value -and (($Value -isnot [int] -and $Value -isnot [long]) -or $Value -ne 1)) {
        throw "Unsupported $Name version. Only version 1 and unversioned legacy inputs are supported."
    }
}

function Assert-BackupStringList {
    param([object]$Value, [string]$Name)
    if ($null -eq $Value) { return }
    if ($Value -isnot [array]) { throw "$Name must be an array of strings." }
    foreach ($entry in $Value) {
        if ($entry -isnot [string] -or [string]::IsNullOrWhiteSpace($entry)) { throw "$Name must contain non-empty strings." }
    }
}

function Assert-BackupConfiguration {
    param([object]$Config)
    Assert-BackupObject $Config 'Backup configuration'
    Assert-BackupVersion $Config.version 'backup configuration'
    foreach ($collection in @('knownFolders', 'extraPaths')) {
        if ($Config.$collection -isnot [array]) { throw "$collection must be an array." }
        foreach ($entry in $Config.$collection) {
            Assert-BackupObject $entry $collection
            Assert-BackupApplication $entry.application
            if ($entry.enabled -isnot [bool]) { throw "$collection.enabled must be a boolean." }
            if ($null -ne $entry.required -and $entry.required -isnot [bool]) { throw "$collection.required must be a boolean." }
            Assert-BackupStringList $entry.tags "$collection.tags"
            if ($collection -eq 'knownFolders') {
                if ($entry.name -notin @('Desktop', 'Documents', 'Pictures', 'Downloads', 'Videos', 'Music')) { throw 'Unsupported known folder name.' }
            }
            else {
                $null = Get-CanonicalBackupPath $entry.path
                if ($null -ne $entry.label -and $entry.label -isnot [string]) { throw 'extraPaths.label must be a string.' }
            }
        }
    }
    Assert-BackupStringList $Config.excludePatterns 'excludePatterns'
    if ($null -ne $Config.options) {
        Assert-BackupObject $Config.options 'options'
        foreach ($name in @('backupRepoFiles', 'copyDownloads')) {
            if ($null -ne $Config.options.$name -and $Config.options.$name -isnot [bool]) { throw "options.$name must be a boolean." }
        }
    }
    if ($null -ne $Config.restoreTargets) {
        Assert-BackupObject $Config.restoreTargets 'restoreTargets'
        foreach ($property in $Config.restoreTargets.PSObject.Properties) { $null = Get-CanonicalBackupPath $property.Value }
        $null = Get-RestoreTargetMap $Config
    }
}

function Assert-BackupApplication {
    param([object]$Application)
    if ($null -eq $Application) { return }
    Assert-BackupObject $Application 'application'
    if ($Application.id -isnot [string] -or [string]::IsNullOrWhiteSpace($Application.id)) { throw 'application.id must be a non-empty string.' }
    Assert-BackupStringList $Application.processNames 'application.processNames'
    if (-not $Application.processNames.Count) { throw 'application.processNames must name the processes that must be closed.' }
    foreach ($name in $Application.processNames) {
        if ($name -match '[\\/:*?"<>|]' -or $name.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) { throw 'application.processNames must contain exact process names without paths, wildcards, or .exe.' }
    }
}

function Assert-BackupManifest {
    param([object]$Manifest)
    Assert-BackupObject $Manifest 'Backup manifest'
    Assert-BackupVersion $Manifest.manifestVersion 'manifest'
    foreach ($name in @('machine', 'backup', 'repo')) { Assert-BackupObject $Manifest.$name $name }
    $null = Get-CanonicalBackupPath $Manifest.backup.backupRoot
    $null = Get-CanonicalBackupPath $Manifest.repo.restorePath
    if ($null -ne $Manifest.machine.userProfile) { $null = Get-CanonicalBackupPath $Manifest.machine.userProfile }
    if ($null -ne $Manifest.machine.osDrive -and ($Manifest.machine.osDrive -isnot [string] -or $Manifest.machine.osDrive -notmatch '^[A-Za-z]:$')) { throw 'machine.osDrive must be a drive letter followed by a colon.' }
    foreach ($name in @('repoFiles', 'rules')) {
        if ($Manifest.$name -isnot [array]) { throw "$name must be an array." }
        foreach ($entry in $Manifest.$name) {
            Assert-BackupObject $entry $name
            if ($name -eq 'rules') {
                Assert-BackupApplication $entry.application
                if ($entry.success -isnot [bool]) { throw 'rules.success must be a boolean.' }
                # Earlier v1 producers serialized an absent optional tag list as [null].
                if ($entry.tags -is [array] -and $entry.tags.Count -eq 1 -and $null -eq $entry.tags[0]) { $entry.tags = @() }
                Assert-BackupStringList $entry.tags 'rules.tags'
                if (-not $entry.success) { continue }
                $null = Get-CanonicalBackupPath $entry.restorePath
            }
            elseif ($entry.relativePath -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.relativePath)) { throw 'repoFiles.relativePath must be a non-empty string.' }
            if ($entry.backupPath -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.backupPath)) { throw "$name.backupPath must be a non-empty string." }
        }
    }
    if ($null -ne $Manifest.restoreTargets) {
        Assert-BackupObject $Manifest.restoreTargets 'restoreTargets'
        foreach ($property in $Manifest.restoreTargets.PSObject.Properties) {
            $null = Get-CanonicalBackupPath $property.Name
            $null = Get-CanonicalBackupPath $property.Value
        }
    }
}

function Assert-BackupPathsDisjoint {
    param([string]$Source, [string]$Destination)
    $sourcePath = Get-CanonicalBackupPath $Source
    $destinationPath = Get-CanonicalBackupPath $Destination
    Assert-NoBackupReparsePoint $sourcePath
    Assert-NoBackupReparsePoint $destinationPath
    if ((Test-BackupPathWithin $destinationPath $sourcePath) -or (Test-BackupPathWithin $sourcePath $destinationPath)) {
        throw "Backup source and destination overlap: $sourcePath and $destinationPath"
    }
}

function Get-BackupTreeFiles {
    param([string]$Root)
    Assert-NoBackupReparsePoint $Root
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Backup directory missing: $Root" }
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($Root)
    while ($pending.Count -gt 0) {
        foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force -ErrorAction Stop) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Cannot verify a reparse point in backup content: $($item.FullName)" }
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            else { $item }
        }
    }
}

function Get-VerifiedBackupFile {
    param([string]$Path, [string]$BackupRoot, [string]$Source)
    Assert-NoBackupReparsePoint $Path
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($Source) {
        Assert-NoBackupReparsePoint $Source
        $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($hash -ne $sourceHash) { throw "Backup hash mismatch between source '$Source' and copy '$Path'." }
    }
    return [pscustomobject]@{ path = $Path.Substring($BackupRoot.TrimEnd('\').Length).TrimStart('\'); sha256 = $hash }
}

function Assert-BackupHashes {
    param([object]$Manifest, [string]$BackupRoot, [switch]$MetadataOnly)
    if ($null -eq $Manifest.verification) {
        if ($MetadataOnly) { return }
        # Older manifests recorded only repository-file hashes, without source comparison.
        foreach ($entry in $Manifest.repoFiles) {
            if ($null -ne $entry.sha256) {
                $path = Resolve-BackupSourcePath $entry.backupPath $Manifest.backup.backupRoot $BackupRoot
                if ($entry.sha256 -isnot [string] -or $entry.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash -ne $entry.sha256) {
                    throw "Legacy backup hash validation failed: $path"
                }
            }
        }
        Write-Warning 'This legacy backup has no complete file verification record. Any stored repository hashes were checked; other content is unverified.'
        return
    }
    $verification = $Manifest.verification
    Assert-BackupObject $verification 'verification'
    if ($verification.algorithm -ne 'SHA256' -or $verification.status -ne 'verified' -or $verification.files -isnot [array]) { throw 'Backup does not contain a successful SHA256 file verification record.' }
    $verifiedPaths = @{}
    foreach ($entry in $verification.files) {
        Assert-BackupObject $entry 'verification.files'
        if ($entry.sha256 -isnot [string] -or $entry.sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'verification.files.sha256 must contain a SHA256 digest.' }
        $path = Resolve-ContainedBackupPath $entry.path $BackupRoot
        if ($verifiedPaths.ContainsKey($path)) { throw "Duplicate verified backup path: $path" }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing recorded backup file: $path" }
        if (-not $MetadataOnly -and (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash -ne $entry.sha256) { throw "Backup hash validation failed: $path" }
        $verifiedPaths[$path] = $true
    }
    # Added files must not silently join a verified restore, including hidden files.
    foreach ($directory in @('files', 'repo-files', 'exports')) {
        $root = Join-Path $BackupRoot $directory
        foreach ($file in Get-BackupTreeFiles $root) {
            if (-not $verifiedPaths.ContainsKey($file.FullName)) { throw "Backup file has no verification record: $($file.FullName)" }
        }
    }
    foreach ($entry in $Manifest.repoFiles) {
        $path = Resolve-BackupSourcePath $entry.backupPath $Manifest.backup.backupRoot $BackupRoot
        if (-not $verifiedPaths.ContainsKey($path)) { throw "Restore source has no verification record: $path" }
    }
    foreach ($entry in $Manifest.rules) {
        if (-not $entry.success) { continue }
        $root = Resolve-BackupSourcePath $entry.backupPath $Manifest.backup.backupRoot $BackupRoot
        foreach ($file in Get-BackupTreeFiles $root) {
            if (-not $verifiedPaths.ContainsKey($file.FullName)) { throw "Restore source has no verification record: $($file.FullName)" }
        }
    }
}

function New-BackupManifest {
    param(
        [Parameter(Mandatory)][object]$Machine,
        [Parameter(Mandatory)][object]$Repo,
        [Parameter(Mandatory)][object]$Backup,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rules,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$RepoFiles,
        [Parameter(Mandatory)][object]$Exports,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Failures,
        [hashtable]$RestoreTargets = @{},
        [object]$Verification
    )

    $manifest = [ordered]@{
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
        restoreTargets = $RestoreTargets
    }
    if ($null -ne $Verification) { $manifest.verification = $Verification }
    return $manifest
}
