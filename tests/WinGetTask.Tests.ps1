BeforeAll {
    . (Join-Path $PSScriptRoot '..\modules\WinGetInstall.ps1')
    function New-ScheduledTaskAction { param($Execute, $Argument) }
    function New-ScheduledTaskPrincipal { param($UserId, $LogonType, $RunLevel) }
    function Register-ScheduledTask { param($TaskName, $Action, $Principal, [switch]$Force) }
    function Start-ScheduledTask { param($TaskName) }
    function Get-ScheduledTask { param($TaskName) }
    function Get-ScheduledTaskInfo { param($TaskName) }
    function Stop-ScheduledTask { param($TaskName) }
    function Unregister-ScheduledTask { param($TaskName, $Confirm) }
    function winget { $global:LASTEXITCODE = 0; 'Synthetic installer success'; $args -join '|' }
}

Describe 'User-scope task result publication and cleanup' {
    BeforeEach {
        $originalTemp = $env:TEMP
        $env:TEMP = $TestDrive
        $ProgressFile = Join-Path $TestDrive 'progress.json'
        $script:taskState = 'Ready'
        $script:runnerPath = $null
        $script:resultPath = $null
        Mock New-ScheduledTaskAction {
            $script:runnerPath = [regex]::Match($Argument, '-File "(.+)"').Groups[1].Value
            $runner = Get-Content -LiteralPath $script:runnerPath -Raw
            $script:resultPath = [regex]::Match($runner, "\[IO.File\]::Move\(.+, '(.+)'\)").Groups[1].Value
            [pscustomobject]@{ Argument = $Argument }
        }
        Mock New-ScheduledTaskPrincipal { [pscustomobject]@{} }
        Mock Register-ScheduledTask { }
        Mock Start-ScheduledTask { }
        Mock Get-ScheduledTask { [pscustomobject]@{ State = $script:taskState } }
        Mock Get-ScheduledTaskInfo { [pscustomobject]@{ LastTaskResult = 0x41303 } }
        Mock Stop-ScheduledTask { $script:taskState = 'Ready' }
        Mock Unregister-ScheduledTask { }
        Mock Start-Sleep { throw 'Unexpected wait in fixture' }
    }

    AfterEach { $env:TEMP = $originalTemp }

    It 'runs the generated publisher with the exact source and version arguments' {
        Mock Start-ScheduledTask { & $script:runnerPath }
        $result = Invoke-WingetPackageInstall -PackageId Vendor.App -Source private -Version '1.2' -Unelevated
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Contain 'Synthetic installer success'
        $result.Output | Should -Contain 'install|--id|Vendor.App|--exact|--accept-package-agreements|--accept-source-agreements|--source|private|--version|1.2'
        Test-Path -LiteralPath $script:runnerPath | Should -BeFalse
        Test-Path -LiteralPath $script:resultPath | Should -BeFalse
        Test-Path -LiteralPath "$script:resultPath.tmp" | Should -BeFalse
    }

    It 'waits for complete publication while a partial temporary result exists' {
        Mock Start-ScheduledTask {
            $script:taskState = 'Running'
            Set-Content -LiteralPath "$script:resultPath.tmp" -Value '{"Completed":'
        }
        Mock Start-Sleep {
            Test-Path -LiteralPath $script:resultPath | Should -BeFalse
            Set-Content -LiteralPath "$script:resultPath.tmp" -Value '{"Completed":true,"ExitCode":0,"Output":["published"]}'
            [IO.File]::Move("$script:resultPath.tmp", $script:resultPath)
            $script:taskState = 'Ready'
        }
        $result = Invoke-WingetPackageInstall -PackageId Vendor.App -Unelevated
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Contain published
        Should -Invoke Start-Sleep -Times 1 -Exactly
    }

    It 'rejects malformed or incomplete published results' {
        foreach ($json in @('{', '{}', '{"Completed":true,"ExitCode":"0","Output":[]}', '{"Completed":true,"ExitCode":0,"Output":[null]}')) {
            $script:fixtureResult = $json
            Mock Start-ScheduledTask { Set-Content -LiteralPath $script:resultPath -Value $script:fixtureResult }
            $result = Invoke-WingetPackageInstall -PackageId Vendor.App -Unelevated
            $result.ExitCode | Should -Be 1
            Test-Path -LiteralPath $script:runnerPath | Should -BeFalse
        }
    }

    It 'accepts a result published between the file check and task completion check' {
        Mock Get-ScheduledTaskInfo {
            Set-Content -LiteralPath $script:resultPath -Value '{"Completed":true,"ExitCode":0,"Output":["published during task check"]}'
            [pscustomobject]@{ LastTaskResult = 0 }
        }
        $result = Invoke-WingetPackageInstall -PackageId Vendor.App -Unelevated
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Contain 'published during task check'
    }

    It 'reports task startup failure and removes files after confirming the task is idle' {
        Mock Start-ScheduledTask { throw 'Synthetic startup failure' }
        $result = Invoke-WingetPackageInstall -PackageId Vendor.App -Unelevated
        $result.ExitCode | Should -Be 1
        ($result.Output -join ';') | Should -Match 'Synthetic startup failure'
        Should -Invoke Get-ScheduledTask -Times 1 -Exactly
        Should -Invoke Unregister-ScheduledTask -Times 1 -Exactly
        Test-Path -LiteralPath $script:runnerPath | Should -BeFalse
    }

    It 'reports a task that exits before it can publish a result' {
        Mock Get-ScheduledTaskInfo { [pscustomobject]@{ LastTaskResult = 1 } }
        $result = Invoke-WingetPackageInstall -PackageId Vendor.App -Unelevated
        $result.ExitCode | Should -Be 1
        ($result.Output -join ';') | Should -Match 'ended without a complete result'
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'stops running work on timeout before removing its supporting files' {
        Mock Start-ScheduledTask { $script:taskState = 'Running' }
        Mock Stop-ScheduledTask {
            Test-Path -LiteralPath $script:runnerPath | Should -BeTrue
            $script:taskState = 'Ready'
        }
        $result = Invoke-WingetPackageInstall -PackageId Vendor.App -Unelevated -TimeoutSeconds 0
        $result.ExitCode | Should -Be 1
        ($result.Output -join ';') | Should -Match 'Timed out'
        Should -Invoke Stop-ScheduledTask -Times 1 -Exactly
        Test-Path -LiteralPath $script:runnerPath | Should -BeFalse
    }

    It 'settles a cancelled task and retains evidence when it cannot confirm termination' {
        $script:cancellation = [Threading.CancellationTokenSource]::new()
        try {
            Mock Start-ScheduledTask { $script:taskState = 'Running'; $script:cancellation.Cancel() }
            Mock Stop-ScheduledTask { }
            $result = Invoke-WingetPackageInstall -PackageId Vendor.App -Unelevated -CancellationToken $script:cancellation.Token
            $result.ExitCode | Should -Be 1
            $result.RemainingWork | Should -BeTrue
            ($result.Output -join ';') | Should -Match 'Remaining work: scheduled task'
            Should -Invoke Stop-ScheduledTask -Times 1 -Exactly
            Should -Invoke Unregister-ScheduledTask -Times 0 -Exactly
            Test-Path -LiteralPath $script:runnerPath | Should -BeTrue
        }
        finally { $script:cancellation.Dispose() }
    }
}
