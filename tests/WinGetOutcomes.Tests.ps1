BeforeAll {
    . (Join-Path $PSScriptRoot '..\modules\BootstrapRun.ps1')
    . (Join-Path $PSScriptRoot '..\modules\WinGetInstall.ps1')
    function Write-Log { param($Message, $Level) }
    function winget {
        $global:LASTEXITCODE = 0
        & $script:wingetStub @args
    }
}

Describe 'WinGet request identity and command readiness' {
    BeforeEach {
        $script:wingetCalls = [Collections.Generic.List[object]]::new()
        $script:wingetStub = { $script:wingetCalls.Add(@($args)) }
        Mock Write-Log { }
        Mock Update-SetupProgress { }
        Mock Update-WingetProgressFromLine { }
    }

    It 'keeps identical IDs from different sources and requested versions' {
        $path = Join-Path $TestDrive 'requests.json'
        '{"Sources":[{"SourceDetails":{"Name":"first"},"Packages":[{"PackageIdentifier":"Vendor.App","Version":"1.2"}]},{"SourceDetails":{"Name":"second"},"Packages":[{"PackageIdentifier":"Vendor.App","Version":"2.0"}]}]}' | Set-Content $path
        $packages = Get-WingetPackagesFromJson -Path $path
        $packages.Count | Should -Be 2
        $packages[0].Source | Should -Be first
        $packages[0].Version | Should -Be '1.2'
        $packages[1].Source | Should -Be second
        $packages[1].Version | Should -Be '2.0'
        foreach ($json in @(
            '{"Sources":[{"Packages":[{"PackageIdentifier":"Vendor.App","Scope":"machine"}]}]}',
            '{"Sources":[{"Packages":[{"PackageIdentifier":"Vendor.App","Version":null}]}]}',
            '{"Sources":[{"SourceDetails":{"Name":""},"Packages":[]}]}',
            '{"Sources":[],"InstallOptions":{"Override":"x"}}'
        )) {
            Set-Content $path $json
            { Get-WingetPackagesFromJson -Path $path } | Should -Throw '*Invalid WinGet manifest*'
        }
    }

    It 'checks registered source identity before using its name' {
        $request = [pscustomobject]@{ Source = 'private'; SourceDetails = [pscustomobject]@{ Name = 'private'; Identifier = 'expected'; Argument = 'https://example.invalid/source'; Type = 'Microsoft.Rest' } }
        $script:wingetStub = { '{"Name":"private","Identifier":"expected","Arg":"https://example.invalid/source","Type":"Microsoft.Rest"}' }
        { Assert-WingetSources -Packages @($request) } | Should -Not -Throw
        $request.SourceDetails.Identifier = 'different'
        { Assert-WingetSources -Packages @($request) } | Should -Throw '*does not match manifest Identifier*'
    }

    It 'passes source to inventory and source plus version to installation without bypassing integrity' {
        Test-WingetPackageInstalled -PackageId Vendor.App -Source private | Should -BeFalse
        $null = Invoke-WingetPackageInstall -PackageId Vendor.App -Source private -Version '1.2'
        ($script:wingetCalls[0] -join '|') | Should -Be 'list|--id|Vendor.App|--exact|--accept-source-agreements|--disable-interactivity|--source|private'
        ($script:wingetCalls[1] -join '|') | Should -Be 'install|--id|Vendor.App|--exact|--accept-package-agreements|--accept-source-agreements|--source|private|--version|1.2'
    }

    It 'verifies the installed version from source-specific JSON export' {
        $script:wingetStub = {
            $args[0] | Should -Be export
            ($args -join '|') | Should -Match '--include-versions.*--source\|private'
            $outputPath = $args[[array]::IndexOf($args, '--output') + 1]
            '{"Sources":[{"SourceDetails":{"Name":"private"},"Packages":[{"PackageIdentifier":"Vendor.App","Version":"1.2"}]}]}' | Set-Content -LiteralPath $outputPath
        }
        Test-WingetPackageInstalled -PackageId Vendor.App -Source private -Version '1.2' | Should -BeTrue
        Test-WingetPackageInstalled -PackageId Vendor.App -Source private -Version '2.0' | Should -BeFalse
    }

    It 'reports missing or unregistered WinGet as a prerequisite failure' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget' }
        { Assert-WingetReady } | Should -Throw '*Prerequisite failure: WinGet is unavailable*'
        $script:wingetCalls.Count | Should -Be 0
    }

    It 'reports a WinGet executable that cannot start' {
        $script:wingetStub = { $global:LASTEXITCODE = 1 }
        { Assert-WingetReady } | Should -Throw '*Prerequisite failure: WinGet cannot start*'
    }

    It 'rediscovers tools from the registered PATH in the existing process' {
        $oldPath = $env:Path
        try {
            $registeredPath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
            if (-not $registeredPath) { throw 'The Windows fixture requires a registered machine PATH.' }
            $env:Path = $TestDrive
            Update-SetupToolPath
            ($env:Path -split ';')[0] | Should -Be $TestDrive
            foreach ($entry in ($registeredPath -split ';' | Where-Object { $_ })) {
                ($env:Path -split ';') | Should -Contain ([Environment]::ExpandEnvironmentVariables($entry))
            }
        }
        finally { $env:Path = $oldPath }
    }
}

