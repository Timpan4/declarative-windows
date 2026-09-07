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

Describe "Source ISO image validation" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..\validate-unattend.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        foreach ($name in @('Write-Info', 'Write-Success', 'Find-UnattendSchemaDll', 'Test-SourceIsoImage')) {
            $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            . ([scriptblock]::Create($function.Extent.Text))
        }
        # Keep these fixtures usable on hosts without DISM or Storage cmdlets.
        function Get-WindowsImage { param($ImagePath, $Index, $ErrorAction) }
        function Mount-DiskImage { param($ImagePath, [switch]$PassThru) }
        function Dismount-DiskImage { param($ImagePath, $ErrorAction) }
        function Get-Volume { param([Parameter(ValueFromPipeline)]$InputObject) }
    }

    BeforeEach {
        $iso = Join-Path $TestDrive 'source.iso'
        [IO.File]::WriteAllText($iso, 'disposable ISO fixture')
        [void][IO.Directory]::CreateDirectory((Join-Path $TestDrive 'sources'))
        [IO.File]::WriteAllText((Join-Path $TestDrive 'sources\install.wim'), 'image fixture')
        $script:imageDetails = @{
            1 = [pscustomobject]@{ Version = [version]'10.0.26100.1'; Architecture = 9; InstallationType = 'Client' }
            2 = [pscustomobject]@{ Version = [version]'10.0.26200.1'; Architecture = 9; InstallationType = 'Client' }
        }
        Mock Write-Info {}
        Mock Write-Success {}
        Mock Mount-DiskImage { [pscustomobject]@{ ImagePath = $ImagePath } }
        Mock Get-Volume { [pscustomobject]@{ DriveLetter = 'TestDrive' } }
        Mock Dismount-DiskImage {}
        Mock Get-WindowsImage {
            if ($Index) { return $script:imageDetails[[int]$Index] }
            @(
                [pscustomobject]@{ ImageIndex = 1; ImageName = 'Windows 11 Home' }
                [pscustomobject]@{ ImageIndex = 2; ImageName = 'Windows 11 Pro' }
            )
        }
    }

    It "accepts supported editions in <format> and reads each detailed image" -TestCases @(
        @{ format = 'wim' }, @{ format = 'esd' }
    ) {
        param($format)
        if ($format -eq 'esd') {
            Move-Item -LiteralPath (Join-Path $TestDrive 'sources\install.wim') -Destination (Join-Path $TestDrive 'sources\install.esd')
        }
        { Test-SourceIsoImage -IsoPath $iso } | Should -Not -Throw
        Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter { $Index -eq 1 -and $ImagePath.EndsWith("install.$format") }
        Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter { $Index -eq 2 -and $ImagePath.EndsWith("install.$format") }
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly -ParameterFilter { $ImagePath -eq $iso }
    }

    It "rejects <reason> even when the first edition is supported" -TestCases @(
        @{ reason = 'pre-24H2'; property = 'Version'; value = '10.0.22631.1' }
        @{ reason = 'ARM64'; property = 'Architecture'; value = 12 }
        @{ reason = 'x86'; property = 'Architecture'; value = 0 }
        @{ reason = 'missing architecture'; property = 'Architecture'; value = $null }
        @{ reason = 'Server'; property = 'InstallationType'; value = 'Server' }
        @{ reason = 'missing installation type'; property = 'InstallationType'; value = $null }
        @{ reason = 'missing version'; property = 'Version'; value = $null }
        @{ reason = 'invalid version'; property = 'Version'; value = 'unknown' }
    ) {
        param($property, $value)
        $script:imageDetails[2].$property = $value
        { Test-SourceIsoImage -IsoPath $iso } | Should -Throw '*image index 2*'
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly
        Should -Invoke Write-Success -Times 0 -Exactly
    }

    It "fails closed and unmounts when detailed metadata cannot be read" {
        Mock Get-WindowsImage { throw 'DISM metadata failure' } -ParameterFilter { $Index -eq 2 }
        { Test-SourceIsoImage -IsoPath $iso } | Should -Throw '*DISM metadata failure*'
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly
    }

    It "rejects an empty detailed metadata result" {
        $script:imageDetails[2] = $null
        { Test-SourceIsoImage -IsoPath $iso } | Should -Throw '*image index 2*'
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly
    }

    It "reports the mandatory schema when Deployment Tools are absent" {
        Mock Test-Path { $false }
        { Find-UnattendSchemaDll } | Should -Throw '*Install Windows ADK Deployment Tools*standalone oscdimg.exe*'
        Should -Invoke Mount-DiskImage -Times 0 -Exactly
    }

    It "finds an installed schema and rejects a missing override" {
        $expected = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\WSIM\amd64\microsoft.componentstudio.componentplatforminterface.dll"
        Mock Test-Path { $Path -eq $expected }
        Find-UnattendSchemaDll | Should -Be $expected
        { Find-UnattendSchemaDll -OverridePath 'missing.dll' } | Should -Throw '*Specified schema DLL was not found*'
    }

    It "keeps schema and image validation ahead of ISO staging" {
        $validator = [IO.File]::ReadAllText($scriptPath)
        $validator.LastIndexOf('Find-UnattendSchemaDll -OverridePath') | Should -BeLessThan $validator.LastIndexOf('Test-SourceIsoImage -IsoPath')
        $builder = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\build-iso.ps1'))
        $validation = $builder.IndexOf('& $validateUnattendScript')
        $validation | Should -BeGreaterThan -1
        $validation | Should -BeLessThan $builder.IndexOf('$oscdimgPath = Find-OscdImg')
        $validation | Should -BeLessThan $builder.IndexOf('[void][IO.Directory]::CreateDirectory($WorkDir)')
    }
}
