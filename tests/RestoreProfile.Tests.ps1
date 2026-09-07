Describe 'restore profile mapping' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        . (Join-Path $repoRoot 'modules\BackupManifest.ps1')
    }

    It 'maps the recorded profile root and descendants with case and separator handling' {
        $destination = Join-Path $TestDrive 'new-user'
        foreach ($path in @('C:\Users\old-user', 'c:/users/OLD-user/')) {
            Resolve-RestoreTargetPath -Path $path -ProfileRoot $destination -OriginalProfileRoot 'C:\Users\old-user\' |
                Should -Be $destination
        }
        Resolve-RestoreTargetPath -Path 'c:/users/OLD-user/Documents/file.txt' -ProfileRoot $destination -OriginalProfileRoot 'C:\Users\old-user' |
            Should -Be (Join-Path $destination 'Documents\file.txt')
    }

    It 'preserves unchanged profiles, boundary lookalikes and unrelated redirected folders' {
        $profile = Join-Path $TestDrive 'user'
        foreach ($path in @((Join-Path $profile 'Documents'), ($profile + '-other\Documents'), (Join-Path $TestDrive 'redirected\Documents'))) {
            Resolve-RestoreTargetPath -Path $path -ProfileRoot $profile -OriginalProfileRoot $profile | Should -Be $path
        }
    }

    It 'retains explicit mappings for redirected known folders and the legacy profile fallback' {
        $redirected = Join-Path $TestDrive 'redirected'
        $destination = Join-Path $TestDrive 'new-user'
        Resolve-RestoreTargetPath -Path (Join-Path $redirected 'Documents') -ProfileRoot $destination -OriginalProfileRoot 'C:\Users\old-user' -RestoreTargetMap @{ $redirected = $destination } |
            Should -Be (Join-Path $destination 'Documents')
        Resolve-RestoreTargetPath -Path (Join-Path $env:USERPROFILE 'Documents') -ProfileRoot $destination |
            Should -Be (Join-Path $destination 'Documents')
    }

    It 'restores serialized content and repo destinations into the requested profile' {
        $fixtureRepo = Join-Path $TestDrive 'fixture'
        $session = Join-Path $TestDrive 'session'
        $oldProfile = Join-Path $TestDrive 'old-user'
        $newProfile = Join-Path $TestDrive 'new-user'
        New-Item -ItemType Directory -Path $fixtureRepo, (Join-Path $session 'content'), (Join-Path $session 'repo-files') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot 'modules') -Destination $fixtureRepo -Recurse
        # Run only synthetic copies without requiring elevation on the developer's OS.
        (Get-Content -LiteralPath (Join-Path $repoRoot 'restore-backup.ps1') -Raw) -replace '(?m)^#Requires -RunAsAdministrator\r?\n', '' |
            Set-Content -LiteralPath (Join-Path $fixtureRepo 'restore-backup.ps1')
        Set-Content -LiteralPath (Join-Path $session 'content\example.txt') -Value 'user content'
        Set-Content -LiteralPath (Join-Path $session 'repo-files\apps.json') -Value '{}'
        @{
            machine = @{ userProfile = $oldProfile; osDrive = $env:SystemDrive }
            backup = @{ backupRoot = $session }
            repo = @{ restorePath = (Join-Path $oldProfile 'repo') }
            repoFiles = @(@{ relativePath = 'apps.json'; backupPath = 'repo-files\apps.json' })
            rules = @(@{ success = $true; backupPath = 'content'; restorePath = (Join-Path $oldProfile 'Documents') })
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $session 'backup-manifest.json')

        & (Join-Path $fixtureRepo 'restore-backup.ps1') -ManifestPath (Join-Path $session 'backup-manifest.json') -DestinationProfileRoot $newProfile

        Get-Content -LiteralPath (Join-Path $newProfile 'Documents\example.txt') | Should -Be 'user content'
        Get-Content -LiteralPath (Join-Path $newProfile 'repo\apps.json') | Should -Be '{}'
        Test-Path -LiteralPath $oldProfile | Should -BeFalse
    }
}
