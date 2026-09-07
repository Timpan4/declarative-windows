BeforeAll {
    $repository = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repository 'modules\BackupManifest.ps1')
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repository 'restore-backup.ps1'), [ref]$null, [ref]$null)
    $restore = [scriptblock]::Create('[CmdletBinding(SupportsShouldProcess)]' + $ast.ParamBlock.Extent.Text + "`n" + '$PSScriptRoot = ''' + $repository.Replace("'", "''") + "'`n" + (($ast.EndBlock.Statements | ForEach-Object { $_.Extent.Text }) -join "`n"))
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repository 'preflight-backup.ps1'), [ref]$null, [ref]$null)
    $backup = [scriptblock]::Create('[CmdletBinding(SupportsShouldProcess)]' + $ast.ParamBlock.Extent.Text + "`n" + '$PSScriptRoot = ''' + $repository.Replace("'", "''") + "'`n" + (($ast.EndBlock.Statements | ForEach-Object { $_.Extent.Text }) -join "`n"))
}

Describe 'backup path and schema validation' {
    It 'rejects unsafe relative paths' -ForEach @(
        @{ Path = '..\outside.txt' }, @{ Path = 'C:\fixture\file.txt' },
        @{ Path = '\rooted.txt' }, @{ Path = 'file.txt:stream' }, @{ Path = 'sub\..\file.txt' }, @{ Path = 'sub\.. \file.txt' }
    ) {
        { Resolve-ContainedBackupPath $Path $TestDrive } | Should -Throw
    }

    It 'remaps legacy absolute sources into the selected session even while the old copy exists' {
        $old = New-Item -ItemType Directory (Join-Path $TestDrive 'old')
        $selected = New-Item -ItemType Directory (Join-Path $TestDrive 'selected')
        Set-Content (Join-Path $old 'file.txt') 'old'
        Set-Content (Join-Path $selected 'file.txt') 'selected'
        Resolve-BackupSourcePath (Join-Path $old 'file.txt') $old.FullName $selected.FullName | Should -Be (Join-Path $selected 'file.txt')
        { Resolve-BackupSourcePath ($old.FullName + '-other\file.txt') $old.FullName $selected.FullName } | Should -Throw
    }

    It 'rejects source overlap and accepts sibling paths' {
        $source = Join-Path $TestDrive 'source'
        { Assert-BackupPathsDisjoint $source $source } | Should -Throw '*overlap*'
        { Assert-BackupPathsDisjoint $source (Join-Path $source 'backup') } | Should -Throw '*overlap*'
        { Assert-BackupPathsDisjoint $source ($source + '-backup') } | Should -Not -Throw
    }

    It 'rejects junction aliases before copying' {
        $physical = New-Item -ItemType Directory (Join-Path $TestDrive 'physical')
        $alias = Join-Path $TestDrive 'alias'
        New-Item -ItemType Junction -Path $alias -Target $physical.FullName | Out-Null
        { Assert-BackupPathsDisjoint $alias (Join-Path $TestDrive 'backup') } | Should -Throw '*Reparse-point*'
        { Resolve-ContainedBackupPath 'alias\file.txt' $TestDrive } | Should -Throw '*Reparse-point*'
    }

    It 'rejects malformed configuration types and unsupported versions' -ForEach @(
        @{ Json = '{"version":2,"knownFolders":[],"extraPaths":[]}' },
        @{ Json = '{"knownFolders":{},"extraPaths":[]}' },
        @{ Json = '{"knownFolders":[],"extraPaths":[{"enabled":"false","path":"C:\\fixture"}]}' },
        @{ Json = '{"knownFolders":[],"extraPaths":[],"options":{"backupRepoFiles":"false"}}' }
    ) {
        { Assert-BackupConfiguration ($Json | ConvertFrom-Json) } | Should -Throw
    }

    It 'rejects invalid backup configuration and overlap before creating a session' -ForEach @(
        @{ Fault = 'version' }, @{ Fault = 'overlap' }
    ) {
        $destination = Join-Path $TestDrive ($Fault + '-backup')
        $config = @{ version = 1; knownFolders = @(); extraPaths = @(); options = @{ backupRepoFiles = $false } }
        if ($Fault -eq 'version') { $config.version = 2 }
        else { $config.extraPaths = @(@{ enabled = $true; path = $TestDrive; label = 'source' }) }
        $configPath = Join-Path $TestDrive ($Fault + '.json')
        $config | ConvertTo-Json -Depth 5 | Set-Content $configPath
        Mock Get-Command { $null }
        { & $backup -DestinationRoot $destination -ConfigPath $configPath -BackupName 'session' -Force } | Should -Throw
        Test-Path $destination | Should -BeFalse
    }

    It 'validates all restore entries before writing even the first valid file' -ForEach @(
        @{ Fault = 'path' }, @{ Fault = 'missing' }, @{ Fault = 'version' }, @{ Fault = 'type' }
    ) {
        $session = New-Item -ItemType Directory (Join-Path $TestDrive $Fault)
        $target = Join-Path $TestDrive ($Fault + '-target')
        Set-Content (Join-Path $session 'saved.txt') 'saved'
        $manifest = @{
            manifestVersion = 1; machine = @{}; backup = @{ backupRoot = $session.FullName }
            repo = @{ restorePath = $target }; rules = @()
            repoFiles = @(@{ relativePath = 'first.txt'; backupPath = 'saved.txt' }, @{ relativePath = 'second.txt'; backupPath = 'saved.txt' })
        }
        switch ($Fault) {
            'path' { $manifest.repoFiles[1].relativePath = '..\outside.txt' }
            'missing' { $manifest.repoFiles[1].backupPath = 'missing.txt' }
            'version' { $manifest.manifestVersion = 2 }
            'type' { $manifest.repoFiles[1].backupPath = 7 }
        }
        $manifestPath = Join-Path $session 'backup-manifest.json'
        $manifest | ConvertTo-Json -Depth 5 | Set-Content $manifestPath
        { & $restore -ManifestPath $manifestPath } | Should -Throw
        Test-Path $target | Should -BeFalse
        Test-Path (Join-Path $session 'restore-report.json') | Should -BeFalse
    }
}
