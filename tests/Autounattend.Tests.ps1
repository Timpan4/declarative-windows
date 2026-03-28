Describe "autounattend.xml static checks" {
    BeforeAll {
        $filePath = Resolve-Path (Join-Path $PSScriptRoot "..\autounattend.xml")
        $fileContent = Get-Content $filePath -Raw
    }

    It "runs bootstrap from C:\\Setup" {
        $fileContent | Should -Match "C:\\Setup\\bootstrap\.ps1"
    }

    It "does not hardcode a disk or partition target" {
        $fileContent | Should -Not -Match "<DiskConfiguration>"
        $fileContent | Should -Not -Match "<WillWipeDisk>true</WillWipeDisk>"
        $fileContent | Should -Not -Match "<InstallTo>"
        $fileContent | Should -Not -Match "<DiskID>0</DiskID>"
    }

    It "does not include an empty product key block" {
        $fileContent | Should -Not -Match "<ProductKey>"
        $fileContent | Should -Not -Match "<Key></Key>"
    }

    It "sets execution policy for bootstrap" {
        $fileContent | Should -Match "Set-ExecutionPolicy"
    }

    It "waits for network before bootstrap" {
        $fileContent | Should -Match "Wait for Network Connectivity"
        $fileContent | Should -Match "Network wait timed out"
    }
}
