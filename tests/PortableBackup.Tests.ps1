Describe "portable backup paths" {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $backupPath = Join-Path $repoRoot "preflight-backup.ps1"
        $backupAst = [System.Management.Automation.Language.Parser]::ParseFile($backupPath, [ref]$null, [ref]$null)
        foreach ($name in @('Get-RelativePath', 'Test-IsSystemDrivePath', 'Assert-DestinationRoot')) {
            $definition = $backupAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            . ([scriptblock]::Create($definition.Extent.Text))
        }
    }

    It "treats the relative-path base as a directory with or without a trailing separator" {
        $session = Join-Path $TestDrive 'session with spaces'
        $file = Join-Path $session 'repo-files\apps.json'
        Get-RelativePath -Path $file -BasePath $session | Should -Be 'repo-files\apps.json'
        Get-RelativePath -Path $file -BasePath ($session + '\') | Should -Be 'repo-files\apps.json'
    }

    It "rejects normalized system-drive destinations before creating directories" {
        $originalSystemDrive = $env:SystemDrive
        try {
            Mock New-Item { throw 'Unexpected directory creation' }
            $Force = $false
            foreach ($systemDrive in @('C:', 'C:\', 'c:/')) {
                $env:SystemDrive = $systemDrive
                foreach ($destination in @('C:\backup', 'c:/backup', 'C:\temp\..\backup')) {
                    Test-IsSystemDrivePath -Path $destination | Should -BeTrue
                    { Assert-DestinationRoot -Path $destination } | Should -Throw '*unless -Force is specified*'
                }
            }
            Should -Invoke New-Item -Times 0 -Exactly
        }
        finally { $env:SystemDrive = $originalSystemDrive }
    }

    It "allows a non-system drive and preserves the explicit Force override" {
        $originalSystemDrive = $env:SystemDrive
        try {
            $env:SystemDrive = 'C:'
            Mock Test-Path { $true }
            $Force = $false
            Test-IsSystemDrivePath -Path 'D:\backup' | Should -BeFalse
            { Assert-DestinationRoot -Path 'D:\backup' } | Should -Not -Throw
            $Force = $true
            { Assert-DestinationRoot -Path 'C:\backup' } | Should -Not -Throw
        }
        finally { $env:SystemDrive = $originalSystemDrive }
    }

    It "backs up and restores content and repo files after moving the session" {
        $fixtureRepo = Join-Path $TestDrive 'fixture-repo'
        $source = Join-Path $TestDrive 'content'
        $destination = Join-Path $TestDrive 'backup'
        $movedSession = Join-Path $TestDrive 'moved session'
        $restoredRepo = Join-Path $TestDrive 'restored-repo'
        $restoredContent = Join-Path $TestDrive 'restored-content'
        New-Item -ItemType Directory -Path $fixtureRepo, $source, (Join-Path $fixtureRepo 'config') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot 'modules') -Destination $fixtureRepo -Recurse
        # Only synthetic fixtures are used. Remove elevation requirements in these test copies.
        foreach ($scriptName in @('preflight-backup.ps1', 'restore-backup.ps1')) {
            $scriptText = Get-Content -LiteralPath (Join-Path $repoRoot $scriptName) -Raw
            $scriptText -replace '(?m)^#Requires -RunAsAdministrator\r?\n', '' |
                Set-Content -LiteralPath (Join-Path $fixtureRepo $scriptName)
        }
        Set-Content -LiteralPath (Join-Path $source 'example.txt') -Value 'portable content'
        Set-Content -LiteralPath (Join-Path $fixtureRepo 'apps.json') -Value '{"packages":[]}'
        @{
            knownFolders = @()
            extraPaths = @(@{ enabled = $true; path = $source; label = 'example'; required = $true })
            restoreTargets = @{ repoPath = $restoredRepo; $source = $restoredContent }
            options = @{ backupRepoFiles = $true }
            excludePatterns = @()
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $fixtureRepo 'config\backup.template.json')
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget' -or $Name -eq 'git' }

        & (Join-Path $fixtureRepo 'preflight-backup.ps1') -DestinationRoot $destination -BackupName 'session' -Force
        $session = Join-Path $destination 'declarative-windows-backup\session'
        $manifest = Get-Content -LiteralPath (Join-Path $session 'backup-manifest.json') -Raw | ConvertFrom-Json
        $manifest.rules[0].backupPath | Should -Be 'files\extra-example'
        $manifest.repoFiles[0].backupPath | Should -Be 'repo-files\apps.json'
        $manifest.restoreTargets.$source | Should -Be $restoredContent
        Move-Item -LiteralPath $session -Destination $movedSession
        Remove-Item -LiteralPath (Join-Path $source 'example.txt')

        & (Join-Path $fixtureRepo 'restore-backup.ps1') -ManifestPath (Join-Path $movedSession 'backup-manifest.json')
        Get-Content -LiteralPath (Join-Path $restoredContent 'example.txt') -Raw | Should -Be "portable content`r`n"
        Get-Content -LiteralPath (Join-Path $restoredRepo 'apps.json') -Raw | Should -Be "{`"packages`":[]}`r`n"
    }
}
