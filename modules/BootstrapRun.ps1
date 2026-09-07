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
            $state = Get-Content -Path $StatePath -Raw | ConvertFrom-Json
        }
        catch {
            $state = $null
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

function Save-State {
    param(
        [Parameter(Mandatory)]
        [object]$State,

        [Parameter(Mandatory)]
        [string]$StatePath
    )

    $State.lastUpdated = (Get-Date).ToString("o")
    $State | ConvertTo-Json -Depth 6 | Set-Content -Path $StatePath -Force
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
    [pscustomobject]$script:ProgressState | ConvertTo-Json -Depth 4 | Set-Content -Path $ProgressFile -Encoding UTF8 -Force
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

function Write-SummaryReport {
    param([string]$DesktopPath)

    $summaryPath = Join-Path $DesktopPath "Setup Summary.txt"
    $summaryLines = @(
        "Declarative Windows Setup Summary",
        "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        ""
    )

    foreach ($item in $SummaryItems) {
        $statusSymbol = switch ($item.Status) {
            "OK" { "✓" }
            "WARN" { "⚠" }
            "FAIL" { "✗" }
            default { $item.Status }
        }
        $summaryLines += "{0} {1}: {2}" -f $statusSymbol, $item.Step, $item.Message
    }

    Set-Content -Path $summaryPath -Value $summaryLines -Force
    return $summaryPath
}

function Add-FailedItem {
    param(
        [Parameter(Mandatory)]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$Item,

        [string]$Reason = ""
    )

    $FailedItems.Add([pscustomobject]@{
        Category = $Category
        Item     = $Item
        Reason   = $Reason
    })
}

function Write-FailedInstallsReport {
    param([string]$DesktopPath)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $lines = @(
        "Failed Installs - $timestamp",
        "========================================"
    )

    if ($FailedItems.Count -eq 0) {
        $lines += ""
        $lines += "No failures recorded. Everything installed successfully."
    }
    else {
        $categories = $FailedItems | Select-Object -ExpandProperty Category -Unique
        foreach ($category in $categories) {
            $lines += ""
            $lines += "${category}:"
            foreach ($entry in ($FailedItems | Where-Object { $_.Category -eq $category })) {
                $detail = if ($entry.Reason) { " - $($entry.Reason)" } else { "" }
                $lines += "  - $($entry.Item)$detail"
            }
        }
        $lines += ""
        $lines += "========================================"
        $lines += "Review the items above and install/apply them manually."
    }

    $lines | Set-Content -Path $FailedInstallsLog -Force

    if ($DesktopPath) {
        $desktopReport = Join-Path $DesktopPath "Failed Installs.txt"
        $lines | Set-Content -Path $desktopReport -Force
        return $desktopReport
    }

    return $FailedInstallsLog
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
