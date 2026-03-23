Describe "build-iso.ps1 static checks" {
    BeforeAll {
        $scriptPath = Resolve-Path (Join-Path $PSScriptRoot "..\build-iso.ps1")
        $scriptContent = Get-Content $scriptPath -Raw
    }

    It "uses $OEM$ $1 Setup path" {
        ($scriptContent -like '*`$1\Setup*') | Should -BeTrue
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
}
