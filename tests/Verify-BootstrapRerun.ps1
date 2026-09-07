# Run with powershell.exe -NoProfile -File tests/Verify-BootstrapRerun.ps1.
# Only module functions and synthetic files are used; bootstrap is never executed.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\modules\BootstrapRun.ps1')

function Assert-Equal($Actual, $Expected, [string]$Because) {
    if ($Actual -cne $Expected) { throw "$Because. Expected '$Expected', got '$Actual'." }
}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
New-Item -Path $fixtureRoot -ItemType Directory | Out-Null
try {
    $statePath = Join-Path $fixtureRoot 'state.json'
    $state = Initialize-State -StatePath $statePath -StepIds @('winget', 'sophia')
    Assert-Equal ($state.steps.Keys -join ',') 'winget,sophia' 'Fresh state contains only requested steps'
    $state.steps.winget.status = 'done'
    Save-State -State $state -StatePath $statePath
    $state = Initialize-State -StatePath $statePath -StepIds @('winget', 'sophia')
    Assert-Equal $state.steps.Count 2 'Round trip preserves the step count'
    Assert-Equal $state.steps.winget.status 'done' 'Round trip preserves completion'

    $polluted = '{"Count":0,"Keys":[],"Values":[],"IsReadOnly":false,"IsFixedSize":false,"IsSynchronized":false,"SyncRoot":{},"winget":{"status":"done"},"custom":{"status":"done"}}' | ConvertFrom-Json
    $clean = Convert-StepsToHashtable $polluted
    Assert-Equal ($clean.Keys -join ',') 'winget,custom' 'Pollution is removed without dropping completion records'
    $dictionary = Convert-StepsToHashtable ([ordered]@{ winget = @{ status = 'done' } })
    Assert-Equal ($dictionary.Keys -join ',') 'winget' 'Dictionary entries are copied directly'
    $namedCount = Convert-StepsToHashtable ('{"Count":{"status":"done"}}' | ConvertFrom-Json)
    Assert-Equal $namedCount['Count'].status 'done' 'A real record named Count survives migration'
    Write-Host 'Bootstrap state checks passed.'
}
finally {
    # The generated absolute directory is the only cleanup target.
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}
