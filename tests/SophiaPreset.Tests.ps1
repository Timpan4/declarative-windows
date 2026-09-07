Describe 'selected Sophia preset execution' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'bootstrap.ps1'), [ref]$null, [ref]$null)
        $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-SophiaPreset' }, $true)
        # Bind the extracted function to the actual bootstrap path, without running bootstrap.
        $functionText = $definition.Extent.Text.Replace('$PSScriptRoot', "'" + $repoRoot.Replace("'", "''") + "'")
        . ([scriptblock]::Create($functionText))
        $step = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.IfStatementAst] -and $node.Extent.Text.StartsWith('if ($OptionalAppsOnly)') -and $node.Extent.Text.Contains('Invoke-SophiaPreset -FrameworkRoot') }, $true)
        $runSophiaStep = [scriptblock]::Create($step.Extent.Text)
        function Write-Log { param($Message, $Level) }
        function Add-SummaryItem { param($Step, $Status, $Message) }
        function Add-FailedItem { param($Category, $Item, $Reason) }
        function Set-StepState { param($StepId, $Status, $Message) }
        function Get-SophiaScript { $SophiaScript }
    }

    BeforeEach {
        $fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $SophiaDir = Join-Path $fixture 'framework'
        $SophiaScript = Join-Path $SophiaDir 'Sophia.ps1'
        $SophiaPreset = Join-Path $fixture 'selected.ps1'
        $SophiaMarker = Join-Path $fixture 'sophia.completed'
        $SophiaVersion = '7.3.0'
        $OptionalAppsOnly = $false
        $DryRun = $false
        $Force = $false
        $stepId = 'sophia'
        New-Item -ItemType Directory -Path (Join-Path $SophiaDir 'Module\Manifest'), (Join-Path $SophiaDir 'Module\Private') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $SophiaDir 'Module\Manifest\SophiaScript.psd1') -Value "@{ RootModule = '..\Sophia.psm1'; ModuleVersion = '7.3.0' }"
        Set-Content -LiteralPath (Join-Path $SophiaDir 'Module\Sophia.psm1') -Value 'function CustomAction { Set-Content -LiteralPath (Join-Path $env:DW_SOPHIA_FIXTURE ''custom-ran'') -Value ''selected'' }'
        Set-Content -LiteralPath (Join-Path $SophiaDir 'Module\Private\InitialActions.ps1') -Value 'function InitialActions { Set-Content -LiteralPath (Join-Path $env:DW_SOPHIA_FIXTURE ''initialized'') -Value ''yes'' }'
        Set-Content -LiteralPath $SophiaScript -Value 'throw ''Stock defaults must never run'''
        Set-Content -LiteralPath $SophiaPreset -Value 'CustomAction'
        $previousFixture = $env:DW_SOPHIA_FIXTURE
        $env:DW_SOPHIA_FIXTURE = $fixture
        Mock Set-StepState {}
    }

    AfterEach { $env:DW_SOPHIA_FIXTURE = $previousFixture }

    It 'initializes the framework and runs only selected actions in Windows PowerShell' {
        . $runSophiaStep
        Get-Content -LiteralPath (Join-Path $fixture 'initialized') | Should -Be 'yes'
        Get-Content -LiteralPath (Join-Path $fixture 'custom-ran') | Should -Be 'selected'
        Get-Content -LiteralPath $SophiaMarker | Should -Be ('custom-preset-v1:7.3.0:' + (Get-FileHash $SophiaPreset).Hash)
        Should -Invoke Set-StepState -Times 1 -ParameterFilter { $Status -eq 'done' }
    }

    It 'does not mark completion after framework early exit with a zero exit code' {
        Set-Content -LiteralPath (Join-Path $SophiaDir 'Module\Private\InitialActions.ps1') -Value 'function InitialActions { $Global:Failed = $true; exit }'
        . $runSophiaStep
        Test-Path -LiteralPath $SophiaMarker | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fixture 'custom-ran') | Should -BeFalse
        Should -Invoke Set-StepState -Times 1 -ParameterFilter { $Status -eq 'failed' }
    }

    It 'does not mark completion after a preset error' {
        Set-Content -LiteralPath $SophiaPreset -Value 'Write-Error ''Synthetic preset failure'''
        . $runSophiaStep
        Test-Path -LiteralPath $SophiaMarker | Should -BeFalse
        Should -Invoke Set-StepState -Times 1 -ParameterFilter { $Status -eq 'failed' }
    }

    It 'reruns legacy completion markers and skips a proven custom preset on the next run' {
        Set-Content -LiteralPath $SophiaMarker -Value (Get-FileHash $SophiaPreset).Hash
        . $runSophiaStep
        Test-Path -LiteralPath (Join-Path $fixture 'custom-ran') | Should -BeTrue
        Mock Invoke-SophiaPreset { throw 'Completed custom preset must be skipped' }
        . $runSophiaStep
        Should -Invoke Invoke-SophiaPreset -Times 0 -Exactly
    }
}
