Describe 'declarative registry validation and results' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\modules\DeclarativeConfig.ps1')
    }

    BeforeEach {
        $configPath = Join-Path $TestDrive 'registry.json'
        Mock Test-Path { $true }
        Mock New-Item {}
        Mock Get-Item { throw 'Value does not exist' }
        Mock New-ItemProperty {}
        Mock Set-Item {}
    }

    It 'rejects <Label> before registry access, including dry runs' -ForEach @(
        @{ Label = 'missing value'; Entry = @{ path = 'HKCU:\Software\Fixture'; name = 'Setting'; type = 'DWORD' } }
        @{ Label = 'null value'; Entry = @{ path = 'HKCU:\Software\Fixture'; name = 'Setting'; type = 'STRING'; value = $null } }
        @{ Label = 'unsupported kind'; Entry = @{ path = 'HKCU:\Software\Fixture'; name = 'Setting'; type = 'BINARY'; value = 1 } }
        @{ Label = 'fractional DWORD'; Entry = @{ path = 'HKCU:\Software\Fixture'; name = 'Setting'; type = 'DWORD'; value = 1.5 } }
        @{ Label = 'boolean DWORD'; Entry = @{ path = 'HKCU:\Software\Fixture'; name = 'Setting'; type = 'DWORD'; value = $true } }
        @{ Label = 'overflow DWORD'; Entry = @{ path = 'HKCU:\Software\Fixture'; name = 'Setting'; type = 'DWORD'; value = 2147483648 } }
        @{ Label = 'non-numeric DWORD'; Entry = @{ path = 'HKCU:\Software\Fixture'; name = 'Setting'; type = 'DWORD'; value = 'private-value' } }
        @{ Label = 'array STRING'; Entry = @{ path = 'HKCU:\Software\Fixture'; name = 'Setting'; type = 'STRING'; value = @('private-value') } }
        @{ Label = 'numeric STRING'; Entry = @{ path = 'HKCU:\Software\Fixture'; name = 'Setting'; type = 'STRING'; value = 1 } }
        @{ Label = 'object STRING'; Entry = @{ path = 'HKCU:\Software\Fixture'; name = 'Setting'; type = 'STRING'; value = @{ secret = 'private-value' } } }
        @{ Label = 'missing name'; Entry = @{ path = 'HKCU:\Software\Fixture'; type = 'DWORD'; value = 1 } }
    ) {
        @{ entries = @($Entry) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath
        foreach ($preview in @($false, $true)) {
            $result = Invoke-RegistryConfig -ConfigPath $configPath -DryRun:$preview
            $result.Applied | Should -Be 0
            $result.Skipped | Should -Be 0
            $result.Failed | Should -Be 1
            $result.Failures.Count | Should -Be 1
            $result.Failures[0].Index | Should -Be 1
            $result.Failures[0].Path | Should -Be $Entry.path
            $result.Failures[0].Name | Should -Be $Entry.name
            $result.Failures[0].Reason | Should -Not -BeNullOrEmpty
            ($result | ConvertTo-Json -Depth 5) | Should -Not -Match 'private-value'
        }
        Should -Invoke Test-Path -Times 0 -Exactly
        Should -Invoke New-Item -Times 0 -Exactly
        Should -Invoke New-ItemProperty -Times 0 -Exactly
        Should -Invoke Set-Item -Times 0 -Exactly
    }

    It 'applies zero, integer strings and empty strings while preserving counts' {
        @{ entries = @(
            @{ path = 'HKCU:\Software\Fixture'; name = 'Zero'; type = 'DWORD'; value = 0 }
            @{ path = 'HKCU:\Software\Fixture'; name = 'Integer'; type = 'DWORD'; value = '1' }
            @{ path = 'HKCU:\Software\Fixture'; name = 'Empty'; type = 'STRING'; value = '' }
        ) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configPath
        $result = Invoke-DeclarativeConfig -Kind Registry -ConfigPath $configPath
        $result.Applied | Should -Be 3
        $result.Skipped | Should -Be 0
        $result.Failed | Should -Be 0
        $result.Failures.Count | Should -Be 0
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter { $Name -eq 'Zero' -and $Value -eq 0 -and $PropertyType -eq 'DWord' }
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter { $Name -eq 'Integer' -and $Value -eq 1 -and $Value -is [int] }
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter { $Name -eq 'Empty' -and $Value -eq '' -and $PropertyType -eq 'String' }
    }

    It 'skips an already-correct value and kind without writing' {
        Mock Get-Item {
            $key = [pscustomobject]@{}
            $key | Add-Member ScriptMethod GetValue { param($name, $fallback, $options) return 1 }
            $key | Add-Member ScriptMethod GetValueKind { param($name) return 'DWord' }
            return $key
        }
        @{ entries = @(@{ path = 'HKCU:\Software\Fixture'; name = 'Setting'; type = 'DWORD'; value = 1 }) } |
            ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configPath
        $result = Invoke-RegistryConfig -ConfigPath $configPath
        $result.Skipped | Should -Be 1
        $result.Applied | Should -Be 0
        $result.Failed | Should -Be 0
        $result.Failures.Count | Should -Be 0
        Should -Invoke New-ItemProperty -Times 0 -Exactly
    }

    It 'reports a non-terminating <Operation> failure without leaking the value and continues' -ForEach @(
        @{ Operation = 'key creation' }
        @{ Operation = 'named value write' }
        @{ Operation = 'default value write' }
    ) {
        $name = 'Setting'
        if ($Operation -eq 'key creation') {
            Mock Test-Path { $false }
            Mock New-Item { Write-Error 'private-value' -Category PermissionDenied }
        }
        elseif ($Operation -eq 'default value write') {
            $name = '(Default)'
            Mock Set-Item { Write-Error 'private-value' -Category PermissionDenied }
        }
        else {
            Mock New-ItemProperty { Write-Error 'private-value' -Category PermissionDenied }
        }
        @{ entries = @(
            @{ path = 'HKCU:\Software\Fixture'; name = $name; type = 'STRING'; value = 'private-value' }
            @{ path = 'HKCU:\Software\Fixture'; name = 'Invalid'; type = 'STRING' }
        ) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configPath
        $result = Invoke-RegistryConfig -ConfigPath $configPath
        $result.Applied | Should -Be 0
        $result.Failed | Should -Be 2
        $result.Failures[0].Name | Should -Be $name
        $result.Failures[0].Reason | Should -Match '^Could not (create registry key|write registry value)$'
        $result.Failures[0].Category | Should -Be 'PermissionDenied'
        $result.Failures[1].Index | Should -Be 2
        $result.Failures[1].Reason | Should -Be 'Registry entry requires a non-null value'
        ($result | ConvertTo-Json -Depth 5) | Should -Not -Match 'private-value'
    }

    It 'returns an empty failure collection for an empty configuration' {
        '{"entries":[]}' | Set-Content -LiteralPath $configPath
        $result = Invoke-RegistryConfig -ConfigPath $configPath
        $result.Applied | Should -Be 0
        $result.Skipped | Should -Be 0
        $result.Failed | Should -Be 0
        $result.Failures.Count | Should -Be 0
    }
}
