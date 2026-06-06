#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ConfigPath,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$ModuleRoot = Join-Path $PSScriptRoot "modules"
$DeclarativeConfigModule = Join-Path $ModuleRoot "DeclarativeConfig.ps1"
if (Test-Path $DeclarativeConfigModule) {
    . $DeclarativeConfigModule
}

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

if (Get-Command Invoke-DeclarativeConfig -ErrorAction SilentlyContinue) {
    return Invoke-DeclarativeConfig -Kind Registry -ConfigPath $ConfigPath -DryRun:$DryRun
}

throw "DeclarativeConfig module not found at $DeclarativeConfigModule"
