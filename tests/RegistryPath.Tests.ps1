Describe 'registry path normalization' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\modules\DeclarativeConfig.ps1')
    }

    It 'normalizes aliases, drive paths and full provider paths' {
        $hives = @{
            HKLM = 'HKEY_LOCAL_MACHINE'
            HKCU = 'HKEY_CURRENT_USER'
            HKCR = 'HKEY_CLASSES_ROOT'
            HKU = 'HKEY_USERS'
            HKCC = 'HKEY_CURRENT_CONFIG'
        }
        foreach ($alias in $hives.Keys) {
            $full = $hives[$alias]
            foreach ($path in @("${alias}:\SOFTWARE", "$alias\SOFTWARE", "$full\SOFTWARE", "Registry::$full\SOFTWARE")) {
                Normalize-RegistryPath $path | Should -Be "Registry::$full\SOFTWARE"
            }
        }
        Normalize-RegistryPath 'hkcu:\Software' | Should -Be 'Registry::HKEY_CURRENT_USER\Software'
    }

    It 'rejects unsupported providers and hive lookalikes' {
        foreach ($path in @('', 'C:\SOFTWARE', 'FileSystem::C:\SOFTWARE', 'Registry::C:\SOFTWARE', 'HKLMOther\SOFTWARE', 'HKLM:SOFTWARE', 'HKEY_CURRENT_USER:\Software', 'Registry::HKEY_LOCAL_MACHINE:\Software', 'SOFTWARE')) {
            { Normalize-RegistryPath $path } | Should -Throw
        }
    }

    It 'passes a normalized path to writes and rejects invalid paths before provider access' {
        Mock Test-Path { $false }
        Mock New-Item {}
        Mock Get-Item { throw 'Missing value' }
        Mock New-ItemProperty {}
        $configPath = Join-Path $TestDrive 'registry.json'
        @{ entries = @(
            @{ path = 'HKCU:\Software\Fixture'; name = 'Enabled'; type = 'DWORD'; value = 1 },
            @{ path = 'FileSystem::C:\Fixture'; name = 'Enabled'; type = 'DWORD'; value = 1 }
        ) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configPath

        $result = Invoke-RegistryConfig -ConfigPath $configPath

        $result.Applied | Should -Be 1
        $result.Failed | Should -Be 1
        Should -Invoke Test-Path -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq 'Registry::HKEY_CURRENT_USER\Software\Fixture' }
        Should -Invoke New-Item -Times 1 -Exactly
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq 'Registry::HKEY_CURRENT_USER\Software\Fixture' -and $Value -eq 1 }
    }
}
