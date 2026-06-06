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

if (Get-Command Invoke-DeclarativeConfig -ErrorAction SilentlyContinue) {
    return Invoke-DeclarativeConfig -Kind Registry -ConfigPath $ConfigPath -DryRun:$DryRun
}

throw "DeclarativeConfig module not found at $DeclarativeConfigModule"
