Describe "bootstrap.ps1 static checks" {
    BeforeAll {
        $scriptPath = Resolve-Path (Join-Path $PSScriptRoot "..\bootstrap.ps1")
        $scriptContent = Get-Content $scriptPath -Raw
    }

    It "tracks WinGet completion marker with hash" {
        $scriptContent | Should -Match "winget\.completed"
        $scriptContent | Should -Match "Get-FileHash"
    }

    It "supports optional apps manifest and marker" {
        $scriptContent | Should -Match "optional-apps\.json"
        $scriptContent | Should -Match "optional-winget\.completed"
        $scriptContent | Should -Match "OptionalAppsOnly"
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

    It "tracks resume state" {
        $scriptContent | Should -Match "state\.json"
        $scriptContent | Should -Match "Initialize-State"
    }

    It "handles registry fallback" {
        $scriptContent | Should -Match "apply-registry\.ps1"
        $scriptContent | Should -Match "registry\.json"
    }

    It "checks network with ping and HTTPS fallback" {
        $scriptContent | Should -Match "1\.1\.1\.1"
        $scriptContent | Should -Match "Test-NetConnection"
        $scriptContent | Should -Match "Invoke-WebRequest"
    }

    It "uses a canonical repo path in Documents" {
        $scriptContent | Should -Match "MyDocuments"
        $scriptContent | Should -Match "declarative-windows"
    }

    It "creates a restore shortcut" {
        $scriptContent | Should -Match "Restore My Files\.lnk"
        $scriptContent | Should -Match "restore-backup\.ps1"
    }

    It "creates an optional apps shortcut and prompt" {
        $scriptContent | Should -Match "Install Optional Apps\.lnk"
        $scriptContent | Should -Match "Install optional apps now\? \(Y/N\)"
    }

    It "can fall back when repo clone fails" {
        $scriptContent | Should -Match "git"
        $scriptContent | Should -Match "continuing with C:\\Setup"
        $scriptContent | Should -Match "backup-manifest\.json"
    }

    It "auto-downloads Sophia Script when missing" {
        $scriptContent | Should -Match "Get-SophiaScript"
        $scriptContent | Should -Match "SophiaDownloadUrl"
        $scriptContent | Should -Match "Sophia\.Script\.for\.Windows\.11"
        $scriptContent | Should -Match "Expand-Archive"
    }

    It "tracks failed installs and writes a report" {
        $scriptContent | Should -Match "Add-FailedItem"
        $scriptContent | Should -Match "Write-FailedInstallsReport"
        $scriptContent | Should -Match "Failed Installs\.txt"
        $scriptContent | Should -Match "failed-installs\.log"
    }

    It "checks individual packages after WinGet import" {
        $scriptContent | Should -Match "stillMissing"
        $scriptContent | Should -Match "Not installed after import from"
    }

    It "keeps partial WinGet failures retryable" {
        $scriptContent | Should -Match 'Set-StepState -StepId \$stepId -Status "failed" -Message "\$failCount package\(s\) failed"'
    }

    It "chooses newest backup manifest across drives" {
        $scriptContent | Should -Match 'Sort-Object LastWriteTimeUtc -Descending'
        $scriptContent | Should -Match 'newestMatch'
    }
}
