Describe 'generated automation shortcuts' {
    BeforeAll {
        $bootstrapPath = Join-Path $PSScriptRoot '..\bootstrap.ps1'
        $ast = [Management.Automation.Language.Parser]::ParseFile($bootstrapPath, [ref]$null, [ref]$null)
        $function = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'New-DesktopShortcut' }, $true)
        . ([scriptblock]::Create($function.Extent.Text))
        $calls = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'New-DesktopShortcut' }, $true)
    }

    It 'creates elevated shortcuts with profile-free launches and explicit user configuration' {
        $SetupPath = Join-Path $TestDrive 'Setup files'
        $ConfigRoot = Join-Path $TestDrive 'Selected config'
        $bootstrapTarget = Join-Path $SetupPath 'bootstrap.ps1'
        $RestoreScript = Join-Path $SetupPath 'restore-backup.ps1'
        $shortcutPath = Join-Path $TestDrive 'Run Windows Setup.lnk'
        $restoreShortcutPath = Join-Path $TestDrive 'Restore My Files.lnk'
        $optionalShortcutPath = Join-Path $TestDrive 'Install Optional Apps.lnk'
        New-Item -ItemType Directory -Path $SetupPath, $ConfigRoot | Out-Null
        foreach ($call in $calls) { & ([scriptblock]::Create($call.Extent.Text)) }

        $shell = New-Object -ComObject WScript.Shell
        foreach ($path in @($shortcutPath, $restoreShortcutPath, $optionalShortcutPath)) {
            $link = $shell.CreateShortcut($path)
            ([IO.File]::ReadAllBytes($path)[0x15] -band 0x20) | Should -Be 0x20
            $link.Arguments | Should -Match '^-NoProfile -ExecutionPolicy Bypass -File '
            $link.Arguments | Should -Match ([regex]::Escape('-WorkingDirectory "' + $SetupPath + '"'))
            $link.WorkingDirectory | Should -Be $SetupPath
        }
        $setupArguments = $shell.CreateShortcut($shortcutPath).Arguments
        $setupArguments | Should -Match ([regex]::Escape('-File "' + $bootstrapTarget + '"'))
        $setupArguments | Should -Match ([regex]::Escape('-ConfigRoot "' + $ConfigRoot + '"'))
        $setupArguments | Should -Match ([regex]::Escape('-ExpectedUserSid ' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
        $shell.CreateShortcut($optionalShortcutPath).Arguments | Should -Match '-OptionalAppsOnly '
        $shell.CreateShortcut($restoreShortcutPath).Arguments | Should -Match ([regex]::Escape('-DestinationProfileRoot "' + $env:USERPROFILE + '"'))
    }

    It 'rejects a different elevation identity before initializing setup' {
        $guard = $ast.EndBlock.Statements[0]
        $guard | Should -BeOfType ([Management.Automation.Language.IfStatementAst])
        $ExpectedUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        { & ([scriptblock]::Create($guard.Extent.Text)) } | Should -Not -Throw
        $ExpectedUserSid = 'S-1-0-0'
        { & ([scriptblock]::Create($guard.Extent.Text)) } | Should -Throw '*another account*'
    }

    It 'sets the shortcut working directory before setup or restore begins' {
        $WorkingDirectory = Join-Path $TestDrive 'Shortcut start'
        New-Item -ItemType Directory -Path $WorkingDirectory | Out-Null
        foreach ($script in @('bootstrap.ps1', 'restore-backup.ps1')) {
            $scriptAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot "..\$script"), [ref]$null, [ref]$null)
            $guard = $scriptAst.EndBlock.Statements | Where-Object { $_.Extent.Text -match '^if \(\$WorkingDirectory\)' }
            $guard | Should -Not -BeNullOrEmpty
            Push-Location
            try {
                & ([scriptblock]::Create($guard.Extent.Text))
                (Get-Location).Path | Should -Be $WorkingDirectory
            } finally {
                Pop-Location
            }
        }
    }
}
