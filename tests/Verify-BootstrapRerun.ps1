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

    $Force = $false
    $SetupState = Initialize-State -StatePath $statePath -StepIds @('winget', 'optionalWinget', 'sophia', 'registry', 'postInstallTweaks', 'repo')
    foreach ($key in $SetupState.steps.Keys) { $SetupState.steps[$key].status = 'done' }
    foreach ($key in @('winget', 'optionalWinget', 'sophia', 'registry')) {
        Assert-Equal (Should-RunStep $key) $true "$key must reconcile even when saved as done"
    }
    Assert-Equal (Should-RunStep 'postInstallTweaks') $false 'Completed destructive tweaks stay skipped'
    Assert-Equal (Should-RunStep 'repo') $false 'Completed backup restoration stays skipped'

    . (Join-Path $PSScriptRoot '..\modules\WinGetInstall.ps1')
    foreach ($name in @('Invoke-WingetManifestInstall')) {
        $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $false)
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    function Write-Log { param($Message, $Level) }
    function Add-SummaryItem { param($Step, $Status, $Message) }
    function Set-StepState { param($StepId, $Status, $Message) }
    function Update-SetupProgress { }
    function Write-WingetOutput { }
    function Wait-ForNetwork { return $true }
    function Test-WingetPackageInstalled { param($PackageId) return $script:inventory.Contains($PackageId) }
    function Invoke-WingetPackageInstall {
        param($PackageId)
        $script:installs.Add($PackageId)
        $script:inventory.Add($PackageId)
        return @{ ExitCode = 0; Output = @() }
    }
    $script:inventory = [Collections.Generic.List[string]]::new()
    $script:installs = [Collections.Generic.List[string]]::new()
    $script:inventory.Add('Example.One')
    $manifestPath = Join-Path $fixtureRoot 'apps.json'
    $markerPath = Join-Path $fixtureRoot 'winget.completed'
    '{"Sources":[{"Packages":[{"PackageIdentifier":"Example.One"}]}]}' | Set-Content $manifestPath
    $installArgs = @{ ManifestPath = $manifestPath; MarkerPath = $markerPath; StepId = 'winget'; SummaryStep = 'WinGet'; ManifestLabel = 'apps.json'; MissingManifestMessage = 'missing' }
    Assert-Equal (Invoke-WingetManifestInstall @installArgs) $true 'Unchanged package inventory succeeds'
    Assert-Equal $script:installs.Count 0 'Unchanged packages are not reinstalled'
    '{"Sources":[{"Packages":[{"PackageIdentifier":"Example.One"},{"PackageIdentifier":"Example.Two"}]}]}' | Set-Content $manifestPath
    Assert-Equal (Invoke-WingetManifestInstall @installArgs) $true 'Changed manifest is reconciled'
    Assert-Equal ($script:installs -join ',') 'Example.Two' 'Only the added package is installed'
    $script:inventory.Remove('Example.One') | Out-Null
    Assert-Equal (Invoke-WingetManifestInstall @installArgs) $true 'Removed application is reconciled'
    Assert-Equal ($script:installs -join ',') 'Example.Two,Example.One' 'Only the removed application is reinstalled'

    $SophiaPreset = Join-Path $fixtureRoot 'preset.ps1'
    $SophiaMarker = Join-Path $fixtureRoot 'sophia.completed'
    'custom preset fixture' | Set-Content $SophiaPreset
    (Get-FileHash $SophiaPreset).Hash | Set-Content $SophiaMarker
    $script:sophiaRequested = $false
    function Get-SophiaScript { $script:sophiaRequested = $true; return $false }
    function Add-FailedItem { }
    $OptionalAppsOnly = $false
    $DryRun = $false
    $stepId = 'sophia'
    $sophiaStep = $ast.Find({ param($node)
        $node -is [Management.Automation.Language.IfStatementAst] -and $node.Extent.Text.StartsWith('if ($OptionalAppsOnly)') -and $node.Extent.Text.Contains('Step 3:')
    }, $true)
    . ([scriptblock]::Create($sophiaStep.Extent.Text))
    Assert-Equal $script:sophiaRequested $false 'Unchanged Sophia preset does not invoke the framework'
    'changed custom preset fixture' | Set-Content $SophiaPreset
    . ([scriptblock]::Create($sophiaStep.Extent.Text))
    Assert-Equal $script:sophiaRequested $true 'Changed Sophia preset reaches framework readiness'

    . (Join-Path $PSScriptRoot '..\modules\DeclarativeConfig.ps1')
    $script:registryValue = 1
    $script:registryWrites = 0
    $fakeKey = [pscustomobject]@{}
    $fakeKey | Add-Member ScriptMethod GetValue { param($name, $default, $options) return $script:registryValue }
    $fakeKey | Add-Member ScriptMethod GetValueKind { param($name) return 'DWord' }
    function Test-Path {
        param($LiteralPath)
        if ($LiteralPath -ne 'Registry::HKEY_CURRENT_USER\SyntheticFixture') { throw "Unexpected registry path: $LiteralPath" }
        return $true
    }
    function Get-Item { param($LiteralPath) return $fakeKey }
    function New-ItemProperty {
        param($LiteralPath, $Name, $Value, $PropertyType, [switch]$Force)
        $script:registryWrites++
        $script:registryValue = $Value
    }
    $registryFixture = Join-Path $fixtureRoot 'registry.json'
    '{"entries":[{"path":"Registry::HKEY_CURRENT_USER\\SyntheticFixture","name":"Setting","type":"DWORD","value":1}]}' | Set-Content $registryFixture
    $result = Invoke-RegistryConfig -ConfigPath $registryFixture
    Assert-Equal $result.Skipped 1 'Unchanged registry values are skipped'
    Assert-Equal $script:registryWrites 0 'Unchanged registry configuration performs no writes'
    '{"entries":[{"path":"Registry::HKEY_CURRENT_USER\\SyntheticFixture","name":"Setting","type":"DWORD","value":2}]}' | Set-Content $registryFixture
    $result = Invoke-RegistryConfig -ConfigPath $registryFixture
    Assert-Equal $result.Applied 1 'Changed registry input is applied'
    Assert-Equal $script:registryValue 2 'Registry reconciliation uses the new desired value'
    Write-Host 'Bootstrap rerun reconciliation checks passed.'
}
finally {
    # The generated absolute directory is the only cleanup target.
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}
