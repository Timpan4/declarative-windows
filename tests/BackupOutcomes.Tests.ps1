BeforeAll {
    $repository = Split-Path $PSScriptRoot -Parent
    $realCopy = Get-Command Copy-Item
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
        . (Join-Path $repository 'modules\BackupManifest.ps1')
        . (Join-Path $repository 'modules\RestorePlan.ps1')
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $session = Join-Path $root 'session'
        $profile = Join-Path $root 'profile'
        New-Item -ItemType Directory -Path (Join-Path $session 'first'), (Join-Path $session 'second') -Force | Out-Null
        Set-Content (Join-Path $session 'apps.json') '{}'
        Set-Content (Join-Path $session 'first\file.txt') 'first'
        Set-Content (Join-Path $session 'second\file.txt') 'second'
        $manifestPath = Join-Path $session 'backup-manifest.json'
        @{
            manifestVersion = 1
            machine = @{ userProfile = $profile; osDrive = $env:SystemDrive }
            backup = @{ backupRoot = $session }
            repo = @{ restorePath = (Join-Path $profile 'repo') }
            repoFiles = @(@{ relativePath = 'apps.json'; backupPath = 'apps.json' })
            rules = @(
                @{ success = $true; tags = @(); backupPath = 'first'; restorePath = (Join-Path $profile 'first') }
                @{ success = $true; tags = @(); backupPath = 'second'; restorePath = (Join-Path $profile 'second') }
            )
        } | ConvertTo-Json -Depth 5 | Set-Content $manifestPath
        Mock Write-Warning {}
        Mock Out-Host {}
        Mock Copy-Item { & $realCopy -LiteralPath $LiteralPath -Destination $Destination -Recurse:$Recurse -ErrorAction Stop }
    }

    It 'retains mixed results and succeeds on retry after a copy failure' {
        Mock Copy-Item { throw 'Synthetic content copy failure' } -ParameterFilter { $LiteralPath -eq (Join-Path $session 'first\file.txt') }
        { & $restorebackup -ManifestPath $manifestPath -DestinationProfileRoot $profile } | Should -Throw '*Restore completed with failures*'
        $plan = New-RestorePlan -ManifestPath $manifestPath -DestinationProfileRoot $profile
        $reportPath = Join-Path $plan.recoveryRoot 'restore-report.json'
        $report = Get-Content $reportPath -Raw | ConvertFrom-Json
        $report.Count | Should -Be 3
        $report[0].status | Should -Be 'conflicting-copy-saved' -Because ($report | ConvertTo-Json)
        $report[1].status | Should -Be 'failed'
        $report[1].message | Should -Be 'Synthetic content copy failure'
        $report[2].status | Should -Be 'restored'

        Mock Copy-Item { & $realCopy -LiteralPath $LiteralPath -Destination $Destination -ErrorAction Stop } -ParameterFilter { $LiteralPath -eq (Join-Path $session 'first\file.txt') }
        $null = & $restorebackup -ManifestPath $manifestPath -DestinationProfileRoot $profile
        $report = Get-Content $reportPath -Raw | ConvertFrom-Json
        $report[0].status | Should -Be 'already-present'
        $report[1].status | Should -Be 'restored'
        $report[2].status | Should -Be 'already-present'
    }

    It 'reports a repository recovery copy error and still attempts personal files' {
        Mock Copy-Item { throw 'Synthetic repository copy failure' } -ParameterFilter { $LiteralPath -eq (Join-Path $session 'apps.json') }
        { & $restorebackup -ManifestPath $manifestPath -DestinationProfileRoot $profile } | Should -Throw '*Restore completed with failures*'
        $plan = New-RestorePlan -ManifestPath $manifestPath -DestinationProfileRoot $profile
        $report = Get-Content (Join-Path $plan.recoveryRoot 'restore-report.json') -Raw | ConvertFrom-Json
        $report[0].status | Should -Be 'failed'
        $report[0].message | Should -Be 'Synthetic repository copy failure'
        @($report | Where-Object status -eq 'restored').Count | Should -Be 2 -Because ($report | ConvertTo-Json)
    }
}
