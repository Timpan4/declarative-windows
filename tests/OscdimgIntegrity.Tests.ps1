BeforeAll {
    $buildPath = Join-Path $PSScriptRoot '..\build-iso.ps1'
    $ast = [Management.Automation.Language.Parser]::ParseFile($buildPath, [ref]$null, [ref]$null)
    $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Find-OscdImg' }, $true)
    . ([scriptblock]::Create($definition.Extent.Text))
    function Write-Step { param($Message) }
    function Write-Success { param($Message) }
    function Write-ErrorMessage { param($Message) }
    function Write-Info { param($Message) }
}

Describe 'oscdimg download integrity' {
    BeforeEach {
        $TempDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $fixture = Join-Path $TestDrive 'fixture.exe'
        Set-Content -LiteralPath $fixture -Value 'synthetic executable bytes, never executed'
        $expectedHash = (Get-FileHash -LiteralPath $fixture).Hash
        Mock Test-Path {
            if ($Path -like '*Windows Kits*') { return $false }
            return [IO.File]::Exists($Path) -or [IO.Directory]::Exists($Path)
        }
        Mock Get-ItemProperty { $null }
        Mock Invoke-WebRequest { Copy-Item -LiteralPath $fixture -Destination $OutFile }
        Mock Write-Info { }
    }

    It 'requires an independent digest before downloading and records verified identity' {
        { Find-OscdImg -DownloadUrl 'https://example.invalid/oscdimg.exe' } | Should -Throw '*requires -OscdimgSha256*'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        $path = Find-OscdImg -DownloadUrl 'https://example.invalid/oscdimg.exe' -ExpectedHash $expectedHash
        (Get-FileHash -LiteralPath $path).Hash | Should -Be $expectedHash
        Should -Invoke Write-Info -ParameterFilter { $Message -like "*Verified oscdimg executable SHA256 $expectedHash*" }
    }

    It 'rejects a mismatched executable and a truncated download' {
        Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile -Value 'truncated' }
        { Find-OscdImg -DownloadUrl 'https://example.invalid/oscdimg.exe' -ExpectedHash $expectedHash } | Should -Throw '*SHA-256 mismatch*'
    }

    It 'verifies a ZIP before extraction and rejects a mismatched archive' {
        $archiveRoot = Join-Path $TestDrive 'release'
        New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
        Copy-Item -LiteralPath $fixture -Destination (Join-Path $archiveRoot 'oscdimg.exe')
        $fixture = Join-Path $TestDrive 'fixture.zip'
        Compress-Archive -LiteralPath $archiveRoot -DestinationPath $fixture -Force
        $archiveHash = (Get-FileHash -LiteralPath $fixture).Hash
        $path = Find-OscdImg -DownloadUrl 'https://example.invalid/oscdimg.zip' -ExpectedHash $archiveHash
        (Get-FileHash -LiteralPath $path).Hash | Should -Be $expectedHash
        Mock Expand-Archive { throw 'Must not extract mismatched content' }
        { Find-OscdImg -DownloadUrl 'https://example.invalid/oscdimg.zip' -ExpectedHash $expectedHash } | Should -Throw '*SHA-256 mismatch*'
        Should -Invoke Expand-Archive -Times 0 -Exactly
    }

    It 'rejects an archive without oscdimg instead of reusing a stale download' {
        $stale = Join-Path $TestDrive 'other-build/tools/oscdimg.exe'
        New-Item -ItemType Directory -Path (Split-Path $stale -Parent) -Force | Out-Null
        Set-Content -LiteralPath $stale -Value 'stale executable'
        $textFile = Join-Path $TestDrive 'readme.txt'
        Set-Content -LiteralPath $textFile -Value 'no executable in this archive'
        $fixture = Join-Path $TestDrive 'incomplete.zip'
        Compress-Archive -LiteralPath $textFile -DestinationPath $fixture -Force
        $expectedHash = (Get-FileHash -LiteralPath $fixture).Hash
        { Find-OscdImg -DownloadUrl 'https://example.invalid/oscdimg.zip' -ExpectedHash $expectedHash } | Should -Throw '*Failed to download oscdimg.exe*'
        Get-Content -LiteralPath $stale | Should -Be 'stale executable'
    }
}
