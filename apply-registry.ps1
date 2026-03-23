#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ConfigPath,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Normalize-RegistryPath {
    param([string]$Path)

    if ($Path -like "Registry::*") {
        return $Path
    }

    if ($Path -match '^(HKLM|HKCU|HKCR|HKU|HKCC)') {
        return "Registry::$Path"
    }

    return $Path
}

function Convert-RegistryType {
    param([string]$Type)

    switch ($Type.ToUpperInvariant()) {
        "DWORD" { return "DWord" }
        "STRING" { return "String" }
        default { throw "Unsupported registry value type: $Type" }
    }
}

$config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
$entries = $config.entries

if (-not $entries) {
    return [pscustomobject]@{
        Applied = 0
        Skipped = 0
        Failed = 0
    }
}

$applied = 0
$skipped = 0
$failed = 0

foreach ($entry in $entries) {
    try {
        if (-not $entry.path -or -not $entry.name -or -not $entry.type) {
            throw "Registry entry missing required fields (path, name, type)"
        }

        $registryPath = Normalize-RegistryPath -Path $entry.path
        $valueType = Convert-RegistryType -Type $entry.type
        $desiredValue = $entry.value

        if ($valueType -eq "DWord") {
            $desiredValue = [int]$desiredValue
        }

        if (-not (Test-Path -LiteralPath $registryPath)) {
            if ($DryRun) {
                $skipped++
                continue
            }

            New-Item -Path $registryPath -Force | Out-Null
        }

        $currentValue = $null
        try {
            $currentValue = (Get-ItemProperty -LiteralPath $registryPath -Name $entry.name -ErrorAction SilentlyContinue).$($entry.name)
        }
        catch {
            $currentValue = $null
        }

        if ($null -ne $currentValue -and $currentValue -eq $desiredValue) {
            $skipped++
            continue
        }

        if ($DryRun) {
            $skipped++
            continue
        }

        Set-ItemProperty -LiteralPath $registryPath -Name $entry.name -Value $desiredValue -Type $valueType -Force
        $applied++
    }
    catch {
        $failed++
    }
}

return [pscustomobject]@{
    Applied = $applied
    Skipped = $skipped
    Failed = $failed
}
