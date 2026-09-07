BeforeAll {
    $repository = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repository 'modules\BackupManifest.ps1')
    function New-HashFixture {
        param([string]$Root)
        $repo = Join-Path $Root 'repo'
        $source = Join-Path $Root 'source'
        New-Item -ItemType Directory -Path (Join-Path $repo 'config'), (Join-Path $source 'nested') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repository 'modules') -Destination $repo -Recurse
        foreach ($name in @('preflight-backup.ps1', 'restore-backup.ps1')) {
            (Get-Content -LiteralPath (Join-Path $repository $name) -Raw) -replace '(?m)^#Requires -RunAsAdministrator\r?\n', '' |
                Set-Content -LiteralPath (Join-Path $repo $name)
        }
        Set-Content -LiteralPath (Join-Path $repo 'apps.json') '{}'
        Set-Content -LiteralPath (Join-Path $source 'nested\file.txt') 'original content'
        Set-Content -LiteralPath (Join-Path $source 'hidden.txt') 'hidden content'
        (Get-Item -LiteralPath (Join-Path $source 'hidden.txt')).Attributes = [IO.FileAttributes]::Hidden
        Set-Content -LiteralPath (Join-Path $source 'excluded.tmp') 'excluded'
        @{
            version = 1; knownFolders = @()
            extraPaths = @(@{ enabled = $true; path = $source; label = 'payload' })
            options = @{ backupRepoFiles = $true }; excludePatterns = @('*.tmp')
            restoreTargets = @{ repoPath = (Join-Path $Root 'restored-repo'); $source = (Join-Path $Root 'restored-content') }
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $repo 'config\backup.template.json')
        return $repo
    }
}

Describe 'complete backup file verification' {
    BeforeEach {
        Mock Get-Command { $null } -ParameterFilter { $Name -in @('git', 'winget') }
    }

    It 'compares copied content, records every payload hash, and restores after serialization' {
        $root = Join-Path $TestDrive 'roundtrip'
        $repo = New-HashFixture $root
        $exporter = Join-Path $root 'export.ps1'
        'param($Action, $o, $source) Set-Content -LiteralPath $o ''{"Sources":[]}''; $global:LASTEXITCODE = 0' | Set-Content $exporter
        Mock Get-Command { [pscustomobject]@{ Source = $exporter } } -ParameterFilter { $Name -eq 'winget' }
        & (Join-Path $repo 'preflight-backup.ps1') -DestinationRoot (Join-Path $root 'backup') -BackupName 'session' -VerifyHashes -Force
        $session = Join-Path $root 'backup\declarative-windows-backup\session'
        $manifestPath = Join-Path $session 'backup-manifest.json'
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        $manifest.verification.status | Should -Be 'verified'
        @($manifest.verification.files).Count | Should -Be 4
        $manifest.verification.files.path | Should -Contain 'files\extra-payload\nested\file.txt'
        $manifest.verification.files.path | Should -Contain 'files\extra-payload\hidden.txt'
        $manifest.verification.files.path | Should -Contain 'repo-files\apps.json'
        $manifest.verification.files.path | Should -Contain 'exports\apps.json'
        & (Join-Path $repo 'restore-backup.ps1') -ManifestPath $manifestPath
        Get-Content (Join-Path $root 'restored-content\nested\file.txt') | Should -Be 'original content'
        Get-Content (Join-Path $root 'restored-repo\apps.json') | Should -Be '{}'
        Test-Path (Join-Path $root 'restored-content\excluded.tmp') | Should -BeFalse
    }

    It 'refuses verification success when a copy differs from its source' {
        $root = Join-Path $TestDrive 'bad-copy'
        $repo = New-HashFixture $root
        $corruptDestination = Join-Path $root 'backup\declarative-windows-backup\session\files\extra-payload\hidden.txt'
        Mock robocopy {
            Set-Content -LiteralPath $corruptDestination 'corrupt copy'
            $global:LASTEXITCODE = 1
        }
        { & (Join-Path $repo 'preflight-backup.ps1') -DestinationRoot (Join-Path $root 'backup') -BackupName 'session' -VerifyHashes -Force } | Should -Throw '*hash mismatch*'
        Test-Path (Join-Path $root 'backup\declarative-windows-backup\session\backup-manifest.json') | Should -BeFalse
    }

    It 'rejects damaged or unverified payloads before any restore writes' -ForEach @(
        @{ Fault = 'content' }, @{ Fault = 'repo' }, @{ Fault = 'missing' }, @{ Fault = 'added' }, @{ Fault = 'record' }
    ) {
        $root = Join-Path $TestDrive $Fault
        $repo = New-HashFixture $root
        & (Join-Path $repo 'preflight-backup.ps1') -DestinationRoot (Join-Path $root 'backup') -BackupName 'session' -VerifyHashes -Force
        $session = Join-Path $root 'backup\declarative-windows-backup\session'
        $manifestPath = Join-Path $session 'backup-manifest.json'
        switch ($Fault) {
            'content' { Set-Content (Join-Path $session 'files\extra-payload\nested\file.txt') 'changed' }
            'repo' { Set-Content (Join-Path $session 'repo-files\apps.json') 'changed' }
            'missing' { Remove-Item -LiteralPath (Join-Path $session 'repo-files\apps.json') }
            'added' { Set-Content (Join-Path $session 'files\extra-payload\added.txt') 'unrecorded' }
            'record' {
                $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
                $manifest.verification.files[0].sha256 = 'invalid'
                $manifest | ConvertTo-Json -Depth 8 | Set-Content $manifestPath
            }
        }
        { & (Join-Path $repo 'restore-backup.ps1') -ManifestPath $manifestPath } | Should -Throw
        Test-Path (Join-Path $root 'restored-content') | Should -BeFalse
        Test-Path (Join-Path $root 'restored-repo') | Should -BeFalse
        Test-Path (Join-Path $session 'restore-report.json') | Should -BeFalse
    }

    It 'checks legacy repository hashes without claiming complete verification' {
        $session = New-Item -ItemType Directory (Join-Path $TestDrive 'legacy')
        $file = Join-Path $session 'apps.json'
        Set-Content $file '{}'
        $manifest = @{ backup = @{ backupRoot = $session.FullName }; repoFiles = @(@{ backupPath = 'apps.json'; sha256 = (Get-FileHash $file).Hash }) }
        Mock Write-Warning {}
        Assert-BackupHashes $manifest $session.FullName
        Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*unverified*' }
        Set-Content $file 'changed'
        { Assert-BackupHashes $manifest $session.FullName } | Should -Throw '*Legacy backup hash validation failed*'
    }
}
