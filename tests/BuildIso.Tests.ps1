Describe "build-iso.ps1 static checks" {
    BeforeAll {
        $scriptPath = Resolve-Path (Join-Path $PSScriptRoot "..\build-iso.ps1")
        $payloadModulePath = Resolve-Path (Join-Path $PSScriptRoot "..\modules\StagedSetupPayload.ps1")
        $scriptContent = Get-Content $scriptPath -Raw
        $payloadModuleContent = Get-Content $payloadModulePath -Raw
        $buildAndPayloadContent = $scriptContent + "`n" + $payloadModuleContent
    }

    It "uses $OEM$ $1 Setup path" {
        ($scriptContent -like '*sources*`$OEM`$*`$1\Setup*') | Should -Be $true
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
        $buildAndPayloadContent | Should -Match "apply-registry\.ps1"
        $buildAndPayloadContent | Should -Match "config\\registry\.json"
    }

    It "copies restore workflow assets" {
        $buildAndPayloadContent | Should -Match "restore-backup\.ps1"
        $buildAndPayloadContent | Should -Match "backup\.template\.json"
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
        $buildAndPayloadContent | Should -Match "Validate-StagedIsoLayout"
        $scriptContent | Should -Match "Validating staged ISO layout"
        $buildAndPayloadContent | Should -Match "Staged ISO layout validation passed"
    }

    It "checks unattend C:\\Setup references against the staged OEM payload" {
        $stagedPathPattern = [regex]::Escape('Join-Path $WorkRoot ''sources\$OEM$\$1\Setup''')

        $buildAndPayloadContent | Should -Match "Get-UnattendSetupFileReferences"
        $buildAndPayloadContent | Should -Match "C:\\Setup\\"
        $buildAndPayloadContent | Should -Match $stagedPathPattern
        $buildAndPayloadContent | Should -Match "autounattend\.xml references .* staged ISO is missing"
    }

    It "runs staged layout validation before building the ISO" {
        $validationIndex = $scriptContent.LastIndexOf('Validate-StagedIsoLayout')
        $buildIndex = $scriptContent.IndexOf('Write-Step "Building custom ISO with oscdimg"')

        $validationIndex | Should -BeGreaterThan -1
        $buildIndex | Should -BeGreaterThan -1
        $validationIndex | Should -BeLessThan $buildIndex
    }

    It "passes source ISO into unattend validation" {
        $sourceIsoArgumentPattern = [regex]::Escape('-SourceISO $SourceISO')
        $scriptContent | Should -Match $sourceIsoArgumentPattern
    }

    It "does not reference MountDir anymore" {
        $scriptContent.Contains('$MountDir') | Should -Be $false
    }
}

Describe "ISO payload selection" {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\modules\StagedSetupPayload.ps1')
    }

    BeforeEach {
        $project = Join-Path $TestDrive ('project-' + [guid]::NewGuid())
        $work = Join-Path $TestDrive ('work-' + [guid]::NewGuid())
        foreach ($relative in @(
            'autounattend.xml', 'bootstrap.ps1', 'apps.json', 'Sophia-Preset.ps1',
            'restore-backup.ps1', 'apply-registry.ps1', 'modules\BootstrapRun.ps1',
            'modules\WinGetInstall.ps1', 'modules\BackupManifest.ps1',
            'modules\DeclarativeConfig.ps1',
            'modules\Run-SophiaPreset.ps1', 'config\registry.json', 'config\backup.template.json'
        )) {
            $file = Join-Path $project $relative
            [void][IO.Directory]::CreateDirectory((Split-Path $file -Parent))
            [IO.File]::WriteAllText($file, 'fixture')
        }
    }

    It "stages required files and excludes unrelated and ignored files" {
        foreach ($relative in @('config\backup.json', 'config\restore.json', 'config\secret-personal.json', 'config\unrelated.txt', 'modules\unrelated.txt', 'modules\StagedSetupPayload.ps1')) {
            [IO.File]::WriteAllText((Join-Path $project $relative), 'excluded fixture')
        }
        $payload = @(Get-IsoSetupPayload -ProjectRoot $project)
        Copy-IsoSetupPayload -Payload $payload -WorkRoot $work
        $setup = Join-Path $work 'sources\$OEM$\$1\Setup'
        Get-Content -LiteralPath (Join-Path $setup 'config\registry.json') | Should -Be 'fixture'
        Get-Content -LiteralPath (Join-Path $setup 'config\backup.template.json') | Should -Be 'fixture'
        Test-Path -LiteralPath (Join-Path $setup 'modules\Run-SophiaPreset.ps1') | Should -BeTrue
        @(Get-ChildItem -LiteralPath (Join-Path $setup 'config') -File).Count | Should -Be 2
        Test-Path -LiteralPath (Join-Path $setup 'modules\unrelated.txt') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $setup 'modules\StagedSetupPayload.ps1') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $setup 'optional-apps.json') | Should -BeFalse
    }

    It "includes optional apps when explicitly present" {
        [IO.File]::WriteAllText((Join-Path $project 'optional-apps.json'), 'optional fixture')
        Copy-IsoSetupPayload -Payload @(Get-IsoSetupPayload -ProjectRoot $project) -WorkRoot $work
        Get-Content -LiteralPath (Join-Path $work 'sources\$OEM$\$1\Setup\optional-apps.json') | Should -Be 'optional fixture'
    }

    It "rejects missing required configuration before copying" {
        Remove-Item -LiteralPath (Join-Path $project 'config\registry.json')
        { Get-IsoSetupPayload -ProjectRoot $project } | Should -Throw '*Missing required payload file*registry.json*'
        Test-Path -LiteralPath $work | Should -BeFalse
    }
}

