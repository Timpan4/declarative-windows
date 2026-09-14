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
        foreach ($name in @('Get-BackupManifestData', 'Ensure-CanonicalRepo')) {
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
        function Update-SetupToolPath { }
    }

    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $CanonicalRepoPath = Join-Path $caseRoot 'canonical'
        $SetupPath = Join-Path $caseRoot 'staged'
        $ConfigRoot = $SetupPath
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

    It "preserves repo edits when running with non-staged configuration" {
        $ConfigRoot = $CanonicalRepoPath
        $OptionalAppsOnly = $false
        New-Item -ItemType Directory -Path $CanonicalRepoPath -Force | Out-Null
        $editedPath = Join-Path $CanonicalRepoPath 'apps.json'
        Set-Content -LiteralPath $editedPath -Value 'edited configuration'
        Mock Get-BackupManifestData { throw 'Must not load a backup for a repo configuration rerun' }
        . $runRepoStep
        Get-Content -LiteralPath $editedPath | Should -Be 'edited configuration'
        Should -Invoke Get-BackupManifestData -Times 0
    }

    It 'refreshes tool discovery before cloning with newly installed Git' {
        $script:pathRefreshed = $false
        $fakeGit = Join-Path $TestDrive 'git.ps1'
        'New-Item -ItemType Directory -Path (Join-Path $args[2] ".git") -Force | Out-Null; $global:LASTEXITCODE = 0' | Set-Content $fakeGit
        Mock Update-SetupToolPath { $script:pathRefreshed = $true }
        Mock Get-Command {
            if ($script:pathRefreshed) { [pscustomobject]@{ Source = $fakeGit } }
        } -ParameterFilter { $Name -eq 'git' }
        Ensure-CanonicalRepo -Manifest ([pscustomobject]@{ repo = @{ remoteUrl = 'https://example.invalid/repo' } }) | Should -BeTrue
        Should -Invoke Update-SetupToolPath -Times 1 -Exactly
        Test-Path -LiteralPath (Join-Path $CanonicalRepoPath '.git') | Should -BeTrue
    }

    It "clones without applying backup settings over current configuration" {
        $stepId = 'repo'
        $OptionalAppsOnly = $false
        $DryRun = $false
        $Force = $false
        $SetupState = @{ steps = [ordered]@{} }
        $StateFile = Join-Path $TestDrive 'state.json'
        $SummaryItems = New-Object 'System.Collections.Generic.List[object]'
        New-Item -ItemType Directory -Path $CanonicalRepoPath -Force | Out-Null
        $currentFile = Join-Path $CanonicalRepoPath 'apps.json'
        Set-Content $currentFile 'current settings'
        Mock Get-BackupManifestData { $fixtureManifest }
        Mock Ensure-CanonicalRepo { $true }
        Mock Copy-Item { throw 'Bootstrap must not copy backup settings' }
        . $runRepoStep
        Get-Content $currentFile | Should -Be 'current settings'
        $SetupState.steps.repo.status | Should -Be 'done'
        $SummaryItems[0].Message | Should -Match 'explicit restore'
        Should -Invoke Copy-Item -Times 0 -Exactly
    }
}