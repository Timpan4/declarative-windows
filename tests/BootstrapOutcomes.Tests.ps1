BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'modules/BootstrapRun.ps1')
    $tokens = $null
    $parseErrors = $null
    $bootstrapAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'bootstrap.ps1'), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors) { throw ($parseErrors | Out-String) }
    foreach ($name in @('Set-RegistryValueSafe', 'Remove-ProvisionedAppIfPresent', 'Disable-OptionalFeatureIfPresent', 'Invoke-PostInstallTweaks')) {
        $definition = $bootstrapAst.Find({ param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $false)
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    function Write-Log { param($Message, $Level) }
}

Describe 'Bootstrap run outcomes and reports' {
    BeforeEach {
        $StateFile = Join-Path $TestDrive 'state.json'
        $FailedInstallsLog = Join-Path $TestDrive 'failed-installs.log'
        $ProgressFile = Join-Path $TestDrive 'progress.json'
        $script:ProgressState = @{ phase = ''; status = ''; currentPackage = ''; packageIndex = 0; packageTotal = 0; mode = ''; lastUpdated = $null }
        $RunStartedAt = (Get-Date).ToString('o')
        $RunStepIds = @('winget', 'repo', 'registry')
        $SetupState = Initialize-State -StatePath (Join-Path $TestDrive 'unused.json') -StepIds @('winget', 'repo', 'registry', 'optionalWinget', 'summary')
        $SummaryItems = [Collections.Generic.List[object]]::new()
        $FailedItems = [Collections.Generic.List[object]]::new()
        $OptionalAppsOnly = $false
        $DryRun = $false
        foreach ($id in $RunStepIds) {
            $SetupState.steps[$id].status = 'done'
            $SetupState.steps[$id].lastRun = '2026-01-01T00:00:00.0000000Z'
            $SetupState.steps[$id].message = 'Previously applied'
        }
        $SetupState.steps.summary.status = 'done'
    }

    It 'reports a state-only failure consistently and replaces stale reports after retry' {
        Set-StepState -StepId winget -Status failed -Message 'Network unavailable'
        $result = Complete-BootstrapRun -DesktopPath $TestDrive
        $result.ExitCode | Should -Be 1
        $result.Status | Should -Be 'Failed'
        (Get-Content $ProgressFile -Raw | ConvertFrom-Json).phase | Should -Be $result.Status
        Get-Content (Join-Path $TestDrive 'Setup Summary.txt') -Raw | Should -Match 'Network unavailable'
        Get-Content (Join-Path $TestDrive 'Failed Installs.txt') -Raw | Should -Match 'Network unavailable'
        $result.Records | Where-Object Step -EQ repo | Select-Object -ExpandProperty Origin | Should -Be 'Previous result'

        $RunStartedAt = (Get-Date).ToString('o')
        Set-StepState -StepId winget -Status done -Message 'Installed'
        $result = Complete-BootstrapRun -DesktopPath $TestDrive
        $result.Status | Should -Be 'Completed'
        $result.ExitCode | Should -Be 0
        $SetupState.steps.repo.status | Should -Be 'done'
        $report = Get-Content (Join-Path $TestDrive 'Failed Installs.txt') -Raw
        $report | Should -Not -Match 'Network unavailable'
        $report | Should -Match ([regex]::Escape($RunStartedAt))
    }

    It 'includes repo and registry failures even without detailed FailedItems' {
        Set-StepState -StepId repo -Status failed -Message 'Clone failed'
        Set-StepState -StepId registry -Status failed -Message 'Registry script missing'
        $result = Complete-BootstrapRun -DesktopPath $TestDrive
        $result.ExitCode | Should -Be 1
        $report = Get-Content $FailedInstallsLog -Raw
        $report | Should -Match 'Clone failed'
        $report | Should -Match 'Registry script missing'
        $report | Should -Not -Match 'Everything installed successfully'
    }

    It 'refreshes optional-only reports while preserving core failures as history' {
        $SetupState.steps.winget.status = 'failed'
        $SetupState.steps.winget.message = 'Previous core failure'
        $OptionalAppsOnly = $true
        $RunStepIds = @('optionalWinget')
        Set-StepState -StepId optionalWinget -Status done -Message 'Optional app installed'
        $result = Complete-BootstrapRun -DesktopPath $TestDrive
        $result.ExitCode | Should -Be 0
        $report = Get-Content (Join-Path $TestDrive 'Setup Summary.txt') -Raw
        $report | Should -Match 'Optional apps only'
        $report | Should -Match 'Previous core failure.*Previous result; Not selected this run'
        $report | Should -Match 'Optional app installed.*Current run; Included'
        $SetupState.steps.winget.status | Should -Be 'failed'
    }

    It 'distinguishes unverified installs from package failures and optional skips' {
        $SetupState.steps.optionalWinget.status = 'pending'
        Set-StepState -StepId winget -Status unverified -Message 'Package verification pending'
        Add-FailedItem -Category 'WinGet Verification' -Item 'Example.App' -Reason 'Not verified' -Status WARN
        $result = Get-BootstrapRunResult
        $result.Status | Should -Be 'Completed with warnings'
        $result.ExitCode | Should -Be 0
        Add-FailedItem -Category WinGet -Item 'Example.Broken' -Reason 'Installer failed'
        $result = Get-BootstrapRunResult
        $result.Status | Should -Be 'Failed'
        $result.ExitCode | Should -Be 1
    }

    It 'returns failure when a required step is still pending or reporting fails' {
        Set-StepState -StepId registry -Status pending -Message 'Not attempted'
        (Get-BootstrapRunResult).ExitCode | Should -Be 1
        Set-StepState -StepId registry -Status done -Message 'Applied'
        Mock Write-SummaryReport { throw 'Access denied' }
        $result = Complete-BootstrapRun -DesktopPath $TestDrive
        $result.ExitCode | Should -Be 1
        (Get-Content $ProgressFile -Raw | ConvertFrom-Json).phase | Should -Be 'Failed'
        ($result.Problems.Reason -join ';') | Should -Match 'Access denied'
        Get-Content $FailedInstallsLog -Raw | Should -Match 'Result: Failed'
    }

    It 'writes fatal prerequisite failures into both reports' {
        $result = Complete-BootstrapRun -DesktopPath $TestDrive -FailureMessage 'Prerequisite unavailable'
        $result.ExitCode | Should -Be 1
        Get-Content $FailedInstallsLog -Raw | Should -Match 'Prerequisite unavailable'
        Get-Content (Join-Path $TestDrive 'Setup Summary.txt') -Raw | Should -Match 'Result: Failed'
    }

    It 'does not rewrite reports during a preview' {
        $DryRun = $true
        Mock Write-SummaryReport { throw 'Must not write' }
        Mock Write-FailedInstallsReport { throw 'Must not write' }
        (Complete-BootstrapRun -DesktopPath $TestDrive).Status | Should -Be 'Preview'
        Should -Invoke Write-SummaryReport -Times 0 -Exactly
        Should -Invoke Write-FailedInstallsReport -Times 0 -Exactly
    }

    It 'connects the orchestrator exit to the aggregate result' {
        $bootstrapAst.EndBlock.Statements[-1].Extent.Text | Should -Be 'exit $runResult.ExitCode'
        $bootstrapAst.Extent.Text | Should -Not -Match 'Skipping summary report \(already completed\)'
    }
}

Describe 'Post-install operation failures' {
    BeforeEach {
        $FailedItems = [Collections.Generic.List[object]]::new()
    }

    It 'makes registry provider writes terminating even with Continue preference' {
        $ErrorActionPreference = 'Continue'
        Mock Test-Path { $false }
        Mock New-Item { Write-Error 'Registry denied' }
        { Set-RegistryValueSafe -Path 'Registry::HKEY_USERS\.DEFAULT\Synthetic' -Name Flags -Value 10 -Type DWord } | Should -Throw '*Registry denied*'
    }

    It 'does not mark tweaks done after a registry write fails' {
        Mock Remove-ProvisionedAppIfPresent { $true }
        Mock Disable-OptionalFeatureIfPresent { $true }
        Mock Set-RegistryValueSafe { throw 'Registry denied' }
        Mock Get-Process { }
        (Invoke-PostInstallTweaks) | Should -BeFalse
        $FailedItems.Reason | Should -Contain 'Registry denied'
    }

    It 'uses the provider-qualified default-user hive without an HKU drive' {
        Mock Remove-ProvisionedAppIfPresent { $true }
        Mock Disable-OptionalFeatureIfPresent { $true }
        Mock Set-RegistryValueSafe { }
        Mock Get-Process { }
        (Invoke-PostInstallTweaks) | Should -BeTrue
        Should -Invoke Set-RegistryValueSafe -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Accessibility\StickyKeys'
        }
    }
}
