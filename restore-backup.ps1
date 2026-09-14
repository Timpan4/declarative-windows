#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ManifestPath,
    [string]$DestinationProfileRoot = $env:USERPROFILE,
    [ValidateSet('Merge', 'SkipExisting', 'Overwrite')]
    [string]$Mode = 'Merge',
    [string[]]$IncludeTags,
    [string[]]$RestoreApp,
    [switch]$UseBackupSettings,
    [switch]$Preview,
    [switch]$OpenRecoveredFiles,
    [switch]$Force,
    [string]$WorkingDirectory
)

$ErrorActionPreference = 'Stop'
if ($WorkingDirectory) { Set-Location -LiteralPath $WorkingDirectory -ErrorAction Stop }
. (Join-Path $PSScriptRoot 'modules\BackupManifest.ps1')
. (Join-Path $PSScriptRoot 'modules\RestorePlan.ps1')

$ManifestPath = Find-BackupManifest -Path $ManifestPath
if (-not $ManifestPath) { throw 'No backup selected. Pass -ManifestPath with an explicit manifest file from the candidates or another backup location.' }
$plan = New-RestorePlan -ManifestPath $ManifestPath -DestinationProfileRoot $DestinationProfileRoot -Mode $Mode -IncludeTags $IncludeTags -RestoreApp $RestoreApp -UseBackupSettings:$UseBackupSettings
Write-Host "Backup: $($plan.manifestPath)"
Write-Host "Destination profile: $($plan.profileRoot)"
Write-Host $plan.verification
$plan.items | Select-Object @{n='Action'; e={$_.action}}, @{n='Type'; e={$_.kind}}, @{n='Current path'; e={$_.path}}, @{n='Recovered path'; e={if ($_.outputPath -ne $_.path) { $_.outputPath }}}, @{n='Details'; e={$_.message}} | Format-List | Out-Host

if ($Preview -or $WhatIfPreference) { return $plan }
if ($Mode -eq 'Overwrite' -or $UseBackupSettings -or $RestoreApp) {
    $choice = Read-Host 'Apply the selections shown above, including any replacements? Type YES to continue'
    if ($choice -cne 'YES') { Write-Host 'Restore cancelled. No files changed.'; return }
}
# Force never selects replacement and cannot bypass the preview confirmation.
$report = @(Invoke-RestorePlan $plan)
$reportPath = Join-Path $plan.recoveryRoot 'restore-report.json'
if ($PSCmdlet.ShouldProcess($reportPath, 'Write restore results')) {
    Assert-NoBackupReparsePoint $reportPath
    $null = [IO.Directory]::CreateDirectory($plan.recoveryRoot)
    ConvertTo-Json -InputObject $report -Depth 8 | Set-Content -LiteralPath $reportPath -ErrorAction Stop
}
$report | Format-List type, path, outputPath, status, message, previousPaths | Out-Host
Write-Host "Restore report: $reportPath"
Write-Host "Open recovered files: explorer.exe `"$($plan.recoveryRoot)`""
if ($OpenRecoveredFiles -and $PSCmdlet.ShouldProcess($plan.recoveryRoot, 'Open recovered files')) {
    Start-Process explorer.exe -ArgumentList "`"$($plan.recoveryRoot)`""
}
if (@($report | Where-Object status -eq 'failed').Count) { throw "Restore completed with failures. Review $reportPath before retrying." }
$report
