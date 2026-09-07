Describe "backup and restore static checks" {
    BeforeAll {
        $backupScriptPath = Resolve-Path (Join-Path $PSScriptRoot "..\preflight-backup.ps1")
        $restoreScriptPath = Resolve-Path (Join-Path $PSScriptRoot "..\restore-backup.ps1")
        $backupConfigPath = Resolve-Path (Join-Path $PSScriptRoot "..\config\backup.template.json")
        $backupManifestModulePath = Resolve-Path (Join-Path $PSScriptRoot "..\modules\BackupManifest.ps1")

        $backupScriptContent = Get-Content $backupScriptPath -Raw
        $restoreScriptContent = Get-Content $restoreScriptPath -Raw
        $backupConfigContent = Get-Content $backupConfigPath -Raw
        $backupManifestModuleContent = Get-Content $backupManifestModulePath -Raw
        $restoreAndModuleContent = $restoreScriptContent + "`n" + $backupManifestModuleContent
    }

    It "falls back to the backup template config" {
        $backupScriptContent | Should -Match "backup\.template\.json"
        $backupScriptContent | Should -Match "backup\.json"
    }

    It "captures repo remote and manifest data" {
        $backupScriptContent | Should -Match "remote get-url origin"
        $backupScriptContent | Should -Match "backup-manifest\.json"
        $backupScriptContent | Should -Match "restorePath"
    }

    It "backs up optional app manifest when present" {
        $backupScriptContent | Should -Match "optional-apps\.json"
    }

    It "restores in merge mode by default" {
        $restoreScriptContent | Should -Match 'Merge'
    }

    It "supports restore manifest autodetection" {
        $restoreAndModuleContent | Should -Match "Find-BackupManifest"
        $restoreAndModuleContent | Should -Match "declarative-windows-backup"
        $restoreAndModuleContent | Should -Match 'Sort-Object LastWriteTimeUtc -Descending'
    }

    It "remaps backup paths when drive letter differs from manifest" {
        $restoreScriptContent | Should -Match "Resolve-BackupSourcePath"
        $restoreScriptContent | Should -Match "manifestBackupRoot"
        $restoreScriptContent | Should -Match "actualBackupRoot"
    }

    It "defines known folders and extra paths in the template" {
        $backupConfigContent | Should -Match '"knownFolders"'
        $backupConfigContent | Should -Match '"extraPaths"'
        $backupConfigContent | Should -Match '"repoPath"'
    }

    It "reads manifest backup root metadata before remapping restore paths" {
        $restoreAndModuleContent | Should -Match 'manifest\.backup\.backupRoot'
        $restoreAndModuleContent | Should -Match 'ExpandEnvironmentVariables'
    }

    It "uses remapped source paths for both repo files and content rules" {
        $restoreScriptContent | Should -Match 'repoFileSource = Resolve-BackupSourcePath'
        $restoreScriptContent | Should -Match 'sourcePath = Resolve-BackupSourcePath'
        $restoreAndModuleContent | Should -Match 'IsPathRooted'
        $restoreScriptContent | Should -Match 'Resolve-RestoreTargetPath -Path \$rule\.restorePath -ProfileRoot \$DestinationProfileRoot -OriginalOsDrive \$originalOsDrive -RestoreTargetMap \$restoreTargetMap'
    }

    It "shares backup manifest implementation through a module" {
        $backupScriptContent | Should -Match 'BackupManifest\.ps1'
        $restoreScriptContent | Should -Match 'BackupManifest\.ps1'
        $backupManifestModuleContent | Should -Match 'function New-BackupManifest'
        $backupManifestModuleContent | Should -Match 'function Resolve-BackupSourcePath'
        $backupManifestModuleContent | Should -Match 'function Resolve-RestoreTargetPath'
    }

    It "allows successful backup manifests with empty optional collections" {
        . $backupManifestModulePath

        $manifest = New-BackupManifest `
            -Machine ([ordered]@{ computerName = "test"; userProfile = "C:\Users\test"; osDrive = "C:" }) `
            -Repo ([ordered]@{ remoteUrl = $null; name = "declarative-windows"; restorePath = "C:\Users\test\Documents\declarative-windows" }) `
            -Backup ([ordered]@{ backupRoot = "E:\backup" }) `
            -Config ([ordered]@{ sourcePath = "config\backup.template.json"; templateFallbackUsed = $true }) `
            -Rules @() `
            -RepoFiles @() `
            -Exports ([ordered]@{ wingetPath = $null }) `
            -Failures @()

        $manifest.rules | Should -BeNullOrEmpty
        $manifest.repoFiles | Should -BeNullOrEmpty
        $manifest.failures | Should -BeNullOrEmpty
    }
}
