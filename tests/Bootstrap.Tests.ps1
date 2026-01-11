Describe "bootstrap.ps1 static checks" {
    BeforeAll {
        $scriptPath = Resolve-Path (Join-Path $PSScriptRoot "..\bootstrap.ps1")
        $scriptContent = Get-Content $scriptPath -Raw
    }

    It "tracks WinGet completion marker with hash" {
        $scriptContent | Should -Match "winget\.completed"
        $scriptContent | Should -Match "Get-FileHash"
    }

    It "tracks Sophia completion marker with hash" {
        $scriptContent | Should -Match "sophia\.completed"
        $scriptContent | Should -Match "Get-FileHash"
    }

    It "creates desktop summary" {
        $scriptContent | Should -Match "Setup Summary\.txt"
    }

    It "creates desktop shortcut" {
        $scriptContent | Should -Match "Run Windows Setup\.lnk"
    }

    It "checks network with ping and HTTPS fallback" {
        $scriptContent | Should -Match "1\.1\.1\.1"
        $scriptContent | Should -Match "Test-NetConnection"
        $scriptContent | Should -Match "Invoke-WebRequest"
    }
}
