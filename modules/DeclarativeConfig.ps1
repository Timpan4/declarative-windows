function Normalize-RegistryPath {
    param([string]$Path)

    $hives = @{
        HKLM = 'HKEY_LOCAL_MACHINE'
        HKCU = 'HKEY_CURRENT_USER'
        HKCR = 'HKEY_CLASSES_ROOT'
        HKU = 'HKEY_USERS'
        HKCC = 'HKEY_CURRENT_CONFIG'
    }

    if ($Path -match '^(?:Registry::)?(?:(?<hive>HKLM|HKCU|HKCR|HKU|HKCC):?|(?<hive>HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER|HKEY_CLASSES_ROOT|HKEY_USERS|HKEY_CURRENT_CONFIG))(?<subkey>\\.*)?$') {
        $hive = $Matches.hive.ToUpperInvariant()
        $subkey = $Matches.subkey
        if ($hives.ContainsKey($hive)) { $hive = $hives[$hive] }
        return "Registry::$hive$subkey"
    }

    throw "Unsupported registry path: $Path"
}

function Convert-RegistryType {
    param([string]$Type)

    switch ($Type.ToUpperInvariant()) {
        "DWORD" { return "DWord" }
        "STRING" { return "String" }
        default { throw "Unsupported registry value type: $Type" }
    }
}

function Invoke-RegistryConfig {
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [switch]$DryRun
    )

    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    $entries = $config.entries

    if (-not $entries) {
        return [pscustomobject]@{
            Applied = 0
            Skipped = 0
            Failed = 0
            Failures = @()
        }
    }

    $applied = 0
    $skipped = 0
    $failed = 0
    $failures = [System.Collections.Generic.List[object]]::new()
    $entryIndex = 0

    foreach ($entry in $entries) {
        $entryIndex++
        $reason = 'Registry entry requires non-empty string fields: path, name, type'
        try {
            if ($entry.path -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.path) -or
                $entry.name -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.name) -or
                $entry.type -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.type)) {
                throw $reason
            }

            $reason = 'Unsupported registry path'
            $registryPath = Normalize-RegistryPath -Path $entry.path
            $reason = 'Unsupported registry value type; use DWORD or STRING'
            $valueType = Convert-RegistryType -Type $entry.type
            $reason = 'Registry entry requires a non-null value'
            if ($null -eq $entry.PSObject.Properties['value'] -or $null -eq $entry.value) {
                throw $reason
            }
            $desiredValue = $entry.value

            if ($valueType -eq "DWord") {
                $reason = 'DWORD value must be an integer or integer string in the Int32 range'
                $parsedValue = 0
                if (($desiredValue -isnot [int] -and $desiredValue -isnot [long] -and $desiredValue -isnot [string]) -or
                    -not [int]::TryParse([string]$desiredValue, [ref]$parsedValue)) {
                    throw $reason
                }
                $desiredValue = $parsedValue
            }
            else {
                $reason = 'STRING value must be a string; an empty string is allowed'
                if ($desiredValue -isnot [string]) { throw $reason }
            }

            $reason = 'Could not inspect registry key'
            if (-not (Test-Path -LiteralPath $registryPath -ErrorAction Stop)) {
                if ($DryRun) {
                    $skipped++
                    continue
                }

                $reason = 'Could not create registry key'
                New-Item -Path $registryPath -Force -ErrorAction Stop | Out-Null
            }

            $valueName = if ($entry.name -eq "(Default)") { "" } else { $entry.name }
            $currentValue = $null
            $currentKind = $null
            try {
                $registryKey = Get-Item -LiteralPath $registryPath -ErrorAction Stop
                $currentValue = $registryKey.GetValue($valueName, $null, "DoNotExpandEnvironmentNames")
                if ($null -ne $currentValue) {
                    $currentKind = $registryKey.GetValueKind($valueName)
                }
            }
            catch {
                $currentValue = $null
                $currentKind = $null
            }

            if ($null -ne $currentValue -and $currentValue -eq $desiredValue -and "$currentKind" -eq $valueType) {
                $skipped++
                continue
            }

            if ($DryRun) {
                $skipped++
                continue
            }

            $reason = 'Could not write registry value'
            if ($entry.name -eq "(Default)") {
                Set-Item -LiteralPath $registryPath -Value $desiredValue -Force -ErrorAction Stop
            }
            else {
                New-ItemProperty -LiteralPath $registryPath -Name $entry.name -Value $desiredValue -PropertyType $valueType -Force -ErrorAction Stop | Out-Null
            }
            $applied++
        }
        catch {
            $failed++
            $failures.Add([pscustomobject]@{
                Index = $entryIndex
                Path = $entry.path
                Name = $entry.name
                Reason = $reason
                Category = [string]$_.CategoryInfo.Category
            })
        }
    }

    return [pscustomobject]@{
        Applied = $applied
        Skipped = $skipped
        Failed = $failed
        Failures = $failures.ToArray()
    }
}

function Invoke-DeclarativeConfig {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Registry")]
        [string]$Kind,

        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [switch]$DryRun
    )

    switch ($Kind) {
        "Registry" { return Invoke-RegistryConfig -ConfigPath $ConfigPath -DryRun:$DryRun }
    }
}