Describe 'Persistent package outcomes and summaries' {
    BeforeEach {
        $StateFile = Join-Path $TestDrive "$([guid]::NewGuid()).state.json"
        $SetupState = Initialize-State -StatePath $StateFile -StepIds @('winget')
        $DryRun = $false
        $Force = $false
        $SummaryItems = [Collections.Generic.List[object]]::new()
        $FailedItems = [Collections.Generic.List[object]]::new()
        $manifestPath = Join-Path $TestDrive 'apps.json'
        '{"Sources":[{"Packages":[{"PackageIdentifier":"Vendor.App"}]}]}' | Set-Content $manifestPath
        $installArgs = @{ ManifestPath = $manifestPath; StepId = 'winget'; SummaryStep = 'WinGet'; MarkerPath = "$StateFile.marker"; ManifestLabel = 'apps.json'; MissingManifestMessage = 'missing' }
        Mock Assert-WingetReady { }
        Mock Assert-WingetSources { }
        Mock Write-Log { }
        Mock Update-SetupProgress { }
        Mock Test-WingetPackageInstalled { $false }
        Mock Invoke-WingetPackageInstall { [pscustomobject]@{ ExitCode = 0; Output = @('Installed successfully') } }
    }

    It 'fails once at the prerequisite without attempting any package' {
        Mock Assert-WingetReady { throw 'Prerequisite failure: WinGet is unavailable' }
        Invoke-WingetManifestInstall @installArgs | Should -BeFalse
        Should -Invoke Test-WingetPackageInstalled -Times 0 -Exactly
        Should -Invoke Invoke-WingetPackageInstall -Times 0 -Exactly
        $SummaryItems.Count | Should -Be 1
        $SummaryItems[0].Message | Should -Match 'Prerequisite failure'
        $FailedItems.Count | Should -Be 0
    }

    It 'persists uncertainty then verifies delayed discovery without reinstalling' {
        Invoke-WingetManifestInstall @installArgs | Should -BeTrue
        $SetupState = Initialize-State -StatePath $StateFile -StepIds @('winget')
        $SetupState.steps.winget.status | Should -Be unverified
        $SetupState.steps.winget.packages[0].Status | Should -Be unverified
        $SetupState.steps.winget.packages[0].ExitCode | Should -Be 0
        $FailedItems[0].Status | Should -Be WARN
        Test-Path -LiteralPath $installArgs.MarkerPath | Should -BeFalse
        Should-RunStep winget | Should -BeTrue

        Mock Test-WingetPackageInstalled { $true }
        Invoke-WingetManifestInstall @installArgs | Should -BeTrue
        $persisted = Initialize-State -StatePath $StateFile -StepIds @('winget')
        $persisted.steps.winget.status | Should -Be done
        $persisted.steps.winget.packages.Count | Should -Be 1
        $persisted.steps.winget.packages[0].Status | Should -Be verified
        Should -Invoke Invoke-WingetPackageInstall -Times 1 -Exactly
    }

    It 'retains source and version through scanning and user-scope retry' {
        '{"Sources":[{"SourceDetails":{"Name":"private"},"Packages":[{"PackageIdentifier":"Vendor.App","Version":"1.2"}]}]}' | Set-Content $manifestPath
        Mock Invoke-WingetPackageInstall {
            if (-not $Unelevated) { return [pscustomobject]@{ ExitCode = 1; Output = @('cannot be run from an administrator context') } }
            [pscustomobject]@{ ExitCode = 0; Output = @('Installed successfully') }
        }
        Invoke-WingetManifestInstall @installArgs | Should -BeTrue
        Should -Invoke Test-WingetPackageInstalled -Times 3 -Exactly -ParameterFilter { $PackageId -eq 'Vendor.App' -and $Source -eq 'private' -and $Version -eq '1.2' }
        Should -Invoke Invoke-WingetPackageInstall -Times 1 -Exactly -ParameterFilter { $Unelevated -and $Source -eq 'private' -and $Version -eq '1.2' }
        $SetupState.steps.winget.packages[0].Source | Should -Be private
        $SetupState.steps.winget.packages[0].Version | Should -Be '1.2'
    }

    It 'preserves a hash mismatch and numeric exit status without leaking raw installer output' {
        Mock Invoke-WingetPackageInstall { [pscustomobject]@{ ExitCode = -1978335215; Output = @('Installer hash does not match', 'https://example.invalid/?token=secret') } }
        Invoke-WingetManifestInstall @installArgs | Should -BeFalse
        $FailedItems[0].Reason | Should -Match 'Integrity failure: installer hash mismatch.*-1978335215.*0x8A150011'
        $FailedItems[0].Reason | Should -Not -Match 'token=secret'
        $SetupState.steps.winget.packages[0].Status | Should -Be failed
        $SetupState.steps.winget.packages[0].ExitCode | Should -Be -1978335215
    }

    It 'distinguishes prerequisite failure from other installer failures' {
        Get-WingetFailureReason -Result ([pscustomobject]@{ ExitCode = 1; Output = @('Failed to open the package source: network unavailable') }) | Should -Match '^Prerequisite failure'
        Get-WingetFailureReason -Result ([pscustomobject]@{ ExitCode = 1603; Output = @('Installation failed') }) | Should -Match '^Installer failure.*1603'
    }
}
