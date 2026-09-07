BeforeAll {
    $repository = Split-Path $PSScriptRoot -Parent
    # Run production orchestration without elevation; all writes use disposable fixtures.
    foreach ($name in @('preflight-backup', 'restore-backup')) {
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repository "$name.ps1"), [ref]$null, [ref]$null)
        $body = '[CmdletBinding(SupportsShouldProcess)]' + $ast.ParamBlock.Extent.Text + "`n" +
            '$PSScriptRoot = ''' + $repository.Replace("'", "''") + "'`n" +
            (($ast.EndBlock.Statements | ForEach-Object { $_.Extent.Text }) -join "`n")
        Set-Variable -Name $name.Replace('-', '') -Value ([scriptblock]::Create($body))
    }
}

Describe 'backup source outcomes' {
    It 'reports missing sources and only fails for required sources: <Required>' -ForEach @(
        @{ Required = $true }, @{ Required = $false }
    ) {
        $destination = Join-Path $TestDrive "backup-$Required"
        $missing = Join-Path $TestDrive 'missing-source'
        $configPath = Join-Path $TestDrive 'config.json'
        @{
            knownFolders = @()
            extraPaths = @(@{ enabled = $true; label = 'missing'; path = $missing; required = $Required })
            options = @{ backupRepoFiles = $false }
        } | ConvertTo-Json -Depth 5 | Set-Content $configPath
        Mock Get-Command { $null }
        $run = { & $preflightbackup -DestinationRoot $destination -ConfigPath $configPath -BackupName 'session' -Force -VerifyHashes }
        if ($Required) { $run | Should -Throw '*Backup completed with failures*' }
        else { & $run }

        $session = Join-Path $destination 'declarative-windows-backup\session'
        $manifest = Get-Content (Join-Path $session 'backup-manifest.json') -Raw | ConvertFrom-Json
        $report = Get-Content (Join-Path $session 'reports\backup-report.txt') -Raw
        $manifest.rules.Count | Should -Be 1
        $manifest.rules[0].source | Should -Be $missing
        $manifest.rules[0].success | Should -BeFalse
        $manifest.rules[0].skipped | Should -Be (-not $Required)
        $report | Should -Match ([regex]::Escape($missing))
        $report | Should -Match ([regex]::Escape($manifest.rules[0].message))
        if ($Required) {
            $manifest.failures.Count | Should -Be 1
            $manifest.failures[0].message | Should -Be $manifest.rules[0].message
            $manifest.verification.status | Should -Be 'failed'
            $report | Should -Match '\[FAILED\] missing'
            $report | Should -Match 'Outcome: FAILED'
        }
        else {
            $manifest.failures.Count | Should -Be 0
            $manifest.verification.status | Should -Be 'verified'
            $report | Should -Match '\[SKIPPED\] missing'
            $report | Should -Match 'Outcome: OK'
        }
    }
}

Describe 'restore copy outcomes' {
    BeforeEach {
        $session = Join-Path $TestDrive 'session'
        New-Item -ItemType Directory -Path (Join-Path $session 'first'), (Join-Path $session 'second') -Force | Out-Null
        Set-Content (Join-Path $session 'apps.json') '{}'
        $manifestPath = Join-Path $session 'backup-manifest.json'
        @{
            manifestVersion = 1
            machine = @{ userProfile = $TestDrive; osDrive = $env:SystemDrive }
            backup = @{ backupRoot = $session }
            repo = @{ restorePath = (Join-Path $TestDrive 'repo') }
            repoFiles = @(@{ relativePath = 'apps.json'; backupPath = 'apps.json' })
            rules = @(
                @{ success = $true; tags = @(); backupPath = 'first'; restorePath = (Join-Path $TestDrive 'restored-first') }
                @{ success = $true; tags = @(); backupPath = 'second'; restorePath = (Join-Path $TestDrive 'restored-second') }
            )
        } | ConvertTo-Json -Depth 5 | Set-Content $manifestPath
        Mock Write-Warning {}
    }

    It 'retains mixed results and succeeds on retry after <Fault>' -ForEach @(
        @{ Fault = 'robocopy failure'; Reason = 'robocopy exit code 8' }
        @{ Fault = 'copy exception'; Reason = 'Synthetic content copy failure' }
    ) {
        Mock robocopy {
            if ($args[0] -eq (Join-Path $session 'first')) {
                if ($Fault -eq 'copy exception') { throw 'Synthetic content copy failure' }
                $global:LASTEXITCODE = 8
            }
            else { $global:LASTEXITCODE = 1 }
        }
        { & $restorebackup -ManifestPath $manifestPath } | Should -Throw '*Restore completed with failures*'
        $reportPath = Join-Path $session 'restore-report.json'
        $report = Get-Content $reportPath -Raw | ConvertFrom-Json
        $report.Count | Should -Be 3
        $report[0].status | Should -Be 'restored'
        $report[1].status | Should -Be 'failed'
        $report[1].message | Should -Be $Reason
        $report[2].status | Should -Be 'restored'

        Mock robocopy { $global:LASTEXITCODE = 1 }
        & $restorebackup -ManifestPath $manifestPath
        $report = Get-Content $reportPath -Raw | ConvertFrom-Json
        $report.Count | Should -Be 3
        @($report | Where-Object { $_.status -ne 'restored' }).Count | Should -Be 0
    }

    It 'reports a repository copy error and still attempts content copies' {
        Mock Copy-Item { throw 'Synthetic repository copy failure' }
        Mock robocopy { $global:LASTEXITCODE = 1 }
        { & $restorebackup -ManifestPath $manifestPath } | Should -Throw '*Restore completed with failures*'
        $report = Get-Content (Join-Path $session 'restore-report.json') -Raw | ConvertFrom-Json
        $report[0].status | Should -Be 'failed'
        $report[0].message | Should -Be 'Synthetic repository copy failure'
        @($report | Where-Object { $_.status -eq 'restored' }).Count | Should -Be 2
    }
}
