BeforeAll {
    $repository = Split-Path $PSScriptRoot -Parent
    $realCopy = Get-Command Copy-Item
    . (Join-Path $repository 'modules\BackupManifest.ps1')
    . (Join-Path $repository 'modules\RestorePlan.ps1')
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repository 'restore-backup.ps1'), [ref]$null, [ref]$null)
    $restore = [scriptblock]::Create('[CmdletBinding(SupportsShouldProcess)]' + $ast.ParamBlock.Extent.Text + "`n" + '$PSScriptRoot = ''' + $repository.Replace("'", "''") + "'`n" + (($ast.EndBlock.Statements | ForEach-Object { $_.Extent.Text }) -join "`n"))

    function Save-FixtureManifest {
        $null = New-Item -ItemType Directory -Path (Join-Path $session 'exports') -Force
        $manifest.verification = @{ algorithm = 'SHA256'; status = 'verified'; files = @(
            foreach ($folder in @('files', 'repo-files')) {
                foreach ($file in Get-BackupTreeFiles (Join-Path $session $folder)) {
                    Get-VerifiedBackupFile $file.FullName $session
                }
            }
        ) }
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath
    }
    function Add-FixtureApplication {
        foreach ($name in @('settings', 'database')) {
            $source = Join-Path $session "files\app-$name"
            $target = Join-Path $profile "AppData\Local\fixture-$name"
            $null = New-Item -ItemType Directory -Path $source, $target -Force
            Set-Content (Join-Path $source 'state') "backup $name"
            Set-Content (Join-Path $target 'state') "current $name"
            Set-Content (Join-Path $target 'obsolete') 'old state must not be merged'
            $manifest.rules += @{
                success = $true; backupPath = "files\app-$name"; restorePath = "C:\Users\previous\AppData\Local\fixture-$name"
                application = @{ id = 'fixture-app'; processNames = @('fixture-app', 'fixture-helper') }
            }
        }
        Save-FixtureManifest
    }
}

