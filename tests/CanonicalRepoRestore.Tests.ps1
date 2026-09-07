Describe "canonical repo file restore" {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        . (Join-Path $repoRoot 'modules\BackupManifest.ps1')
        $stateText = Get-Content -LiteralPath (Join-Path $repoRoot 'modules\BootstrapRun.ps1') -Raw -Encoding UTF8
        $stateAst = [System.Management.Automation.Language.Parser]::ParseInput($stateText, [ref]$null, [ref]$null)
        foreach ($name in @('Save-State', 'Set-StepState', 'Should-RunStep', 'Add-SummaryItem')) {
            $definition = $stateAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        $bootstrapText = Get-Content -LiteralPath (Join-Path $repoRoot 'bootstrap.ps1') -Raw -Encoding UTF8
        $bootstrapAst = [System.Management.Automation.Language.Parser]::ParseInput($bootstrapText, [ref]$null, [ref]$null)
        foreach ($name in @('Restore-RepoFilesFromManifest', 'Get-BackupManifestData', 'Ensure-CanonicalRepo')) {
            $definition = $bootstrapAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        $repoStep = $bootstrapAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.IfStatementAst] -and
            $node.Extent.Text.StartsWith('if ($OptionalAppsOnly)') -and
            $node.Extent.Text.Contains('Ensure-CanonicalRepo -Manifest $manifest')
        }, $true)
        $runRepoStep = [scriptblock]::Create($repoStep.Extent.Text)
        function Write-Log { param($Message, $Level) }
    }

    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $CanonicalRepoPath = Join-Path $caseRoot 'canonical'
        $session = Join-Path $caseRoot 'selected-session'
        New-Item -ItemType Directory -Path (Join-Path $session 'repo-files') -Force | Out-Null
        $script:BackupManifestPath = Join-Path $session 'backup-manifest.json'
        $fixtureManifest = [pscustomobject]@{
            backup = @{ backupRoot = (Join-Path $TestDrive 'old-session') }
            repoFiles = @([pscustomobject]@{ relativePath = 'apps.json'; backupPath = 'repo-files\apps.json' })
        }
        $fixtureManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:BackupManifestPath
        Set-Content -LiteralPath (Join-Path $session 'repo-files\apps.json') -Value 'personal configuration'
        Mock Write-Log {}
    }

    It "restores a relative source from the selected manifest independently of the working directory" {
        $manifest = Get-Content -LiteralPath $script:BackupManifestPath -Raw | ConvertFrom-Json
        Restore-RepoFilesFromManifest -Manifest $manifest | Should -BeTrue
        Get-Content -LiteralPath (Join-Path $CanonicalRepoPath 'apps.json') | Should -Be 'personal configuration'
    }

    It "remaps a moved legacy absolute source through the shared resolver" {
        $fixtureManifest.repoFiles[0].backupPath = Join-Path $fixtureManifest.backup.backupRoot 'repo-files\apps.json'
        Restore-RepoFilesFromManifest -Manifest $fixtureManifest | Should -BeTrue
        Get-Content -LiteralPath (Join-Path $CanonicalRepoPath 'apps.json') | Should -Be 'personal configuration'
    }

    It "returns failure when any listed file is missing even if another file restores" {
        $fixtureManifest.repoFiles = @(
            [pscustomobject]@{ relativePath = 'missing.json'; backupPath = 'repo-files\missing.json' }
            $fixtureManifest.repoFiles[0]
        )
        Restore-RepoFilesFromManifest -Manifest $fixtureManifest | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $CanonicalRepoPath 'apps.json') | Should -Be 'personal configuration'
        Should -Invoke Write-Log -Times 1 -ParameterFilter { $Level -eq 'WARNING' -and $Message -like '*missing.json*' }
    }

    It "returns failure and logs a copy error" {
        Mock Copy-Item { Write-Error 'Synthetic copy failure' }
        Restore-RepoFilesFromManifest -Manifest $fixtureManifest | Should -BeFalse
        Should -Invoke Write-Log -Times 1 -ParameterFilter { $Level -eq 'WARNING' -and $Message -like '*Synthetic copy failure*' }
    }

    It "fails when the selected manifest cannot be located" {
        Restore-RepoFilesFromManifest -Manifest $fixtureManifest -ManifestPath (Join-Path $TestDrive 'missing-manifest.json') | Should -BeFalse
        Test-Path -LiteralPath $CanonicalRepoPath | Should -BeFalse
    }

    It "accepts an empty personal file list but rejects a missing manifest" {
        $fixtureManifest.repoFiles = @()
        Restore-RepoFilesFromManifest -Manifest $fixtureManifest | Should -BeTrue
        Restore-RepoFilesFromManifest -Manifest $null | Should -BeFalse
    }

    It "keeps incomplete repo restoration retryable and marks it done after a successful retry" {
        $stepId = 'repo'
        $OptionalAppsOnly = $false
        $DryRun = $false
        $Force = $false
        $SetupState = @{ steps = [ordered]@{} }
        $StateFile = Join-Path $TestDrive 'state.json'
        $SummaryItems = New-Object 'System.Collections.Generic.List[object]'
        Mock Get-BackupManifestData { $fixtureManifest }
        Mock Ensure-CanonicalRepo { $true }
        $fixtureManifest.repoFiles[0].backupPath = 'repo-files\missing.json'

        . $runRepoStep
        $SetupState.steps.repo.status | Should -Be 'failed'
        (Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json).steps.repo.status | Should -Be 'failed'
        $SummaryItems[0].Status | Should -Be 'FAIL'
        Should-RunStep -StepId 'repo' | Should -BeTrue

        $fixtureManifest.repoFiles[0].backupPath = 'repo-files\apps.json'
        . $runRepoStep
        $SetupState.steps.repo.status | Should -Be 'done'
        $SummaryItems[1].Status | Should -Be 'OK'
        Should-RunStep -StepId 'repo' | Should -BeFalse
    }
}
