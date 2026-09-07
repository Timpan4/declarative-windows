function Convert-StepsToHashtable {
    param([object]$Steps)

    $stepsTable = [ordered]@{}
    if ($Steps -is [System.Collections.IDictionary]) {
        foreach ($key in $Steps.Keys) {
            $stepsTable[$key] = $Steps[$key]
        }
    }
    elseif ($Steps) {
        foreach ($property in $Steps.PSObject.Properties) {
            # Old state files contain dictionary metadata alongside real records.
            if ($property.Name -in @('Count', 'Keys', 'Values', 'IsReadOnly', 'IsFixedSize', 'IsSynchronized', 'SyncRoot') -and
                -not $property.Value.status) {
                continue
            }
            $stepsTable[$property.Name] = $property.Value
        }
    }

    return $stepsTable
}

function Initialize-State {
    param(
        [string]$StatePath,
        [string[]]$StepIds
    )

    $state = $null
    if (Test-Path $StatePath) {
        try {
            $state = Get-Content -LiteralPath $StatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($state -isnot [pscustomobject] -or $state.version -ne '1' -or
                $state.steps -isnot [pscustomobject]) {
                throw 'Expected version 1 state with a steps object.'
            }
            $state.steps = Convert-StepsToHashtable -Steps $state.steps
            foreach ($id in $state.steps.Keys) {
                $step = $state.steps[$id]
                if ($step -isnot [pscustomobject] -or
                    $step.status -notin @('pending', 'done', 'failed', 'skipped', 'unverified') -or
                    $null -eq $step.PSObject.Properties['message'] -or
                    $null -eq $step.PSObject.Properties['lastRun']) {
                    throw "Invalid record for step '$id'."
                }
            }
        }
        catch {
            throw "Cannot safely resume state at '${StatePath}': $($_.Exception.Message) The original file is preserved. Recover it from a known-good copy before retrying; empty state could repeat completed actions."
        }
    }

    if (-not $state) {
        $state = [pscustomobject]@{
            version = "1"
            lastUpdated = (Get-Date).ToString("o")
            steps = [ordered]@{}
        }
    }

    $state.steps = Convert-StepsToHashtable -Steps $state.steps

    foreach ($stepId in $StepIds) {
        if (-not $state.steps.Contains($stepId)) {
            $state.steps[$stepId] = [pscustomobject]@{
                status = "pending"
                lastRun = $null
                message = ""
            }
        }
    }

    return $state
}

function Enter-BootstrapStateLock {
    param([Parameter(Mandatory)][string]$StatePath)

    try {
        # Keep the handle open for the whole run. The OS releases it after a crash.
        return [IO.File]::Open("$StatePath.lock", [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    }
    catch {
        throw "Cannot own bootstrap state at '${StatePath}'. Another setup run may be active: $($_.Exception.Message)"
    }
}

function Save-State {
    param(
        [Parameter(Mandatory)]
        [object]$State,

        [Parameter(Mandatory)]
        [string]$StatePath
    )

    if ($DryRun) { return }

    $State.lastUpdated = (Get-Date).ToString("o")
    $destination = [IO.Path]::GetFullPath($StatePath)
    $temporaryPath = "$destination.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($State | ConvertTo-Json -Depth 6))
        $stream = [IO.File]::Open($temporaryPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        }
        finally { $stream.Dispose() }
        if ([IO.File]::Exists($destination)) {
            [IO.File]::Replace($temporaryPath, $destination, "$destination.previous")
        }
        else {
            [IO.File]::Move($temporaryPath, $destination)
        }
    }
    finally {
        if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) }
    }
}