Describe 'safe restore conflicts' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $session = Join-Path $root 'backup'
        $profile = Join-Path $root 'restored'
        $manifestPath = Join-Path $session 'backup-manifest.json'
        $null = New-Item -ItemType Directory -Path (Join-Path $session 'files\documents\nested'), (Join-Path $session 'repo-files'), (Join-Path $profile 'Documents\nested'), (Join-Path $profile 'repo') -Force
        $sourceFile = Join-Path $session 'files\documents\nested\conflict.txt'
        $currentFile = Join-Path $profile 'Documents\nested\conflict.txt'
        Set-Content $sourceFile 'backup content'
        Set-Content $currentFile 'current content'
        Set-Content (Join-Path $session 'files\documents\missing.txt') 'missing content'
        Set-Content (Join-Path $session 'files\documents\identical.txt') 'identical'
        Set-Content (Join-Path $profile 'Documents\identical.txt') 'identical'
        Set-Content (Join-Path $session 'repo-files\apps.json') 'backup settings'
        Set-Content (Join-Path $profile 'repo\apps.json') 'current settings'
        $manifest = @{
            manifestVersion = 1; machine = @{ userProfile = 'C:\Users\previous'; osDrive = 'C:' }
            backup = @{ backupRoot = $session }; repo = @{ restorePath = 'C:\Users\previous\repo' }
            repoFiles = @(@{ relativePath = 'apps.json'; backupPath = 'repo-files\apps.json' })
            rules = @(@{ success = $true; backupPath = 'files\documents'; restorePath = 'C:\Users\previous\Documents'; tags = @('documents') })
        }
        Save-FixtureManifest
        $parameters = @{ ManifestPath = $manifestPath; DestinationProfileRoot = $profile }
        Mock Out-Host {}
        Mock Copy-Item { & $realCopy -LiteralPath $LiteralPath -Destination $Destination -Recurse:$Recurse -ErrorAction Stop }
    }

    It 'keeps differing current content regardless of <Age> timestamps and reuses recovered files' -ForEach @(
        @{ Age = 'older'; Offset = -1 }, @{ Age = 'equal'; Offset = 0 }, @{ Age = 'newer'; Offset = 1 }
    ) {
        (Get-Item $sourceFile).LastWriteTimeUtc = (Get-Item $currentFile).LastWriteTimeUtc.AddDays($Offset)
        $plan = New-RestorePlan @parameters
        $conflict = $plan.items | Where-Object path -eq $currentFile
        $conflict.action | Should -Be 'recover'
        $conflict.outputPath | Should -Be (Join-Path $plan.recoveryRoot 'C\Users\previous\Documents\nested\conflict.txt')
        $report = @(Invoke-RestorePlan $plan)
        Get-Content $currentFile | Should -Be 'current content'
        Get-Content $conflict.outputPath | Should -Be 'backup content'
        Get-Content (Join-Path $profile 'Documents\missing.txt') | Should -Be 'missing content'
        @($report | Where-Object status -eq 'restored').Count | Should -Be 1
        @($report | Where-Object status -eq 'already-present').Count | Should -Be 1
        @($report | Where-Object status -eq 'conflicting-copy-saved').Count | Should -Be 2
        $second = New-RestorePlan @parameters
        $second.recoveryRoot | Should -Be $plan.recoveryRoot
        @(Invoke-RestorePlan $second | Where-Object status -ne 'already-present').Count | Should -Be 0
        @(Get-BackupTreeFiles $plan.recoveryRoot).Count | Should -Be 2
        Get-Content $sourceFile | Should -Be 'backup content'
        Test-Path (Join-Path $session 'restore-report.json') | Should -BeFalse
    }

    It 'preserves an edited recovered conflict and saves a stable separate copy' {
        $plan = New-RestorePlan @parameters
        $null = Invoke-RestorePlan $plan
        $conflict = $plan.items | Where-Object path -eq $currentFile
        Set-Content $conflict.outputPath 'edited recovery'
        $next = New-RestorePlan @parameters
        $alternate = $next.items | Where-Object path -eq $currentFile
        $alternate.outputPath | Should -Not -Be $conflict.outputPath
        $null = Invoke-RestorePlan $next
        Get-Content $conflict.outputPath | Should -Be 'edited recovery'
        Get-Content $alternate.outputPath | Should -Be 'backup content'
        $again = New-RestorePlan @parameters
        ($again.items | Where-Object path -eq $currentFile).action | Should -Be 'already-present'
    }

    It 'keeps SkipExisting distinct from recovering conflicts' {
        $plan = New-RestorePlan @parameters -Mode SkipExisting
        $report = @(Invoke-RestorePlan $plan)
        @($report | Where-Object status -eq 'skipped').Count | Should -Be 3
        @($report | Where-Object status -eq 'restored').Count | Should -Be 1
        Test-Path $plan.recoveryRoot | Should -BeFalse
    }

    It 'previews without writes or prompts for <Option>' -ForEach @(@{ Option = 'Preview' }, @{ Option = 'WhatIf' }) {
        Mock Read-Host { throw 'Preview must not prompt' }
        $optionParameters = @{ $Option = $true }
        $plan = & $restore @parameters @optionParameters -Mode Overwrite -UseBackupSettings
        ($plan.items | Where-Object path -eq $currentFile).action | Should -Be 'replace'
        Test-Path $plan.recoveryRoot | Should -BeFalse
        Test-Path (Join-Path $profile 'Documents\missing.txt') | Should -BeFalse
        Get-Content $currentFile | Should -Be 'current content'
    }

    It 'requires confirmation after preview for advanced replacement: <Accept>' -ForEach @(@{ Accept = $true }, @{ Accept = $false }) {
        Mock Read-Host { if ($Accept) { 'YES' } else { 'N' } }
        $null = & $restore @parameters -Mode Overwrite -Force -Confirm:$false
        Get-Content $currentFile | Should -Be $(if ($Accept) { 'backup content' } else { 'current content' })
        Get-Content (Join-Path $profile 'repo\apps.json') | Should -Be 'current settings'
        Get-Content $sourceFile | Should -Be 'backup content'
        Should -Invoke Read-Host -Times 1 -Exactly
    }

    It 'applies project settings only after UseBackupSettings is selected and confirmed: <Accept>' -ForEach @(@{ Accept = $true }, @{ Accept = $false }) {
        Mock Read-Host { if ($Accept) { 'YES' } else { '' } }
        $null = & $restore @parameters -UseBackupSettings
        Get-Content (Join-Path $profile 'repo\apps.json') | Should -Be $(if ($Accept) { 'backup settings' } else { 'current settings' })
        Get-Content $currentFile | Should -Be 'current content'
    }

    It 'does not restore missing project settings or nested repo content implicitly' {
        Remove-Item -LiteralPath (Join-Path $profile 'repo\apps.json')
        $null = New-Item -ItemType Directory -Path (Join-Path $session 'files\repo')
        Set-Content (Join-Path $session 'files\repo\preferences.ps1') 'backup preferences'
        $manifest.rules += @{ success = $true; backupPath = 'files\repo'; restorePath = 'C:\Users\previous\repo' }
        Save-FixtureManifest
        $plan = New-RestorePlan @parameters
        $null = Invoke-RestorePlan $plan
        @(Get-ChildItem -LiteralPath (Join-Path $profile 'repo')).Count | Should -Be 0
        @($plan.items | Where-Object kind -eq 'project-settings').Count | Should -Be 2
    }

    It 'leaves all backup files unchanged and offers Open recovered files' {
        $before = @(Get-RestoreTreeSnapshot $session)
        Mock Start-Process {}
        $null = & $restore @parameters -Force -OpenRecoveredFiles
        Assert-RestoreTreeSnapshot $session $before
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'explorer.exe' }
    }

    It 'does not publish corrupted copies or overwrite current files after <Fault>' -ForEach @(
        @{ Fault = 'copy failure' }, @{ Fault = 'copy corruption' }, @{ Fault = 'source change' }, @{ Fault = 'destination change' }
    ) {
        $plan = New-RestorePlan @parameters -Mode Overwrite
        $item = $plan.items | Where-Object path -eq $currentFile
        switch ($Fault) {
            'copy failure' { Mock Copy-Item { throw 'Synthetic copy failure' } }
            'copy corruption' { Mock Copy-Item { Set-Content -LiteralPath $Destination 'corrupt' } }
            'source change' { Set-Content $sourceFile 'changed backup' }
            'destination change' { Set-Content $currentFile 'changed current' }
        }
        $report = @(Invoke-RestorePlan ([pscustomobject]@{ items = @($item) }))
        $report[0].status | Should -Be 'failed'
        Get-Content $currentFile | Should -Be $(if ($Fault -eq 'destination change') { 'changed current' } else { 'current content' })
        @(Get-ChildItem -LiteralPath (Split-Path $currentFile -Parent) -Force -Filter '.restore-*').Count | Should -Be 0
    }

    It 'rejects an integrity failure or backup overlap before writes: <Fault>' -ForEach @(@{ Fault = 'hash' }, @{ Fault = 'overlap' }) {
        if ($Fault -eq 'hash') { Set-Content $sourceFile 'corrupt backup' }
        else { $manifest.rules[0].restorePath = $session; Save-FixtureManifest }
        { New-RestorePlan @parameters } | Should -Throw
        Test-Path (Join-Path $profile 'Recovered from backup') | Should -BeFalse
    }

    It 'skips unclassified AppData instead of merging databases' {
        $manifest.rules[0].restorePath = 'C:\Users\previous\AppData\Local\unknown'
        Save-FixtureManifest
        $plan = New-RestorePlan @parameters -Mode Overwrite
        @($plan.items | Where-Object { $_.kind -eq 'application' -and $_.action -eq 'skip' }).Count | Should -Be 3
        $null = Invoke-RestorePlan $plan
        Test-Path (Join-Path $profile 'AppData') | Should -BeFalse
    }

    It 'restores selected app roots together without merging old state' {
        Add-FixtureApplication
        Mock Get-Process { @() }
        $default = New-RestorePlan @parameters -Mode Overwrite
        ($default.items | Where-Object kind -eq 'application').action | Should -Be 'skip'
        $plan = New-RestorePlan @parameters -RestoreApp fixture-app -IncludeTags unrelated
        $report = @(Invoke-RestorePlan $plan)
        $app = $report | Where-Object type -eq 'application'
        $app.status | Should -Be 'restored'
        $app.previousPaths.Count | Should -Be 2
        foreach ($name in @('settings', 'database')) {
            Get-Content (Join-Path $profile "AppData\Local\fixture-$name\state") | Should -Be "backup $name"
            Test-Path (Join-Path $profile "AppData\Local\fixture-$name\obsolete") | Should -BeFalse
        }
        foreach ($path in $app.previousPaths) { Test-Path (Join-Path $path 'obsolete') | Should -BeTrue }
    }

    It 'rejects running apps at preview and checks again before execution' {
        Add-FixtureApplication
        Mock Get-Process { [pscustomobject]@{ ProcessName = 'fixture-helper' } }
        { New-RestorePlan @parameters -RestoreApp fixture-app } | Should -Throw '*Close application*'
        Mock Get-Process { @() }
        $plan = New-RestorePlan @parameters -RestoreApp fixture-app
        Mock Get-Process { [pscustomobject]@{ ProcessName = 'fixture-app' } }
        $report = @(Invoke-RestorePlan $plan)
        ($report | Where-Object type -eq 'application').status | Should -Be 'failed'
        Get-Content (Join-Path $profile 'AppData\Local\fixture-settings\state') | Should -Be 'current settings'
    }

    It 'keeps all current app roots if staging one fails' {
        Add-FixtureApplication
        Mock Get-Process { @() }
        $plan = New-RestorePlan @parameters -RestoreApp fixture-app
        Mock Copy-Item { throw 'Synthetic app copy failure' } -ParameterFilter { $LiteralPath -like '*app-database' }
        $report = @(Invoke-RestorePlan $plan)
        ($report | Where-Object type -eq 'application').status | Should -Be 'failed'
        foreach ($name in @('settings', 'database')) {
            Get-Content (Join-Path $profile "AppData\Local\fixture-$name\state") | Should -Be "current $name"
        }
    }

    It 'rolls back already applied app roots if a later directory swap fails' {
        Add-FixtureApplication
        Mock Get-Process { @() }
        $plan = New-RestorePlan @parameters -RestoreApp fixture-app
        $app = $plan.items | Where-Object kind -eq 'application'
        $lastPath = $app.roots[-1].path
        Mock Move-RestoreDirectory {
            if ($Destination -eq $lastPath -and $Source -notlike '*-previous') { throw 'Synthetic directory swap failure' }
            [IO.Directory]::Move($Source, $Destination)
        }
        $report = @(Invoke-RestorePlan $plan)
        ($report | Where-Object type -eq 'application').status | Should -Be 'failed'
        foreach ($name in @('settings', 'database')) {
            Get-Content (Join-Path $profile "AppData\Local\fixture-$name\state") | Should -Be "current $name"
            Test-Path (Join-Path $profile "AppData\Local\fixture-$name\obsolete") | Should -BeTrue
        }
    }

    It 'rejects an incomplete application selection and protects its state in parent backups' {
        $manifest.rules += @{
            success = $false; restorePath = 'C:\Users\previous\Documents\nested'
            application = @{ id = 'incomplete'; processNames = @('fixture-app') }
        }
        Save-FixtureManifest
        { New-RestorePlan @parameters -RestoreApp incomplete } | Should -Throw '*No complete application backup*'
        $plan = New-RestorePlan @parameters -Mode Overwrite
        @($plan.items | Where-Object path -eq $currentFile).Count | Should -Be 0
    }
}
