Describe "build-iso.ps1 static checks" {
    BeforeAll {
        $scriptPath = Resolve-Path (Join-Path $PSScriptRoot "..\build-iso.ps1")
        $scriptContent = Get-Content $scriptPath -Raw
    }

    It "uses $OEM$ $1 Setup path" {
        ($scriptContent -like '*sources*`$OEM`$*`$1\Setup*') | Should -BeTrue
    }


    It "validates boot images before oscdimg" {
        $scriptContent | Should -Match "BIOS boot image not found"
        $scriptContent | Should -Match "UEFI boot image not found"
    }

    It "unmounts ISO in cleanup" {
        $scriptContent | Should -Match "Dismount-DiskImage"
    }

    It "supports ISO labels" {
        $scriptContent | Should -Match '-l\$IsoLabel'
    }

    It "copies registry fallback assets" {
        $scriptContent | Should -Match "apply-registry\.ps1"
        $scriptContent | Should -Match "config\\registry\.json"
    }

    It "copies restore workflow assets" {
        $scriptContent | Should -Match "restore-backup\.ps1"
        $scriptContent | Should -Match "backup\.template\.json"
    }

    It "supports optional apps payload when present" {
        $scriptContent | Should -Match "optional-apps\.json"
        $scriptContent | Should -Match "skipping optional apps payload"
    }

    It "validates autounattend before ISO build" {
        $scriptContent | Should -Match "validate-unattend\.ps1"
        $scriptContent | Should -Match "autounattend\.xml validation passed"
    }

    It "validates the staged ISO layout before oscdimg" {
        $scriptContent | Should -Match "Validate-StagedIsoLayout"
        $scriptContent | Should -Match "Validating staged ISO layout"
        $scriptContent | Should -Match "Staged ISO layout validation passed"
    }

    It "checks unattend C:\\Setup references against the staged OEM payload" {
        $scriptContent | Should -Match "Get-UnattendSetupFileReferences"
        $scriptContent | Should -Match "C:\\Setup\\"
        $scriptContent | Should -Match "autounattend\.xml references .* staged ISO is missing"
    }

    It "runs staged layout validation before building the ISO" {
        $validationIndex = $scriptContent.IndexOf('Validate-StagedIsoLayout')
        $buildIndex = $scriptContent.IndexOf('Write-Step "Building custom ISO with oscdimg"')

        $validationIndex | Should -BeGreaterThan -1
        $buildIndex | Should -BeGreaterThan -1
        $validationIndex | Should -BeLessThan $buildIndex
    }

    It "passes source ISO into unattend validation" {
        ($scriptContent -like '*-SourceISO $SourceISO*') | Should -BeTrue
    }

    It "does not reference MountDir anymore" {
        $scriptContent.Contains('$MountDir') | Should -BeFalse
    }
}
