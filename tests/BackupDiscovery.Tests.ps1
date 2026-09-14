BeforeAll {
    $repository = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repository 'modules\BackupManifest.ps1')
    function New-DiscoveryFixture {
        param([string]$Root)
        $null = New-Item -ItemType Directory -Path (Join-Path $Root 'files') -Force
        Set-Content -LiteralPath (Join-Path $Root 'files\saved.txt') 'backup content'
        $manifest = New-BackupManifest -Machine @{ computerName = 'fixture-machine'; userProfile = 'C:\Users\fixture'; osDrive = 'C:' } `
            -Repo @{ restorePath = 'C:\repo' } -Backup @{ backupRoot = 'E:\original-backup' } -Config @{} `
            -Rules @(@{ success = $true; backupPath = 'files'; restorePath = 'C:\Users\fixture\Documents' }) `
            -RepoFiles @() -Exports @{} -Failures @()
        $path = Join-Path $Root 'backup-manifest.json'
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path
        return $path
    }
}

Describe 'backup discovery and selection' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $null = New-Item -ItemType Directory -Path $root
        Mock Out-Host {}
        Mock Write-Warning {}
        Mock Get-FileHash { throw 'Discovery must not claim fresh hash verification' }
    }

    It 'searches the existing layout on non-system drives and reports empty locations' {
        Mock Get-PSDrive { @([pscustomobject]@{ Root = "$env:SystemDrive\" }, [pscustomobject]@{ Root = $root }) }
        Find-BackupManifest | Should -BeNullOrEmpty
        Should -Invoke Write-Warning -ParameterFilter { $Message.Contains((Join-Path $root 'declarative-windows-backup')) }
        $path = New-DiscoveryFixture (Join-Path $root 'declarative-windows-backup\session')
        Find-BackupManifest | Should -Be $path
    }

    It 'finds a nested moved backup under a selected container' {
        $path = New-DiscoveryFixture (Join-Path $root 'different-container\nested\session')
        Find-BackupManifest -Path $root | Should -Be $path
        (Get-BackupCandidate $path).Completeness | Should -Be 'Recorded complete'
    }

    It 'reports identity and absent completion time without hashing content' {
        $path = New-DiscoveryFixture (Join-Path $root 'session')
        $candidate = Get-BackupCandidate $path
        $candidate.Machine | Should -Be 'fixture-machine'
        $candidate.Profile | Should -Be 'C:\Users\fixture'
        $candidate.CreatedAt | Should -Not -Be 'Not recorded'
        $candidate.CompletedAt | Should -Be 'Not recorded'
        $candidate.Compatibility | Should -Be 'Supported'
        $candidate.Verification | Should -Be 'Content not verified during discovery'
        Should -Invoke Get-FileHash -Times 0 -Exactly
    }

    It 'requires explicit selection for <Kind> metadata' -ForEach @(
        @{ Kind = 'failures'; Expected = 'Incomplete' }
        @{ Kind = 'failed-rule'; Expected = 'Incomplete' }
        @{ Kind = 'failed-verification'; Expected = 'Incomplete' }
        @{ Kind = 'legacy-unknown'; Expected = 'Unknown' }
    ) {
        $path = New-DiscoveryFixture (Join-Path $root 'session')
        $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        switch ($Kind) {
            'failures' { $manifest.failures = @('copy failed') }
            'failed-rule' { $manifest.rules[0].success = $false }
            'failed-verification' { $manifest | Add-Member verification @{ status = 'failed' } }
            'legacy-unknown' { $manifest.PSObject.Properties.Remove('failures') }
        }
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path
        (Get-BackupCandidate $path).Completeness | Should -Be $Expected
        Find-BackupManifest -Path $root | Should -BeNullOrEmpty
        # Explicit files retain legacy/partial restore support; the restore planner
        # is responsible for validating the requested content before copying.
        Find-BackupManifest -Path $path | Should -Be $path
    }

    It 'marks missing declared <Kind> payload incomplete' -ForEach @(
        @{ Kind = 'folder' }, @{ Kind = 'repository-file' }, @{ Kind = 'verified-file' }
    ) {
        $path = New-DiscoveryFixture (Join-Path $root 'session')
        $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        switch ($Kind) {
            'folder' { $manifest.rules[0].backupPath = 'missing' }
            'repository-file' { $manifest.repoFiles = @(@{ relativePath = 'apps.json'; backupPath = 'missing.json' }) }
            'verified-file' { $manifest | Add-Member verification @{ algorithm = 'SHA256'; status = 'verified'; files = @(@{ path = 'files\missing.txt'; sha256 = ('A' * 64) }) } }
        }
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path
        $candidate = Get-BackupCandidate $path
        $candidate.Completeness | Should -Be 'Incomplete'
        $candidate.Details | Should -Match 'Missing'
        Find-BackupManifest -Path $root | Should -BeNullOrEmpty
    }

    It 'never chooses by modification time when a backup contains another backup' {
        $outer = New-DiscoveryFixture (Join-Path $root 'session')
        $inner = New-DiscoveryFixture (Join-Path $root 'session\older')
        (Get-Item -LiteralPath $outer).LastWriteTimeUtc = [datetime]'2026-09-14'
        (Get-Item -LiteralPath $inner).LastWriteTimeUtc = [datetime]'2026-09-01'
        Find-BackupManifest -Path $root | Should -BeNullOrEmpty
        Find-BackupManifest -Path $inner | Should -Be $inner
    }

    It 'validates recorded verification metadata without hashing content: <Kind>' -ForEach @(
        @{ Kind = 'valid'; Expected = 'Recorded complete' }
        @{ Kind = 'wrong-algorithm'; Expected = 'Incomplete' }
        @{ Kind = 'missing-files'; Expected = 'Incomplete' }
        @{ Kind = 'empty-files'; Expected = 'Incomplete' }
        @{ Kind = 'invalid-digest'; Expected = 'Incomplete' }
    ) {
        $path = New-DiscoveryFixture (Join-Path $root 'session')
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'session\repo-files'), (Join-Path $root 'session\exports')
        $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $verification = @{ algorithm = 'SHA256'; status = 'verified'; files = @(@{ path = 'files\saved.txt'; sha256 = ('A' * 64) }) }
        switch ($Kind) {
            'wrong-algorithm' { $verification.algorithm = 'MD5' }
            'missing-files' { $verification.Remove('files') }
            'empty-files' { $verification.files = @() }
            'invalid-digest' { $verification.files[0].sha256 = 'not-a-digest' }
        }
        $manifest | Add-Member verification $verification
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path
        (Get-BackupCandidate $path).Completeness | Should -Be $Expected
        $selected = Find-BackupManifest -Path $root
        if ($Kind -eq 'valid') { $selected | Should -Be $path }
        else { $selected | Should -BeNullOrEmpty }
        Should -Invoke Get-FileHash -Times 0 -Exactly
    }

    It 'reports <Kind> candidates and never silently falls back to a supported backup' -ForEach @(
        @{ Kind = 'unsupported-version'; Json = '{"manifestVersion":99,"machine":"newer-machine","createdAt":"2026-09-14"}' }
        @{ Kind = 'snapshot-format'; Json = '{"machine":"newer-machine","createdAt":"2026-09-14"}' }
        @{ Kind = 'unrelated'; Json = '{"unrelated":true}' }
        @{ Kind = 'malformed'; Json = '{' }
    ) {
        $supported = New-DiscoveryFixture (Join-Path $root 'older')
        $unsupported = Join-Path $root 'backup-manifest.json'
        Set-Content -LiteralPath $unsupported $Json
        $before = Get-Content -LiteralPath $unsupported -Raw
        (Get-BackupCandidate $unsupported).Compatibility | Should -Be 'Unsupported'
        Find-BackupManifest -Path $root | Should -BeNullOrEmpty
        { Find-BackupManifest -Path $unsupported } | Should -Throw '*Selected backup is unsupported*No other backup was selected*'
        Get-Content -LiteralPath $unsupported -Raw | Should -Be $before
        Test-Path -LiteralPath $supported | Should -BeTrue
    }

    It 'accepts an explicitly selected manifest with another filename and rejects a missing path' {
        $path = New-DiscoveryFixture (Join-Path $root 'session')
        $renamed = Join-Path $root 'session\chosen.json'
        Move-Item -LiteralPath $path -Destination $renamed
        Find-BackupManifest -Path $renamed | Should -Be $renamed
        { Find-BackupManifest -Path (Join-Path $root 'missing') } | Should -Throw
    }

    It 'does not auto-select after an incomplete directory search' {
        $unreadableSearchFixture = New-DiscoveryFixture (Join-Path $root 'session')
        Mock Get-ChildItem { Get-Item -LiteralPath $unreadableSearchFixture; Write-Error 'Synthetic unreadable subfolder' }
        Find-BackupManifest -Path $root | Should -BeNullOrEmpty
        Should -Invoke Write-Warning -ParameterFilter { $Message -like '*could not inspect every search location*' }
    }
}
