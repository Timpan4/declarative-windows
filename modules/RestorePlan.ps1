function Get-RestoreFileHash {
    param([string]$Path)
    Assert-NoBackupReparsePoint $Path
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Expected a file: $Path" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

function Get-RestoreRecoveryPath {
    param([string]$OriginalPath, [string]$RecoveryRoot)
    $original = Get-CanonicalBackupPath $OriginalPath
    $relative = if ($original.StartsWith('\\')) { 'UNC\' + $original.TrimStart('\') } else { $original.Replace(':', '') }
    return Resolve-ContainedBackupPath $relative $RecoveryRoot
}

function New-RestoreFileDecision {
    param([string]$Source, [string]$Destination, [string]$OriginalPath, [string]$RecoveryRoot, [string]$Kind, [string]$Mode, [bool]$UseBackupSettings)
    $hash = Get-RestoreFileHash $Source
    if (-not $hash) { throw "Backup file missing: $Source" }
    $currentHash = Get-RestoreFileHash $Destination
    $action = 'restore'
    $outputPath = $Destination
    $outputHash = $currentHash
    if ($Mode -eq 'SkipExisting' -and $currentHash) { $action = 'skip' }
    elseif ($hash -eq $currentHash) { $action = 'already-present' }
    elseif (($Kind -eq 'project-settings' -and -not $UseBackupSettings) -or ($currentHash -and $Mode -ne 'Overwrite' -and $Kind -eq 'personal')) {
        $action = 'recover'
        $outputPath = Get-RestoreRecoveryPath $OriginalPath $RecoveryRoot
        $outputHash = Get-RestoreFileHash $outputPath
        if ($outputHash -and $outputHash -ne $hash) {
            # An edited recovered copy is user data too. Keep it and use a stable alternate.
            $outputPath += '.backup-' + $hash
            $outputHash = Get-RestoreFileHash $outputPath
            if ($outputHash -and $outputHash -ne $hash) { throw "Recovered destination has changed: $outputPath" }
        }
        if ($outputHash -eq $hash) { $action = 'already-present' }
    }
    elseif ($currentHash) { $action = 'replace' }
    [pscustomobject]@{
        kind = $Kind; source = $Source; path = $Destination; outputPath = $outputPath
        sha256 = $hash; currentHash = $currentHash; outputHash = $outputHash; action = $action
    }
}

function Get-RestoreTreeSnapshot {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) { return }
    foreach ($file in Get-BackupTreeFiles $Root) {
        [pscustomobject]@{ relativePath = $file.FullName.Substring($Root.TrimEnd('\').Length).TrimStart('\'); sha256 = Get-RestoreFileHash $file.FullName }
    }
}

function Assert-RestoreTreeSnapshot {
    param([string]$Root, [object[]]$Files)
    $current = @(Get-RestoreTreeSnapshot $Root)
    if ($current.Count -ne $Files.Count) { throw "Application state changed since preview: $Root" }
    $expected = @{}
    foreach ($file in $Files) { $expected[$file.relativePath] = $file.sha256 }
    foreach ($file in $current) {
        if ($expected[$file.relativePath] -ne $file.sha256) { throw "Application state changed since preview: $Root" }
    }
}

function Assert-RestoreApplicationClosed {
    param([object]$Application)
    $running = @(Get-Process -ErrorAction Stop | Where-Object { $Application.processNames -contains $_.ProcessName })
    if ($running.Count) { throw "Close application '$($Application.id)' before restoring its state: $($running.ProcessName -join ', ')" }
}

function New-RestorePlan {
    param([string]$ManifestPath, [string]$DestinationProfileRoot, [string]$Mode = 'Merge', [string[]]$IncludeTags, [string[]]$RestoreApp, [switch]$UseBackupSettings)
    $resolvedManifestPath = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
    $manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
    Assert-BackupManifest $manifest
    $actualBackupRoot = Get-CanonicalBackupPath (Split-Path -Parent $resolvedManifestPath)
    $manifestBackupRoot = Get-BackupManifestRoot $manifest
    Assert-BackupHashes $manifest $actualBackupRoot
    $recordedHashes = @{}
    foreach ($file in $manifest.verification.files) {
        $recordedHashes[(Resolve-ContainedBackupPath $file.path $actualBackupRoot)] = $file.sha256
    }
    foreach ($file in $manifest.repoFiles) {
        if ($file.sha256) { $recordedHashes[(Resolve-BackupSourcePath $file.backupPath $manifestBackupRoot $actualBackupRoot)] = $file.sha256 }
    }
    $profile = Get-CanonicalBackupPath $DestinationProfileRoot
    $recoveryRoot = Join-Path (Join-Path $profile 'Recovered from backup') (Get-RestoreFileHash $resolvedManifestPath)
    Assert-BackupPathsDisjoint $actualBackupRoot $recoveryRoot
    $originalOsDrive = $manifest.machine.osDrive
    $restoreTargetMap = Get-RestoreTargetMap $manifest
    $repoTargetRoot = Get-CanonicalBackupPath (Resolve-RestoreTargetPath -Path $manifest.repo.restorePath -ProfileRoot $profile -OriginalOsDrive $originalOsDrive -RestoreTargetMap $restoreTargetMap -OriginalProfileRoot $manifest.machine.userProfile)
    $items = New-Object 'System.Collections.Generic.List[object]'
    $destinations = @{}
    $protectedAppPaths = @(
        foreach ($rule in $manifest.rules) {
            if ($rule.application -and $rule.restorePath) {
                Get-CanonicalBackupPath (Resolve-RestoreTargetPath -Path $rule.restorePath -ProfileRoot $profile -OriginalOsDrive $originalOsDrive -RestoreTargetMap $restoreTargetMap -OriginalProfileRoot $manifest.machine.userProfile)
            }
        }
    )
    $rules = @(
        foreach ($rule in $manifest.rules) {
            if (-not $rule.success) {
                $items.Add([pscustomobject]@{ kind = 'unavailable'; path = $rule.restorePath; action = 'skip'; message = 'Backup rule was not completed.' })
                continue
            }
            $sourcePath = Resolve-BackupSourcePath -Path $rule.backupPath -ManifestBackupRoot $manifestBackupRoot -ActualBackupRoot $actualBackupRoot
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) { throw "Backup content missing: $sourcePath" }
            $targetPath = Get-CanonicalBackupPath (Resolve-RestoreTargetPath -Path $rule.restorePath -ProfileRoot $profile -OriginalOsDrive $originalOsDrive -RestoreTargetMap $restoreTargetMap -OriginalProfileRoot $manifest.machine.userProfile)
            Assert-BackupPathsDisjoint $actualBackupRoot $targetPath
            Assert-BackupPathsDisjoint $recoveryRoot $targetPath
            [pscustomobject]@{ rule = $rule; source = $sourcePath; path = $targetPath }
        }
    )
    $appRules = @($rules | Where-Object { $null -ne $_.rule.application })
    foreach ($id in $RestoreApp) {
        if (-not @($appRules | Where-Object { $_.rule.application.id -eq $id }).Count) { throw "No complete application backup found for '$id'." }
        if (@($manifest.rules | Where-Object { $_.application.id -eq $id -and -not $_.success }).Count) { throw "Application backup is incomplete: $id" }
    }
    foreach ($appRule in $appRules) {
        foreach ($other in $appRules) {
            if ($appRule -ne $other) { Assert-BackupPathsDisjoint $appRule.path $other.path }
        }
        Assert-BackupPathsDisjoint $appRule.path $repoTargetRoot
    }
    foreach ($group in @($appRules | Group-Object { $_.rule.application.id })) {
        $application = [pscustomobject]@{ id = $group.Name; processNames = @($group.Group.rule.application.processNames | Sort-Object -Unique) }
        $selected = $RestoreApp -contains $application.id
        if ($selected) { Assert-RestoreApplicationClosed $application }
        $roots = @(
            foreach ($entry in $group.Group) {
                [pscustomobject]@{
                    source = $entry.source; path = $entry.path; existed = (Test-Path -LiteralPath $entry.path)
                    files = @(Get-RestoreTreeSnapshot $entry.source)
                    currentFiles = if ($selected) { @(Get-RestoreTreeSnapshot $entry.path) } else { @() }
                }
            }
        )
        $items.Add([pscustomobject]@{
            kind = 'application'; application = $application; roots = $roots; path = ($roots.path -join ', ')
            action = if ($selected) { 'restore-application' } else { 'skip' }
            message = if ($selected) { 'Replace related state together with the app closed.' } else { "Select -RestoreApp '$($application.id)' to restore this app's state." }
        })
    }
    foreach ($repoFile in $manifest.repoFiles) {
        $destination = Resolve-ContainedBackupPath $repoFile.relativePath $repoTargetRoot
        Assert-BackupPathsDisjoint $actualBackupRoot $destination
        Assert-BackupPathsDisjoint $recoveryRoot $destination
        $repoFileSource = Resolve-BackupSourcePath -Path $repoFile.backupPath -ManifestBackupRoot $manifestBackupRoot -ActualBackupRoot $actualBackupRoot
        $original = Resolve-ContainedBackupPath $repoFile.relativePath (Get-CanonicalBackupPath $manifest.repo.restorePath)
        $decision = New-RestoreFileDecision $repoFileSource $destination $original $recoveryRoot 'project-settings' $Mode $UseBackupSettings.IsPresent
        $items.Add($decision)
        $destinations[$destination] = $decision
    }
    foreach ($entry in $rules) {
        if ($entry.rule.application) { continue }
        if ($IncludeTags -and @($entry.rule.tags | Where-Object { $IncludeTags -contains $_ }).Count -eq 0) {
            $items.Add([pscustomobject]@{ kind = 'personal'; path = $entry.path; action = 'skip'; message = 'Excluded by IncludeTags.' })
            continue
        }
        foreach ($file in Get-BackupTreeFiles $entry.source) {
            $relative = $file.FullName.Substring($entry.source.TrimEnd('\').Length).TrimStart('\')
            $destination = Resolve-ContainedBackupPath $relative $entry.path
            $original = Resolve-ContainedBackupPath $relative (Get-CanonicalBackupPath $entry.rule.restorePath)
            # Explicit app roots also protect state incidentally included in a parent-folder backup.
            if (@($protectedAppPaths | Where-Object { Test-BackupPathWithin $destination $_ }).Count) { continue }
            $kind = if (Test-BackupPathWithin $destination $repoTargetRoot) { 'project-settings' } else { 'personal' }
            $originalAppData = $manifest.machine.userProfile -and (Test-BackupPathWithin $original (Join-Path $manifest.machine.userProfile 'AppData'))
            if ($originalAppData -or (Test-BackupPathWithin $destination (Join-Path $profile 'AppData')) -or $entry.rule.tags -contains 'app-state') {
                $items.Add([pscustomobject]@{ kind = 'application'; path = $destination; action = 'skip'; message = 'App state needs application metadata before it can be restored.' })
                continue
            }
            $decision = New-RestoreFileDecision $file.FullName $destination $original $recoveryRoot $kind $Mode $UseBackupSettings.IsPresent
            if ($destinations.ContainsKey($destination)) {
                if ($destinations[$destination].sha256 -ne $decision.sha256) { throw "Backup entries disagree for destination: $destination" }
                continue
            }
            $destinations[$destination] = $decision
            $items.Add($decision)
        }
    }
    # Pin planned content to the recorded hashes, including changes during plan construction.
    foreach ($item in $items) {
        $files = if ($item.source) { @([pscustomobject]@{ source = $item.source; sha256 = $item.sha256 }) } else {
            foreach ($root in $item.roots) {
                foreach ($file in $root.files) { [pscustomobject]@{ source = (Resolve-ContainedBackupPath $file.relativePath $root.source); sha256 = $file.sha256 } }
            }
        }
        foreach ($file in $files) {
            if (($manifest.verification -or $recordedHashes.ContainsKey($file.source)) -and $recordedHashes[$file.source] -ne $file.sha256) {
                throw "Backup content changed during planning: $($file.source)"
            }
        }
    }
    [pscustomobject]@{
        manifestPath = $resolvedManifestPath; backupRoot = $actualBackupRoot; profileRoot = $profile; recoveryRoot = $recoveryRoot
        verification = if ($manifest.verification) { 'Recorded hashes verified' } else { 'Legacy backup: complete original verification unavailable; copies will be hash checked' }
        items = $items.ToArray()
    }
}

function Copy-RestoreVerifiedFile {
    param([string]$Source, [string]$Destination, [string]$ExpectedHash)
    Assert-NoBackupReparsePoint $Source
    Assert-NoBackupReparsePoint $Destination
    Copy-Item -LiteralPath $Source -Destination $Destination -ErrorAction Stop
    if ((Get-RestoreFileHash $Destination) -ne $ExpectedHash -or (Get-RestoreFileHash $Source) -ne $ExpectedHash) { throw "Backup or copied content changed: $Source" }
}

function Invoke-RestoreFileDecision {
    param([object]$Item)
    if ($Item.action -in @('skip', 'already-present')) { return $Item.action }
    if ((Get-RestoreFileHash $Item.path) -ne $Item.currentHash -or (Get-RestoreFileHash $Item.outputPath) -ne $Item.outputHash) { throw "Destination changed since preview: $($Item.path)" }
    $parent = Split-Path -Parent $Item.outputPath
    $null = [IO.Directory]::CreateDirectory($parent)
    $temporary = Join-Path $parent ('.restore-' + [guid]::NewGuid().ToString())
    try {
        Copy-RestoreVerifiedFile $Item.source $temporary $Item.sha256
        Assert-NoBackupReparsePoint $Item.outputPath
        if ((Get-RestoreFileHash $Item.outputPath) -ne $Item.outputHash) { throw "Destination changed since preview: $($Item.outputPath)" }
        if ($Item.action -eq 'replace') { [IO.File]::Replace($temporary, $Item.outputPath, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Item.outputPath) }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction Stop }
    }
    if ($Item.action -eq 'recover') { return 'conflicting-copy-saved' }
    return 'restored'
}

function Move-RestoreDirectory {
    param([string]$Source, [string]$Destination)
    Assert-NoBackupReparsePoint $Source
    Assert-NoBackupReparsePoint $Destination
    # Directory.Move refuses an occupied target, unlike a merge into an existing directory.
    [IO.Directory]::Move($Source, $Destination)
}

function Invoke-RestoreApplication {
    param([object]$Item)
    Assert-RestoreApplicationClosed $Item.application
    $staged = New-Object 'System.Collections.Generic.List[object]'
    try {
        # Verify every root before replacing any part of this application's state.
        foreach ($root in $Item.roots) {
            Assert-NoBackupReparsePoint $root.path
            Assert-RestoreTreeSnapshot $root.source $root.files
            $parent = Split-Path -Parent $root.path
            $null = [IO.Directory]::CreateDirectory($parent)
            $stage = Join-Path $parent ('.restore-' + [guid]::NewGuid().ToString())
            $record = [pscustomobject]@{ root = $root; stage = $stage; previous = $stage + '-previous'; moved = $false; applied = $false }
            $staged.Add($record)
            Copy-Item -LiteralPath $root.source -Destination $stage -Recurse -ErrorAction Stop
            Assert-RestoreTreeSnapshot $stage $root.files
            Assert-RestoreTreeSnapshot $root.source $root.files
        }
        Assert-RestoreApplicationClosed $Item.application
        foreach ($record in $staged) {
            $root = $record.root
            Assert-NoBackupReparsePoint $root.path
            if ((Test-Path -LiteralPath $root.path) -ne $root.existed) { throw "Application destination changed since preview: $($root.path)" }
            Assert-RestoreTreeSnapshot $root.path $root.currentFiles
        }
        foreach ($record in $staged) {
            if ($record.root.existed) {
                Move-RestoreDirectory $record.root.path $record.previous
                $record.moved = $true
            }
            Move-RestoreDirectory $record.stage $record.root.path
            $record.applied = $true
        }
    }
    catch {
        for ($index = $staged.Count - 1; $index -ge 0; $index--) {
            $record = $staged[$index]
            if ($record.applied) { Move-RestoreDirectory $record.root.path $record.stage }
            if ($record.moved) { Move-RestoreDirectory $record.previous $record.root.path }
        }
        throw
    }
    finally {
        foreach ($record in $staged) {
            if (Test-Path -LiteralPath $record.stage) {
                # This is the unique staging sibling created above, never a user-supplied root.
                Assert-BackupPathsDisjoint $record.stage $record.root.path
                Remove-Item -LiteralPath $record.stage -Recurse -Force -ErrorAction Stop
            }
        }
    }
    # Retain the old app state for recovery; report its exact location.
    return @($staged | Where-Object moved | ForEach-Object { $_.previous })
}

function Invoke-RestorePlan {
    [CmdletBinding(SupportsShouldProcess)]
    param([object]$Plan)
    foreach ($item in $Plan.items) {
        $result = [ordered]@{ type = $item.kind; path = $item.path; outputPath = $item.outputPath; status = 'skipped'; message = $item.message }
        try {
            if ($item.action -eq 'skip') { }
            elseif ($item.action -eq 'already-present') { $result.status = 'already-present' }
            elseif ($PSCmdlet.ShouldProcess($item.path, $item.action)) {
                if ($item.action -eq 'restore-application') {
                    $result.previousPaths = @(Invoke-RestoreApplication $item)
                    $result.status = 'restored'
                }
                else { $result.status = Invoke-RestoreFileDecision $item }
            }
        }
        catch { $result.status = 'failed'; $result.message = $_.Exception.Message }
        [pscustomobject]$result
    }
}