function Set-StepState {
    param(
        [Parameter(Mandatory)]
        [string]$StepId,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($DryRun) { return }

    if (-not $SetupState.steps.Contains($StepId)) {
        $SetupState.steps[$StepId] = [pscustomobject]@{
            status = "pending"
            lastRun = $null
            message = ""
        }
    }

    $SetupState.steps[$StepId].status = $Status
    $SetupState.steps[$StepId].lastRun = (Get-Date).ToString("o")
    $SetupState.steps[$StepId].message = $Message
    Save-State -State $SetupState -StatePath $StateFile
}

function Should-RunStep {
    param([string]$StepId)

    # These actions reconcile their inputs against package inventory, the preset
    # hash, or current registry values. A saved status cannot replace those checks.
    if ($StepId -in @('winget', 'optionalWinget', 'sophia', 'registry')) {
        return $true
    }

    if ($Force) {
        return $true
    }

    if (-not $SetupState) {
        return $true
    }

    if (-not $SetupState.steps.Contains($StepId)) {
        return $true
    }

    # Older runs incorrectly completed this step when the optional input was absent.
    if ($StepId -eq 'optionalShortcut' -and $SetupState.steps[$StepId].message -eq 'optional-apps.json not found') {
        return $true
    }

    return $SetupState.steps[$StepId].status -ne "done"
}

function Update-SetupProgress {
    param(
        [string]$Phase,
        [string]$Status,
        [string]$CurrentPackage,
        [Nullable[int]]$PackageIndex,
        [Nullable[int]]$PackageTotal,
        [string]$Mode,
        [switch]$ResetPackage
    )

    if ($DryRun) { return }

    if ($PSBoundParameters.ContainsKey('Phase')) {
        $script:ProgressState.phase = $Phase
    }

    if ($PSBoundParameters.ContainsKey('Status')) {
        $script:ProgressState.status = $Status
    }

    if ($ResetPackage) {
        $script:ProgressState.currentPackage = ""
        $script:ProgressState.packageIndex = 0
        $script:ProgressState.packageTotal = 0
    }

    if ($PSBoundParameters.ContainsKey('CurrentPackage')) {
        $script:ProgressState.currentPackage = $CurrentPackage
    }

    if ($PSBoundParameters.ContainsKey('PackageIndex') -and $null -ne $PackageIndex) {
        $script:ProgressState.packageIndex = $PackageIndex
    }

    if ($PSBoundParameters.ContainsKey('PackageTotal') -and $null -ne $PackageTotal) {
        $script:ProgressState.packageTotal = $PackageTotal
    }

    if ($PSBoundParameters.ContainsKey('Mode')) {
        $script:ProgressState.mode = $Mode
    }

    $script:ProgressState.lastUpdated = (Get-Date).ToString('o')
    [pscustomobject]$script:ProgressState | ConvertTo-Json -Depth 4 | Set-Content -Path $ProgressFile -Encoding UTF8 -Force -ErrorAction Stop
}

function Add-SummaryItem {
    param(
        [Parameter(Mandatory)]
        [string]$Step,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $SummaryItems.Add([pscustomobject]@{
        Step = $Step
        Status = $Status
        Message = $Message
    })
}

function Get-BootstrapRunResult {
    param([string]$FailureMessage = "")

    $records = @(
        foreach ($id in $SetupState.steps.Keys) {
            if ($id -eq 'summary') { continue }
            $step = $SetupState.steps[$id]
            $included = $id -in $RunStepIds
            $origin = if ($step.lastRun -and $step.lastRun -ge $RunStartedAt) { 'Current run' } else { 'Previous result' }
            [pscustomobject]@{
                Step = $id
                Status = $step.status
                Message = $step.message
                Origin = $origin
                Included = $included
            }
        }
    )
    $problems = @(
        foreach ($record in $records) {
            if ($record.Included -and $record.Status -notin @('done', 'skipped')) {
                [pscustomobject]@{
                    Category = $record.Step
                    Item = $record.Status
                    Reason = $record.Message
                    Status = if ($record.Status -eq 'unverified') { 'WARN' } else { 'FAIL' }
                }
            }
        }
        foreach ($item in $FailedItems) { $item }
        foreach ($item in $SummaryItems) {
            if ($item.Status -in @('FAIL', 'WARN')) {
                [pscustomobject]@{ Category = $item.Step; Item = $item.Status; Reason = $item.Message; Status = $item.Status }
            }
        }
        if ($FailureMessage) {
            [pscustomobject]@{ Category = 'Bootstrap'; Item = 'Fatal error'; Reason = $FailureMessage; Status = 'FAIL' }
        }
    )
    $failed = @($problems | Where-Object { $_.Status -ne 'WARN' }).Count -gt 0
    $status = if ($failed) { 'Failed' } elseif ($problems.Count) { 'Completed with warnings' } else { 'Completed' }
    if ($DryRun -and -not $FailureMessage) { $status = 'Preview'; $failed = $false }
    [pscustomobject]@{
        StartedAt = $RunStartedAt
        Mode = if ($OptionalAppsOnly) { 'Optional apps only' } else { 'Full setup' }
        Status = $status
        ExitCode = if ($failed) { 1 } else { 0 }
        Records = $records
        Problems = $problems
    }
}

function Write-SummaryReport {
    param([string]$DesktopPath, [Parameter(Mandatory)][object]$Result)

    $summaryPath = Join-Path $DesktopPath "Setup Summary.txt"
    $lines = @(
        "Declarative Windows Setup Summary",
        "Run started: $($Result.StartedAt)",
        "Mode: $($Result.Mode)",
        "Result: $($Result.Status)",
        ""
    )
    foreach ($record in $Result.Records) {
        $scope = if ($record.Included) { 'Included' } else { 'Not selected this run' }
        $lines += "{0}: {1} - {2} [{3}; {4}]" -f $record.Step, $record.Status, $record.Message, $record.Origin, $scope
    }
    foreach ($problem in $Result.Problems) {
        $lines += "{0} {1}: {2} - {3}" -f $problem.Status, $problem.Category, $problem.Item, $problem.Reason
    }
    Set-Content -LiteralPath $summaryPath -Value $lines -Force -ErrorAction Stop
    return $summaryPath
}

function Add-FailedItem {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Item,
        [string]$Reason = "",
        [ValidateSet('FAIL', 'WARN')][string]$Status = 'FAIL'
    )

    $FailedItems.Add([pscustomobject]@{
        Category = $Category
        Item = $Item
        Reason = $Reason
        Status = $Status
    })
}

function Write-FailedInstallsReport {
    param([string]$DesktopPath, [Parameter(Mandatory)][object]$Result)

    $lines = @(
        "Setup failures and warnings",
        "Run started: $($Result.StartedAt)",
        "Mode: $($Result.Mode)",
        "Result: $($Result.Status)",
        ""
    )
    if ($Result.Problems.Count -eq 0) {
        $lines += "No failures or warnings in the selected steps. See Setup Summary.txt for skipped and previous results."
    }
    else {
        foreach ($problem in $Result.Problems) {
            $lines += "{0} {1}: {2} - {3}" -f $problem.Status, $problem.Category, $problem.Item, $problem.Reason
        }
    }
    $reportPaths = @($FailedInstallsLog)
    if ($DesktopPath) {
        $desktopReport = Join-Path $DesktopPath "Failed Installs.txt"
        $reportPaths += $desktopReport
    }
    $writeErrors = @(
        foreach ($path in $reportPaths) {
            try { $lines | Set-Content -LiteralPath $path -Force -ErrorAction Stop }
            catch { $_.Exception.Message }
        }
    )
    if ($writeErrors.Count) { throw ($writeErrors -join '; ') }
    return $reportPaths[-1]
}

function Complete-BootstrapRun {
    param([string]$DesktopPath, [string]$FailureMessage = "")

    $result = Get-BootstrapRunResult -FailureMessage $FailureMessage
    $publicationErrors = @()
    if (-not $DryRun) {
        try {
            $null = Write-FailedInstallsReport -DesktopPath $DesktopPath -Result $result
            $null = Write-SummaryReport -DesktopPath $DesktopPath -Result $result
        }
        catch {
            $publicationErrors += "Report generation failed: $($_.Exception.Message)"
            $result = Get-BootstrapRunResult -FailureMessage ((@($FailureMessage) + $publicationErrors | Where-Object { $_ }) -join '; ')
        }
    }
    try {
        Update-SetupProgress -Phase $result.Status -Status "Windows setup bootstrap: $($result.Status)" -ResetPackage -Mode 'admin'
    }
    catch {
        $publicationErrors += "Progress publication failed: $($_.Exception.Message)"
        $result = Get-BootstrapRunResult -FailureMessage ((@($FailureMessage) + $publicationErrors | Where-Object { $_ }) -join '; ')
    }
    if ($publicationErrors.Count -and -not $DryRun) {
        # Publish the corrected failure result to each destination still writable.
        foreach ($writer in @('Write-FailedInstallsReport', 'Write-SummaryReport')) {
            try { $null = & $writer -DesktopPath $DesktopPath -Result $result }
            catch { Write-Log "Cannot publish corrected report: $($_.Exception.Message)" -Level ERROR }
        }
    }
    $level = if ($result.ExitCode) { 'ERROR' } elseif ($result.Status -eq 'Completed') { 'SUCCESS' } else { 'WARNING' }
    Write-Log "Windows Setup Bootstrap - $($result.Status)" -Level $level
    return $result
}

function Invoke-BootstrapRunStep {
    param(
        [Parameter(Mandatory)]
        [string]$StepId,

        [Parameter(Mandatory)]
        [string]$StepName,

        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [scriptblock]$DryRunAction,

        [switch]$OptionalAppsOnlySkip
    )

    if ($OptionalAppsOnlySkip) {
        Write-Log "Skipping $StepName (optional apps only mode)" -Level INFO
        return $null
    }

    if (-not (Should-RunStep -StepId $StepId)) {
        Write-Log "Skipping $StepName (already completed)" -Level INFO
        Add-SummaryItem -Step $StepName -Status "OK" -Message "Skipped (already completed)"
        return $true
    }

    if ($DryRun) {
        if ($DryRunAction) {
            return & $DryRunAction
        }

        Write-Log "Dry run - skipping $StepName" -Level WARNING
        Add-SummaryItem -Step $StepName -Status "WARN" -Message "Dry run: skipped"
        Set-StepState -StepId $StepId -Status "pending" -Message "Dry run: skipped"
        return $null
    }

    return & $Action
}
