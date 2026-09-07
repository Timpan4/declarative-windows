#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$FrameworkRoot,
    [Parameter(Mandatory)][string]$PresetPath,
    [Parameter(Mandatory)][string]$CompletionPath
)

$ErrorActionPreference = 'Stop'
$Global:Failed = $false

try {
    # Use the pinned framework's initialization contract, without running its stock preset.
    Import-Module -Name (Join-Path $FrameworkRoot 'Module\Manifest\SophiaScript.psd1') -Force -ErrorAction Stop
    Get-ChildItem -LiteralPath (Join-Path $FrameworkRoot 'Module\Private') -Filter '*.ps1' -File -ErrorAction Stop |
        ForEach-Object { . $_.FullName }
    InitialActions
    if ($Global:Failed) { throw 'Sophia framework initialization failed.' }

    . $PresetPath
    if ($Global:Failed) { throw 'Sophia preset reported failure.' }

    # InitialActions can exit with code zero on failure. Only reaching here proves completion.
    Set-Content -LiteralPath $CompletionPath -Value 'completed' -ErrorAction Stop
}
catch {
    Write-Error -ErrorRecord $_ -ErrorAction Continue
    exit 1
}
