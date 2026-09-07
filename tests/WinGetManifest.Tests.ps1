Describe 'WinGet manifest preflight' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\modules\WinGetInstall.ps1')
        function Write-Log { param($Message, $Level) }
        function Add-SummaryItem { param($Step, $Status, $Message) }
        function Set-StepState { param($StepId, $Status, $Message) }
        function Update-SetupProgress { }
        function Add-FailedItem { param($Category, $Item, $Reason) }
        function Wait-ForNetwork { throw 'Generic network probe must not run' }
    }

    BeforeEach {
        $manifestPath = Join-Path $TestDrive 'apps.json'
        $markerPath = Join-Path $TestDrive "apps-$([guid]::NewGuid()).marker"
        $installArgs = @{
            ManifestPath = $manifestPath
            MarkerPath = $markerPath
            StepId = 'apps'
            SummaryStep = 'Apps'
            ManifestLabel = 'apps.json'
            MissingManifestMessage = 'Missing apps.json'
        }
        Mock Write-Log { }
        Mock Add-SummaryItem { }
        Mock Set-StepState { }
        Mock Update-SetupProgress { }
        Mock Add-FailedItem { }
        Mock Wait-ForNetwork { throw 'Generic network probe must not run' }
        Mock Assert-WingetReady { }
        Mock Test-WingetPackageInstalled { $true }
        Mock Invoke-WingetPackageInstall { throw 'Unexpected installation' }
    }

    It 'rejects malformed manifests before inventory, installation or completion' {
        foreach ($json in @(
            '', '{', 'null', '[]', '[{"Sources":[]}]', '{}',
            '{"Sources":null}', '{"Sources":{}}', '{"Sources":[null]}',
            '{"Sources":[{}]}', '{"Sources":[{"Packages":null}]}',
            '{"Sources":[{"Packages":{}}]}', '{"Sources":[{"Packages":[null]}]}',
            '{"Sources":[{"Packages":[{}]}]}',
            '{"Sources":[{"Packages":[{"PackageIdentifier":42}]}]}',
            '{"Sources":[{"Packages":[{"PackageIdentifier":"   "}]}]}',
            '{"Sources":[{"Packages":[{"PackageIdentifier":"Vendor.Valid"},{}]}]}'
        )) {
            Set-Content -LiteralPath $manifestPath -Value $json
            Invoke-WingetManifestInstall @installArgs | Should -BeFalse
            Test-Path -LiteralPath $markerPath | Should -BeFalse
        }

        Should -Invoke Test-WingetPackageInstalled -Times 0 -Exactly
        Should -Invoke Invoke-WingetPackageInstall -Times 0 -Exactly
        Should -Invoke Wait-ForNetwork -Times 0 -Exactly
        Should -Invoke Set-StepState -Times 0 -Exactly -ParameterFilter { $Status -eq 'done' }
        Should -Invoke Set-StepState -ParameterFilter { $Status -eq 'failed' -and $Message -like '*Invalid WinGet manifest*' }
        Should -Invoke Add-SummaryItem -ParameterFilter { $Status -eq 'FAIL' -and $Message -like '*Sources[[]0].Packages[[]1].PackageIdentifier*' }
    }

    It 'accepts intentionally empty manifests without inventory or network work' {
        foreach ($json in @('{"Sources":[]}', '{"Sources":[{"Packages":[]}]}')) {
            Set-Content -LiteralPath $manifestPath -Value $json
            $ids = Get-WingetPackageIdsFromJson -Path $manifestPath
            $ids.GetType().IsArray | Should -BeTrue
            $ids.Count | Should -Be 0
            Invoke-WingetManifestInstall @installArgs | Should -BeTrue
        }
        Should -Invoke Test-WingetPackageInstalled -Times 0 -Exactly
        Should -Invoke Invoke-WingetPackageInstall -Times 0 -Exactly
        Should -Invoke Wait-ForNetwork -Times 0 -Exactly
        Should -Invoke Set-StepState -Times 2 -Exactly -ParameterFilter { $Status -eq 'done' }
    }

    It 'preserves the array contract and deduplicates valid identifiers' {
        '{"Sources":[{"Packages":[{"PackageIdentifier":"Vendor.One"},{"PackageIdentifier":"Vendor.One"}]}]}' |
            Set-Content -LiteralPath $manifestPath
        $ids = Get-WingetPackageIdsFromJson -Path $manifestPath
        $ids.GetType().IsArray | Should -BeTrue
        $ids.Count | Should -Be 1
        $ids[0] | Should -Be 'Vendor.One'
    }

    It 'completes an offline fully installed manifest without a network gate' {
        '{"Sources":[{"Packages":[{"PackageIdentifier":"Vendor.One"}]}]}' |
            Set-Content -LiteralPath $manifestPath

        Invoke-WingetManifestInstall @installArgs | Should -BeTrue

        Should -Invoke Test-WingetPackageInstalled -Times 1 -Exactly
        Should -Invoke Invoke-WingetPackageInstall -Times 0 -Exactly
        Should -Invoke Wait-ForNetwork -Times 0 -Exactly
        Should -Invoke Set-StepState -Times 1 -Exactly -ParameterFilter { $Status -eq 'done' }
        (Get-Content -LiteralPath $markerPath) | Should -Be (Get-FileHash -LiteralPath $manifestPath).Hash
    }

    It 'scans all packages before contacting the install service and keeps offline failures retryable' {
        '{"Sources":[{"Packages":[{"PackageIdentifier":"Vendor.Installed"},{"PackageIdentifier":"Vendor.Missing"}]}]}' |
            Set-Content -LiteralPath $manifestPath
        $script:scanOrder = [System.Collections.Generic.List[string]]::new()
        Mock Test-WingetPackageInstalled {
            $script:scanOrder.Add($PackageId)
            return $PackageId -eq 'Vendor.Installed'
        }
        Mock Invoke-WingetPackageInstall {
            $script:scanOrder.Count | Should -Be 2
            return [pscustomobject]@{ ExitCode = 1; Output = @('Failed to open the package source: network unavailable') }
        }

        Invoke-WingetManifestInstall @installArgs | Should -BeFalse

        Should -Invoke Invoke-WingetPackageInstall -Times 1 -Exactly -ParameterFilter { $PackageId -eq 'Vendor.Missing' }
        Should -Invoke Wait-ForNetwork -Times 0 -Exactly
        Should -Invoke Set-StepState -Times 1 -Exactly -ParameterFilter { $Status -eq 'failed' }
        Should -Invoke Set-StepState -Times 0 -Exactly -ParameterFilter { $Status -eq 'done' }
        Should -Invoke Write-Log -ParameterFilter { $Message -like '*Failed to open the package source: network unavailable*' }
        Test-Path -LiteralPath $markerPath | Should -BeFalse
    }
}
