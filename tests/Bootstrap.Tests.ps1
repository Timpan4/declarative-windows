Describe "bootstrap.ps1 static checks" {
    BeforeAll {
        $scriptPath = Resolve-Path (Join-Path $PSScriptRoot "..\bootstrap.ps1")
        $wingetModulePath = Resolve-Path (Join-Path $PSScriptRoot "..\modules\WinGetInstall.ps1")
        $scriptContent = Get-Content $scriptPath -Raw
        $wingetModuleContent = Get-Content $wingetModulePath -Raw
        $bootstrapAndWingetContent = $scriptContent + "`n" + $wingetModuleContent
    }

    It "tracks WinGet completion marker with hash" {
        $scriptContent | Should -Match "winget\.completed"
        $scriptContent | Should -Match "Get-FileHash"
    }

    It "supports optional apps manifest and marker" {
        $scriptContent | Should -Match "optional-apps\.json"
        $scriptContent | Should -Match "optional-winget\.completed"
        $scriptContent | Should -Match "OptionalAppsOnly"
    }

    It "tracks Sophia completion marker with hash" {
        $scriptContent | Should -Match "sophia\.completed"
        $scriptContent | Should -Match "Get-FileHash"
    }

    It "creates desktop summary" {
        $scriptContent | Should -Match "Setup Summary\.txt"
    }

    It "creates desktop shortcut" {
        $scriptContent | Should -Match "Run Windows Setup\.lnk"
    }

    It "tracks resume state" {
        $scriptContent | Should -Match "state\.json"
        $scriptContent | Should -Match "Initialize-State"
    }

    It "handles registry fallback" {
        $scriptContent | Should -Match "apply-registry\.ps1"
        $scriptContent | Should -Match "registry\.json"
    }

    It "migrates unattended debloat and user tweaks into bootstrap" {
        $scriptContent | Should -Match "postInstallTweaks"
        $scriptContent | Should -Match "Remove-AppxProvisionedPackage"
        $scriptContent | Should -Match "Disable-WindowsOptionalFeature"
        $scriptContent | Should -Match "ConfigureStartPins"
        $scriptContent | Should -Match "SearchboxTaskbarMode"
        $scriptContent | Should -Match "HideFileExt"
        $scriptContent | Should -Match "TaskbarAl"
        $scriptContent | Should -Match "InprocServer32"
    }

    It "checks network with ping and HTTPS fallback" {
        $scriptContent | Should -Match "1\.1\.1\.1"
        $scriptContent | Should -Match "Test-NetConnection"
        $scriptContent | Should -Match "Invoke-WebRequest"
    }

    It "uses a canonical repo path in Documents" {
        $scriptContent | Should -Match "MyDocuments"
        $scriptContent | Should -Match "declarative-windows"
    }

    It "creates a restore shortcut" {
        $scriptContent | Should -Match "Restore My Files\.lnk"
        $scriptContent | Should -Match "restore-backup\.ps1"
    }

    It "creates an optional apps shortcut and prompt" {
        $scriptContent | Should -Match "Install Optional Apps\.lnk"
        $scriptContent | Should -Match "Install optional apps now\? \(Y/N\)"
    }

    It "can fall back when repo clone fails" {
        $scriptContent | Should -Match "git"
        $scriptContent | Should -Match "continuing with C:\\Setup"
        $scriptContent | Should -Match "backup-manifest\.json"
    }

    It "auto-downloads Sophia Script when missing" {
        $scriptContent | Should -Match "Get-SophiaScript"
        $scriptContent | Should -Match "SophiaDownloadUrl"
        $scriptContent | Should -Match "Sophia\.Script\.for\.Windows\.11"
        $scriptContent | Should -Match "Expand-Archive"
    }

    It "tracks failed installs and writes a report" {
        $scriptContent | Should -Match "Add-FailedItem"
        $scriptContent | Should -Match "Write-FailedInstallsReport"
        $scriptContent | Should -Match "Failed Installs\.txt"
        $scriptContent | Should -Match "failed-installs\.log"
    }

    It "installs packages individually instead of using bulk import as the primary path" {
        $scriptContent | Should -Match "Invoke-WingetPackageInstall"
        $scriptContent | Should -Match "winget install --id"
        $scriptContent | Should -Not -Match "winget import --import-file"
    }

    It "keeps partial WinGet failures retryable" {
        $scriptContent | Should -Match 'Set-StepState -StepId \$StepId -Status "failed" -Message "\$failCount package\(s\) failed\$warningSuffix"'
    }

    It "writes progress.json during bootstrap" {
        $scriptContent | Should -Match 'progress\.json'
        $scriptContent | Should -Match 'Update-SetupProgress'
    }

    It "logs useful WinGet output and detects elevation issues" {
        $scriptContent | Should -Match 'Write-WingetOutput'
        $scriptContent | Should -Match 'Test-WingetRequiresUnelevatedRetry'
        $scriptContent | Should -Match 'cannot be run from an administrator context'
        $scriptContent | Should -Match '\[\\\|/\\\\-\]\+'
    }

    It "preserves CreationDate and WinGetVersion in filtered apps json" {
        $scriptContent | Should -Match 'CreationDate'
        $scriptContent | Should -Match 'WinGetVersion'
    }

    It "treats missing backup manifest as warning not fatal for repo step" {
        $scriptContent | Should -Match 'Backup manifest not found; using C:\\Setup fallback'
        $scriptContent | Should -Match 'Set-StepState -StepId \$stepId -Status "skipped" -Message "Backup manifest not found; using C:\\Setup fallback"'
        $scriptContent | Should -Not -Match 'Set-StepState -StepId \$stepId -Status "failed" -Message "Backup manifest not found"'
    }

    It "reports missing optional-apps.json gracefully in OptionalAppsOnly mode" {
        $scriptContent | Should -Match 'optional-apps\.json not found'
    }

    It "tracks detailed progress state fields" {
        $scriptContent | Should -Match 'phase = "Starting"'
        $scriptContent | Should -Match 'status = "Initializing setup"'
        $scriptContent | Should -Match 'currentPackage = ""'
        $scriptContent | Should -Match 'packageIndex = 0'
        $scriptContent | Should -Match 'packageTotal = 0'
        $scriptContent | Should -Match 'mode = "admin"'
        $scriptContent | Should -Match 'lastUpdated = \$null'
    }

    It "retries user-scope packages through a limited scheduled task" {
        $bootstrapAndWingetContent | Should -Match 'Register-ScheduledTask'
        $bootstrapAndWingetContent | Should -Match 'New-ScheduledTaskPrincipal'
        $bootstrapAndWingetContent | Should -Match 'RunLevel Limited'
        $bootstrapAndWingetContent | Should -Match 'LogonType Interactive'
        $bootstrapAndWingetContent | Should -Match 'WingetInstallUnelevated-'
        $bootstrapAndWingetContent | Should -Match 'cannot be run from an administrator context'
        $bootstrapAndWingetContent | Should -Not -Match 'schtasks\.exe /Create'
    }

    It "updates progress during user-scope retry" {
        $scriptContent | Should -Match "Retrying user-scope packages"
        $scriptContent | Should -Match "mode = 'user'"
        $scriptContent | Should -Match 'A second PowerShell window may appear for user-scope installers'
    }

    It "parses package counters from WinGet output" {
        $installLogPattern = [regex]::Escape('Installing [{0}/{1}]: {2} ({3})')
        $progressStatusPattern = [regex]::Escape('Installing package {0} of {1}')

        $scriptContent | Should -Match $installLogPattern
        $scriptContent | Should -Match $progressStatusPattern
    }

    It "classifies successful but unverified packages as verification warnings" {
        $scriptContent | Should -Match 'WinGet reported success but winget list did not verify the package'
        $scriptContent | Should -Match '\$unverifiedPackages'
        $scriptContent | Should -Match '\$unverifiedCount'
    }

    It "sets registry values without passing an invalid Type parameter to Set-ItemProperty" {
        $scriptContent | Should -Match "function Set-RegistryValueSafe"
        $scriptContent | Should -Match '\[int\]\$Value'
        $scriptContent | Should -Not -Match 'Set-ItemProperty[^\r\n]+-Type'
    }
}
