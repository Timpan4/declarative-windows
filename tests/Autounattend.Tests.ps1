Describe "autounattend.xml static checks" {
    BeforeAll {
        $filePath = Resolve-Path (Join-Path $PSScriptRoot "..\autounattend.xml")
        $fileContent = Get-Content $filePath -Raw
    }

    It "runs bootstrap from C:\\Setup" {
        $fileContent | Should -Match "C:\\Setup\\bootstrap\.ps1"
    }

    It "sets execution policy for bootstrap" {
        $fileContent | Should -Match "Set-ExecutionPolicy"
    }

    It "waits for network before bootstrap" {
        $fileContent | Should -Match "Wait for Network Connectivity"
        $fileContent | Should -Match "Network wait timed out"
    }
}
