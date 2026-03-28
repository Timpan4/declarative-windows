Describe "validate-unattend.ps1 static checks" {
    BeforeAll {
        $scriptPath = Resolve-Path (Join-Path $PSScriptRoot "..\validate-unattend.ps1")
        $scriptContent = Get-Content $scriptPath -Raw
    }

    It "checks for empty product key blocks" {
        $scriptContent | Should -Match "empty ProductKey block"
    }

    It "requires the Windows SIM schema DLL" {
        $scriptContent | Should -Match "Windows SIM schema DLL not found"
        $scriptContent | Should -Match "microsoft\.componentstudio\.componentplatforminterface\.dll"
    }

    It "performs schema validation before policy checks" {
        $scriptContent | Should -Match "Test-XmlAgainstSchema"
        $scriptContent | Should -Match "passed schema validation"
    }

    It "blocks hardcoded disk selection" {
        $scriptContent | Should -Match "DiskConfiguration"
        $scriptContent | Should -Match "InstallTo"
    }

    It "validates source image metadata when ISO is provided" {
        $scriptContent | Should -Match "Get-WindowsImage"
        $scriptContent | Should -Match "install\.wim"
        $scriptContent | Should -Match "install\.esd"
    }

    It "requires bootstrap first logon command" {
        $scriptContent | Should -Match "C:\\Setup\\bootstrap\.ps1"
    }
}
