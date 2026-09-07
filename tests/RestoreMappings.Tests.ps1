BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'modules\BackupManifest.ps1')
}

Describe 'persisted restore mappings' {
    It 'round trips normalized configuration mappings through a version 1 manifest' {
        $source = Join-Path $TestDrive 'source'
        $target = Join-Path $TestDrive 'target'
        $config = @{ restoreTargets = @{ repoPath = (Join-Path $TestDrive 'repo'); $source = $target } }
        $map = Get-RestoreTargetMap $config
        $map.Count | Should -Be 1
        $manifest = New-BackupManifest -Machine @{} -Repo @{ restorePath = $TestDrive } -Backup @{ backupRoot = $TestDrive } -Config @{} -Rules @() -RepoFiles @() -Exports @{} -Failures @() -RestoreTargets $map
        $manifestPath = Join-Path $TestDrive 'manifest.json'
        $manifest | ConvertTo-Json -Depth 8 | Set-Content $manifestPath
        $loaded = Get-Content $manifestPath -Raw | ConvertFrom-Json
        Assert-BackupManifest $loaded
        $loadedMap = Get-RestoreTargetMap $loaded
        Resolve-RestoreTargetPath -Path $source.ToUpperInvariant().Replace('\', '/') -RestoreTargetMap $loadedMap | Should -Be $target
        Resolve-RestoreTargetPath -Path (Join-Path $source 'nested\file.txt') -RestoreTargetMap $loadedMap | Should -Be (Join-Path $target 'nested\file.txt')
        Resolve-RestoreTargetPath -Path ($source + '-other') -RestoreTargetMap $loadedMap | Should -Be ($source + '-other')
    }

    It 'uses the longest explicit match before automatic profile or OS-drive remapping' {
        $source = Join-Path $TestDrive 'old-user'
        $target = Join-Path $TestDrive 'target'
        $nested = Join-Path $source 'Documents'
        $map = @{ $source = (Join-Path $TestDrive 'generic'); $nested = $target }
        Resolve-RestoreTargetPath -Path (Join-Path $nested 'file.txt') -ProfileRoot (Join-Path $TestDrive 'new-user') -OriginalProfileRoot $source -RestoreTargetMap $map |
            Should -Be (Join-Path $target 'file.txt')
        Resolve-RestoreTargetPath -Path 'Z:\data' -OriginalOsDrive 'Z:' -RestoreTargetMap @{ 'Z:\data' = $target } | Should -Be $target
    }

    It 'rejects duplicate normalized mapping keys' {
        $source = Join-Path $TestDrive 'source'
        { Get-RestoreTargetMap @{ restoreTargets = @{ $source = $TestDrive; ($source + '\') = $TestDrive } } } | Should -Throw '*Duplicate restore mapping*'
    }
}
