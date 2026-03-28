Describe "backup and restore static checks" {
    BeforeAll {
        $backupScriptPath = Resolve-Path (Join-Path $PSScriptRoot "..\preflight-backup.ps1")
        $restoreScriptPath = Resolve-Path (Join-Path $PSScriptRoot "..\restore-backup.ps1")
        $backupConfigPath = Resolve-Path (Join-Path $PSScriptRoot "..\config\backup.template.json")

        $backupScriptContent = Get-Content $backupScriptPath -Raw
        $restoreScriptContent = Get-Content $restoreScriptPath -Raw
        $backupConfigContent = Get-Content $backupConfigPath -Raw
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
        $restoreScriptContent | Should -Match "Find-BackupManifest"
        $restoreScriptContent | Should -Match "declarative-windows-backup"
        $restoreScriptContent | Should -Match 'Sort-Object LastWriteTimeUtc -Descending'
    }

    It "defines known folders and extra paths in the template" {
        $backupConfigContent | Should -Match '"knownFolders"'
        $backupConfigContent | Should -Match '"extraPaths"'
        $backupConfigContent | Should -Match '"repoPath"'
    }
}
