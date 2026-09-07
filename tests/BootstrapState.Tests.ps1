BeforeAll {
    $stateModule = Join-Path $PSScriptRoot '..\modules\BootstrapRun.ps1'
    . $stateModule
}

Describe 'Exclusive and atomic bootstrap state' {
    BeforeEach {
        $StateFile = Join-Path $TestDrive "$([guid]::NewGuid()).json"
        $DryRun = $false
        $Force = $false
        $SetupState = Initialize-State -StatePath $StateFile -StepIds @('repo')
    }

    It 'rejects a competing process and releases ownership after disposal' {
        $owner = Enter-BootstrapStateLock -StatePath $StateFile
        try {
            $command = ". '$($stateModule.Replace("'", "''"))'; try { `$handle = Enter-BootstrapStateLock -StatePath '$($StateFile.Replace("'", "''"))'; `$handle.Dispose(); exit 0 } catch { exit 17 }"
            & powershell.exe -NoProfile -NonInteractive -Command $command
            $LASTEXITCODE | Should -Be 17
        }
        finally { $owner.Dispose() }
        $nextOwner = Enter-BootstrapStateLock -StatePath $StateFile
        $nextOwner.Dispose()
    }

    It 'preserves committed completion when publication is interrupted' {
        Set-StepState -StepId repo -Status done -Message 'Restored'
        $original = [IO.File]::ReadAllText($StateFile)
        $reader = [IO.File]::Open($StateFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            $SetupState.steps.repo.message = 'New publication'
            { Save-State -State $SetupState -StatePath $StateFile } | Should -Throw
            [IO.File]::ReadAllText($StateFile) | Should -Be $original
        }
        finally { $reader.Dispose() }
        $SetupState = Initialize-State -StatePath $StateFile -StepIds @('repo')
        Should-RunStep -StepId repo | Should -BeFalse
        $SetupState.steps.repo.message = 'Published after retry'
        Save-State -State $SetupState -StatePath $StateFile
        [IO.File]::ReadAllText("$StateFile.previous") | Should -Be $original
        (Initialize-State -StatePath $StateFile -StepIds @('repo')).steps.repo.message | Should -Be 'Published after retry'
    }

    It 'preserves corrupt state and refuses to restart completed actions from empty state' {
        foreach ($content in @('{', 'null', '{}', '{"version":"1","steps":{"repo":{"status":"done"}}}')) {
            [IO.File]::WriteAllText($StateFile, $content)
            { Initialize-State -StatePath $StateFile -StepIds @('repo') } | Should -Throw '*original file is preserved*'
            [IO.File]::ReadAllText($StateFile) | Should -Be $content
        }
    }
}
