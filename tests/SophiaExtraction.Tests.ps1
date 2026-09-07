Describe 'isolated Sophia release extraction' {
    BeforeAll {
        $bootstrap = Join-Path (Split-Path $PSScriptRoot -Parent) 'bootstrap.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($bootstrap, [ref]$null, [ref]$null)
        foreach ($name in @('Test-SophiaFramework', 'Assert-SophiaReleaseIntegrity', 'Get-SophiaScript')) {
            $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        function Write-Log { param($Message, $Level) }
    }

    BeforeEach {
        $SetupPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $SophiaVersion = '7.3.0'
        $SophiaDir = Join-Path $SetupPath 'Sophia-Script'
        $SophiaScript = Join-Path $SophiaDir 'Sophia.ps1'
        $SophiaZipName = 'release.zip'
        $SophiaDownloadUrl = 'https://example.invalid/fixture.zip'
        $release = Join-Path $TestDrive ('archive-' + [guid]::NewGuid().ToString('N'))
        $releaseRoot = Join-Path $release 'Sophia_Script_for_Windows_11_v7.3.0'
        $files = @('Sophia.ps1', 'Module\Sophia.psm1', 'Import-TabCompletion.ps1', 'Module\Binaries\LGPO.exe', 'Module\Private\WinAPI.ps1')
        $files += @('Get-Hash', 'InitialActions', 'PostActions', 'Set-KnownFolderPath', 'Set-Policy', 'Set-UserShellFolder', 'Show-Menu', 'Write-AdditionalKeys', 'Write-ExtensionKeys') | ForEach-Object { "Module\Private\$_.ps1" }
        $files += @('de-DE', 'en-US', 'es-ES', 'fr-FR', 'hu-HU', 'it-IT', 'pl-PL', 'pt-BR', 'ru-RU', 'tr-TR', 'uk-UA', 'zh-CN') | ForEach-Object { "Module\Localizations\$_\Sophia.psd1" }
        foreach ($file in $files + 'Module\Manifest\SophiaScript.psd1') {
            $path = Join-Path $releaseRoot $file
            New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
            Set-Content -LiteralPath $path -Value 'fixture only'
        }
        Set-Content -LiteralPath (Join-Path $releaseRoot 'Module\Manifest\SophiaScript.psd1') -Value "@{ ModuleVersion = '7.3.0' }"
        $stale = Join-Path $SetupPath 'unrelated\Sophia.ps1'
        New-Item -ItemType Directory -Path (Split-Path $stale -Parent) -Force | Out-Null
        Set-Content -LiteralPath $stale -Value 'unrelated script'
        $fixtureZip = "$release.zip"
        Compress-Archive -LiteralPath $releaseRoot -DestinationPath $fixtureZip
        $SophiaArchiveSha256 = (Get-FileHash -LiteralPath $fixtureZip).Hash
        Mock Invoke-WebRequest {
            Copy-Item -LiteralPath $fixtureZip -Destination $OutFile
        }
    }

    It 'publishes the exact pinned release despite stale neighboring scripts' {
        Get-SophiaScript | Should -Be $SophiaScript
        Get-Content -LiteralPath $SophiaScript | Should -Be 'fixture only'
        Get-Content -LiteralPath $stale | Should -Be 'unrelated script'
        @(Get-ChildItem -LiteralPath $SetupPath -Filter '.sophia-*').Count | Should -Be 0
    }

    It 'rejects an incomplete archive without publishing it' {
        Remove-Item -LiteralPath (Join-Path $releaseRoot 'Module\Binaries\LGPO.exe')
        Compress-Archive -LiteralPath $releaseRoot -DestinationPath $fixtureZip -Force
        $SophiaArchiveSha256 = (Get-FileHash -LiteralPath $fixtureZip).Hash
        Get-SophiaScript | Should -BeNullOrEmpty
        Test-Path -LiteralPath $SophiaDir | Should -BeFalse
        Get-Content -LiteralPath $stale | Should -Be 'unrelated script'
    }

    It 'cleans failed extraction staging and preserves neighboring files' {
        Mock Expand-Archive { throw 'Synthetic extraction failure' }
        Get-SophiaScript | Should -BeNullOrEmpty
        Test-Path -LiteralPath $SophiaDir | Should -BeFalse
        @(Get-ChildItem -LiteralPath $SetupPath -Filter '.sophia-*').Count | Should -Be 0
        Get-Content -LiteralPath $stale | Should -Be 'unrelated script'
    }

    It 'rejects mismatched or incomplete downloads before extraction' {
        Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile -Value 'partial download' }
        Mock Expand-Archive { throw 'Must not extract an unverified archive' }
        Get-SophiaScript | Should -BeNullOrEmpty
        Should -Invoke Expand-Archive -Times 0 -Exactly
        Test-Path -LiteralPath $SophiaDir | Should -BeFalse
    }

    It 'checks cached code against the verified archive before reuse' {
        Get-SophiaScript | Should -Be $SophiaScript
        Get-SophiaScript | Should -Be $SophiaScript
        Set-Content -LiteralPath $SophiaScript -Value 'modified code'
        Get-SophiaScript | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly
    }

    It 'preserves an incomplete existing directory and reports a retryable failure' {
        New-Item -ItemType Directory -Path $SophiaDir | Out-Null
        Set-Content -LiteralPath $SophiaScript -Value 'existing script'
        Get-SophiaScript | Should -BeNullOrEmpty
        Get-Content -LiteralPath $SophiaScript | Should -Be 'existing script'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }

    It 'preserves the preparation outcome when staging cleanup fails' {
        Mock Remove-Item { throw 'Synthetic locked staging directory' }
        Get-SophiaScript | Should -Be $SophiaScript
        Get-Content -LiteralPath $SophiaScript | Should -Be 'fixture only'
        # A failed preparation still returns null even if its cleanup also fails.
        $SophiaDir = Join-Path $SetupPath 'second-install'
        Mock Expand-Archive { throw 'Synthetic extraction failure' }
        Get-SophiaScript | Should -BeNullOrEmpty
    }
}
