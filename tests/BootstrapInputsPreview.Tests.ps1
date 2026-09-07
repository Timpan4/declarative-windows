BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $bootstrapPath = Join-Path $repoRoot 'bootstrap.ps1'
    $tokens = $null
    $parseErrors = $null
    $bootstrapAst = [Management.Automation.Language.Parser]::ParseFile($bootstrapPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors) { throw ($parseErrors | Out-String) }
    $main = $bootstrapAst.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] }
    foreach ($name in @('Write-Log', 'New-DesktopShortcut', 'Get-RunBootstrapTarget')) {
        $definition = $bootstrapAst.Find({ param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $false)
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    . (Join-Path $repoRoot 'modules/BootstrapRun.ps1')
    . (Join-Path $repoRoot 'modules/WinGetInstall.ps1')
    $registryStep = [scriptblock]::Create(($main.Body.Statements | Where-Object { $_.Extent.Text.StartsWith('if ($OptionalAppsOnly)') -and $_.Extent.Text.Contains('Step 5:') }).Extent.Text)
    $optionalShortcutStep = [scriptblock]::Create(($main.Body.Statements | Where-Object { $_.Extent.Text.StartsWith('if ($OptionalAppsOnly)') -and $_.Extent.Text.Contains('Step 8:') }).Extent.Text)
    $optionalAppsStep = [scriptblock]::Create(($main.Body.Statements | Where-Object { $_.Extent.Text.StartsWith('if (-not (Should-RunStep') -and $_.Extent.Text.Contains('Step 9:') }).Extent.Text)
}

Describe 'Missing bootstrap inputs' {
    BeforeEach {
        $DryRun = $false
        $Force = $false
        $OptionalAppsOnly = $false
        $StateFile = Join-Path $TestDrive 'state.json'
        $SetupState = Initialize-State -StatePath (Join-Path $TestDrive 'unused.json') -StepIds @('winget', 'registry', 'optionalShortcut', 'optionalWinget')
        $SummaryItems = [Collections.Generic.List[object]]::new()
        $FailedItems = [Collections.Generic.List[object]]::new()
        $RunStepIds = @('winget', 'registry', 'optionalShortcut')
        $RunStartedAt = (Get-Date).ToString('o')
        $ConfigRoot = $TestDrive
        $desktopPath = $TestDrive
        $RegistryConfig = Join-Path $TestDrive 'registry.json'
        $RegistryScript = Join-Path $TestDrive 'apply-registry.ps1'
        $OptionalAppsJson = Join-Path $TestDrive "optional-apps-$([guid]::NewGuid()).json"
        Mock Write-Log { }
        Mock Update-SetupProgress { }
        Mock Test-WingetPackageInstalled { $true }
        Mock Invoke-WingetPackageInstall { throw 'Unexpected installer' }
        Mock New-DesktopShortcut { }
        Mock Get-RunBootstrapTarget { Join-Path $TestDrive 'bootstrap.ps1' }
    }

    It 'fails missing automatic apps and reconciles them when added on an ordinary rerun' {
        $manifestPath = Join-Path $TestDrive 'apps.json'
        $markerPath = Join-Path $TestDrive 'winget.completed'
        $installArgs = @{ ManifestPath = $manifestPath; StepId = 'winget'; SummaryStep = 'WinGet'; MarkerPath = $markerPath; ManifestLabel = 'apps.json'; MissingManifestMessage = 'apps.json not found' }
        Invoke-WingetManifestInstall @installArgs | Should -BeFalse
        $SetupState.steps.winget.status | Should -Be 'failed'
        Test-Path $markerPath | Should -BeFalse
        Should -Invoke Test-WingetPackageInstalled -Times 0 -Exactly

        '{"Sources":[{"Packages":[{"PackageIdentifier":"Example.App"}]}]}' | Set-Content $manifestPath
        $SetupState = Initialize-State -StatePath $StateFile -StepIds @('winget')
        Should-RunStep winget | Should -BeTrue
        Invoke-WingetManifestInstall @installArgs | Should -BeTrue
        $SetupState.steps.winget.status | Should -Be 'done'
        Should -Invoke Test-WingetPackageInstalled -Times 1 -Exactly
    }

    It 'skips absent registry configuration and applies it once supplied' {
        $stepId = 'registry'
        . $registryStep
        $SetupState.steps.registry.status | Should -Be 'skipped'
        $SummaryItems[-1].Status | Should -Be 'SKIP'
        '{}' | Set-Content $RegistryConfig
        '[pscustomobject]@{ Failed = 0 }' | Set-Content $RegistryScript
        $SetupState = Initialize-State -StatePath $StateFile -StepIds @('registry')
        . $registryStep
        $SetupState.steps.registry.status | Should -Be 'done'
        $SetupState.steps.registry.message | Should -Be 'Registry fallback applied'
    }

    It 'retries absent optional shortcuts, including old incorrectly completed records' {
        $stepId = 'optionalShortcut'
        Set-StepState -StepId $stepId -Status done -Message 'optional-apps.json not found'
        . $optionalShortcutStep
        $SetupState.steps.optionalShortcut.status | Should -Be 'skipped'
        Should -Invoke New-DesktopShortcut -Times 0 -Exactly
        '{}' | Set-Content $OptionalAppsJson
        $SetupState = Initialize-State -StatePath $StateFile -StepIds @('optionalShortcut')
        . $optionalShortcutStep
        $SetupState.steps.optionalShortcut.status | Should -Be 'done'
        Should -Invoke New-DesktopShortcut -Times 1 -Exactly
        Should-RunStep optionalShortcut | Should -BeFalse
    }

    It 'fails an explicitly requested optional installation when its manifest is missing' {
        $stepId = 'optionalWinget'
        $OptionalAppsOnly = $true
        $RunStepIds = @('optionalWinget')
        . $optionalAppsStep
        $SetupState.steps.optionalWinget.status | Should -Be 'failed'
        (Get-BootstrapRunResult).ExitCode | Should -Be 1
        Should-RunStep optionalWinget | Should -BeTrue
    }
}

Describe 'Bootstrap dry-run isolation in Windows PowerShell' {
    It 'preserves all saved results with <Label>' -ForEach @(
        @{ Label = 'DryRun'; ExtraArgs = @() }
        @{ Label = 'DryRun and Force'; ExtraArgs = @('-Force') }
        @{ Label = 'DryRun and PromptRestart'; ExtraArgs = @('-PromptRestart') }
    ) {
        $runtime = New-Item -ItemType Directory -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
        $StateFile = Join-Path $runtime.FullName 'state.json'
        $DryRun = $false
        $ids = @('winget', 'repo', 'sophia', 'postInstallTweaks', 'registry', 'shortcut', 'restoreShortcut', 'optionalShortcut', 'optionalWinget', 'summary')
        $SetupState = Initialize-State -StatePath $StateFile -StepIds $ids
        foreach ($id in $ids) {
            $SetupState.steps[$id].status = 'done'
            $SetupState.steps[$id].message = 'Previously completed'
        }
        Save-State -State $SetupState -StatePath $StateFile
        foreach ($name in @('progress.json', 'install.log', 'failed-installs.log', 'sophia.completed', 'winget.completed', 'optional-winget.completed', 'Setup Summary.txt', 'Failed Installs.txt')) {
            'Previous authoritative result' | Set-Content (Join-Path $runtime.FullName $name)
        }
        $before = @(Get-ChildItem $runtime.FullName -File | Sort-Object Name | Get-FileHash | Select-Object Path, Hash) | ConvertTo-Json

        # Run the production script in a child host with disposable paths and an
        # administrator-check substitute. Any attempt to invoke setup work fails.
        $source = $bootstrapAst.Extent.Text.Replace('#Requires -RunAsAdministrator', '')
        $source = $source.Replace('$SetupPath = "C:\Setup"', ('$SetupPath = ' + "'$($runtime.FullName)'"))
        $source = $source.Replace('$ModuleRoot = Join-Path $PSScriptRoot "modules"', ('$ModuleRoot = ' + "'$(Join-Path $repoRoot 'modules')'"))
        $adminAssignment = $main.Body.Statements | Where-Object { $_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$isAdmin' }
        $guards = @('Invoke-WingetManifestInstall', 'Get-BackupManifestData', 'Ensure-CanonicalRepo', 'Get-SophiaScript', 'Invoke-PostInstallTweaks', 'New-DesktopShortcut', 'Read-Host', 'Restart-Computer') | ForEach-Object {
            "function $_ { throw 'Dry run invoked $_' }"
        }
        $source = $source.Replace($main.Extent.Text, (($guards -join "`n") + "`n" + $main.Extent.Text))
        $source = $source.Replace($adminAssignment.Extent.Text, '$isAdmin = $true')
        $previewScript = Join-Path $TestDrive 'preview-bootstrap.ps1'
        [IO.File]::WriteAllText($previewScript, $source, [Text.UTF8Encoding]::new($true))
        $output = & powershell.exe -NoProfile -File $previewScript -DryRun -ConfigRoot $runtime.FullName @ExtraArgs 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
        ($output -join "`n") | Should -Match 'Windows Setup Bootstrap - Preview'
        $after = @(Get-ChildItem $runtime.FullName -File | Sort-Object Name | Get-FileHash | Select-Object Path, Hash) | ConvertTo-Json
        $after | Should -Be $before
    }
}