Describe "ISO build preflight" {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\modules\IsoBuildPreflight.ps1')
    }

    BeforeEach {
        $source = Join-Path $TestDrive 'source.iso'
        [IO.File]::WriteAllText($source, 'original source')
    }

    It "rejects source/output identity and preserves the source" {
        { Get-IsoOutputPath -SourceISO $source -OutputISO $source } | Should -Throw '*must be different*'
        [IO.File]::ReadAllText($source) | Should -Be 'original source'
    }

    It "rejects existing files and directories without changing them" {
        $output = Join-Path $TestDrive 'existing.iso'
        [IO.File]::WriteAllText($output, 'existing output')
        { Get-IsoOutputPath -SourceISO $source -OutputISO $output } | Should -Throw '*already exists*'
        [IO.File]::ReadAllText($output) | Should -Be 'existing output'
        { Get-IsoOutputPath -SourceISO $source -OutputISO $TestDrive } | Should -Throw '*already exists*'
    }

    It "rejects an alternate data stream of the source" {
        { Get-IsoOutputPath -SourceISO $source -OutputISO ($source + ':output.iso') } | Should -Throw '*Invalid ISO output filename*'
        [IO.File]::ReadAllText($source) | Should -Be 'original source'
        @(Get-Item -LiteralPath $source -Stream 'output.iso' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
    It "rejects a parent that is a file" {
        { Get-IsoOutputPath -SourceISO $source -OutputISO (Join-Path $source 'output.iso') } | Should -Throw '*Cannot create ISO output*'
        [IO.File]::ReadAllText($source) | Should -Be 'original source'
    }

    It "rejects non-filesystem output paths" {
        { Get-IsoOutputPath -SourceISO $source -OutputISO 'HKCU:\Software\output.iso' } | Should -Throw '*filesystem path*'
    }

    It "creates missing parent directories and leaves no probe output" {
        $output = Join-Path $TestDrive 'new\[output].iso'
        Get-IsoOutputPath -SourceISO $source -OutputISO $output | Should -Be $output
        Test-Path -LiteralPath (Split-Path $output -Parent) | Should -BeTrue
        Test-Path -LiteralPath $output | Should -BeFalse
    }

    Context "measured capacity" {
        BeforeEach {
            $sourceRoot = Join-Path $TestDrive 'mounted'
            [void][IO.Directory]::CreateDirectory($sourceRoot)
            [IO.File]::WriteAllBytes((Join-Path $sourceRoot 'install.wim'), [byte[]]::new(100))
            $payloadFile = Join-Path $TestDrive 'payload.ps1'
            [IO.File]::WriteAllBytes($payloadFile, [byte[]]::new(20))
            $spaceArgs = @{
                SourceRoot = $sourceRoot
                Payload = @([pscustomobject]@{ Source = $payloadFile })
                StagingDirectory = 'C:\staging'
                OutputDirectory = 'D:\output'
            }
        }

        It "combines staging and output estimates on the same volume" {
            Mock Get-Volume { [pscustomobject]@{ UniqueId = 'shared'; SizeRemaining = 239 } }
            { Assert-IsoBuildSpace @spaceArgs } | Should -Throw '*240 bytes required, 239 available*'
        }

        It "accepts separate volumes that each meet their estimate" {
            Mock Get-Volume { [pscustomobject]@{ UniqueId = $FilePath; SizeRemaining = 120 } }
            { Assert-IsoBuildSpace @spaceArgs } | Should -Not -Throw
        }

        It "rejects insufficient output space on a separate volume" {
            Mock Get-Volume {
                [pscustomobject]@{ UniqueId = $FilePath; SizeRemaining = $(if ($FilePath -like 'D:*') { 119 } else { 120 }) }
            }
            { Assert-IsoBuildSpace @spaceArgs } | Should -Throw '*D:\output*120 bytes required, 119 available*'
        }

        It "fails closed when capacity information is unavailable" {
            Mock Get-Volume { $null }
            { Assert-IsoBuildSpace @spaceArgs } | Should -Throw '*Cannot determine free space*'
        }
    }

    It "checks destination and capacity before staging and publishes without overwrite" {
        $content = Get-Content (Join-Path $PSScriptRoot '..\build-iso.ps1') -Raw
        $copyIndex = $content.IndexOf('Copy-Item -Path "$sourceRoot*"')
        $content.IndexOf('Get-IsoOutputPath -SourceISO') | Should -BeLessThan $copyIndex
        $content.IndexOf('Assert-IsoBuildSpace -SourceRoot') | Should -BeLessThan $copyIndex
        $content | Should -Match ([regex]::Escape('[IO.File]::Move($pendingOutput, $outputPath)'))
    }
}
