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

    # Evaluate only the parameter and path declarations, never the orchestrator.
    $bootstrapPath = Join-Path $PSScriptRoot '..\bootstrap.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($bootstrapPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors) { throw ($parseErrors | Out-String) }
    $declarations = @($ast.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.AssignmentStatementAst] -and
        $_.Left.Extent.Text -in @('$SetupPath', '$ConfigRoot', '$LogFile', '$AppsJson', '$OptionalAppsJson', '$SophiaPreset', '$RegistryConfig', '$StateFile')
    })
    foreach ($folderName in @('canonical', 'staged', 'explicit')) {
        $selected = New-Item -Path (Join-Path $fixtureRoot $folderName) -ItemType Directory
        $ConfigRoot = $selected.FullName
        foreach ($declaration in $declarations) { . ([scriptblock]::Create($declaration.Extent.Text)) }
        Assert-Equal $AppsJson (Join-Path $selected.FullName 'apps.json') 'App configuration follows the selected root'
        Assert-Equal $OptionalAppsJson (Join-Path $selected.FullName 'optional-apps.json') 'Optional apps follow the selected root'
        Assert-Equal $SophiaPreset (Join-Path $selected.FullName 'Sophia-Preset.ps1') 'Sophia follows the selected root'
        Assert-Equal $RegistryConfig (Join-Path $selected.FullName 'config\registry.json') 'Registry follows the selected root'
        Assert-Equal $StateFile 'C:\Setup\state.json' 'Runtime state stays in the staged directory'
        Assert-Equal $LogFile 'C:\Setup\install.log' 'Runtime logs stay in the staged directory'
    }
    $defaultRoot = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'ConfigRoot' }
    Assert-Equal $defaultRoot.DefaultValue.Extent.Text '$PSScriptRoot' 'Launching from the repo or staging selects that directory by default'
    Write-Host 'Bootstrap configuration checks passed.'
}
finally {
    # The generated absolute directory is the only cleanup target.
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}
