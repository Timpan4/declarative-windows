function Get-WingetPackagesFromJson {
    param([string]$Path)

    try {
        $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $data = ConvertFrom-Json -InputObject $content -ErrorAction Stop
    }
    catch {
        throw "Invalid WinGet manifest '${Path}': $($_.Exception.Message)"
    }

    if (-not $content.TrimStart().StartsWith('{') -or $data -isnot [pscustomobject] -or
        $null -eq $data.PSObject.Properties['Sources'] -or $data.Sources -isnot [array]) {
        throw "Invalid WinGet manifest '${Path}': expected an object with a Sources array."
    }

    foreach ($property in $data.PSObject.Properties.Name) {
        if ($property -notin @('$schema', 'CreationDate', 'WinGetVersion', 'Sources')) {
            throw "Invalid WinGet manifest '${Path}': unsupported manifest field '$property'."
        }
    }
    $packages = @()

    for ($sourceIndex = 0; $sourceIndex -lt $data.Sources.Count; $sourceIndex++) {
        $source = $data.Sources[$sourceIndex]
        if ($source -isnot [pscustomobject] -or $null -eq $source.PSObject.Properties['Packages'] -or
            $source.Packages -isnot [array]) {
            throw "Invalid WinGet manifest '${Path}': Sources[$sourceIndex] must contain a Packages array."
        }

        foreach ($property in $source.PSObject.Properties.Name) {
            if ($property -notin @('Packages', 'SourceDetails')) {
                throw "Invalid WinGet manifest '${Path}': unsupported source field '$property'."
            }
        }
        $sourceName = ''
        if ($null -ne $source.PSObject.Properties['SourceDetails']) {
            if ($source.SourceDetails -isnot [pscustomobject] -or
                $source.SourceDetails.Name -isnot [string] -or [string]::IsNullOrWhiteSpace($source.SourceDetails.Name)) {
                throw "Invalid WinGet manifest '${Path}': SourceDetails requires a non-empty Name."
            }
            foreach ($property in $source.SourceDetails.PSObject.Properties) {
                if ($property.Name -notin @('Name', 'Identifier', 'Argument', 'Type') -or
                    $property.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($property.Value)) {
                    throw "Invalid WinGet manifest '${Path}': unsupported or invalid SourceDetails field '$($property.Name)'."
                }
            }
            $sourceName = $source.SourceDetails.Name
        }

        for ($packageIndex = 0; $packageIndex -lt $source.Packages.Count; $packageIndex++) {
            $package = $source.Packages[$packageIndex]
            if ($package -isnot [pscustomobject] -or $null -eq $package.PSObject.Properties['PackageIdentifier'] -or
                $package.PackageIdentifier -isnot [string] -or [string]::IsNullOrWhiteSpace($package.PackageIdentifier)) {
                throw "Invalid WinGet manifest '${Path}': Sources[$sourceIndex].Packages[$packageIndex].PackageIdentifier must be a non-empty string."
            }
            foreach ($property in $package.PSObject.Properties.Name) {
                if ($property -notin @('PackageIdentifier', 'Version')) {
                    throw "Invalid WinGet manifest '${Path}': unsupported package field '$property'. Supported fields are PackageIdentifier and Version."
                }
            }
            $version = ''
            if ($null -ne $package.PSObject.Properties['Version']) {
                if ($package.Version -isnot [string] -or [string]::IsNullOrWhiteSpace($package.Version)) {
                    throw "Invalid WinGet manifest '${Path}': Version must be a non-empty string."
                }
                $version = $package.Version
            }
            $packages += [pscustomobject]@{
                PackageId = $package.PackageIdentifier
                Source = $sourceName
                Version = $version
                SourceDetails = $source.SourceDetails
            }
        }
    }

    return ,@($packages | Sort-Object PackageId, Source, Version, @{ Expression = { $_.SourceDetails | ConvertTo-Json -Compress } } -Unique)
}

function Get-WingetPackageIdsFromJson {
    param([string]$Path)
    return ,@(Get-WingetPackagesFromJson -Path $Path | ForEach-Object { $_.PackageId } | Sort-Object -Unique)
}

function Update-SetupToolPath {
    $paths = @($env:Path -split ';')
    foreach ($target in @('Machine', 'User')) {
        $registeredPath = [Environment]::GetEnvironmentVariable('Path', $target)
        foreach ($entry in ($registeredPath -split ';')) {
            if ($entry) {
                $expanded = [Environment]::ExpandEnvironmentVariables($entry)
                if ($expanded -notin $paths) { $paths += $expanded }
            }
        }
    }
    $env:Path = $paths -join ';'
}

function Assert-WingetReady {
    Update-SetupToolPath
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'Prerequisite failure: WinGet is unavailable. Install or register Microsoft App Installer for this user, then rerun setup.'
    }
    $null = & winget --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Prerequisite failure: WinGet cannot start, exit code $LASTEXITCODE. Repair or register Microsoft App Installer for this user, then rerun setup."
    }
}

function Assert-WingetSources {
    param([object[]]$Packages)

    $registeredSources = @{}
    foreach ($package in $Packages) {
        if (-not $package.Source) { continue }
        if (-not $registeredSources.ContainsKey($package.Source)) {
            $output = & winget source export $package.Source 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Prerequisite failure: WinGet source '$($package.Source)' is unavailable." }
            $registeredSources[$package.Source] = ($output -join "`n") | ConvertFrom-Json -ErrorAction Stop
        }
        $registered = $registeredSources[$package.Source]
        foreach ($property in $package.SourceDetails.PSObject.Properties) {
            $field = if ($property.Name -eq 'Argument') { 'Arg' } else { $property.Name }
            if ($registered.$field -cne $property.Value) {
                throw "Prerequisite failure: registered WinGet source '$($package.Source)' does not match manifest $($property.Name)."
            }
        }
    }
}

function Test-WingetPackageInstalled {
    param([string]$PackageId, [string]$Source = '', [string]$Version = '')

    if ($Version) {
        # Export supplies installed versions as JSON; list's localized table has no version filter.
        $inventoryPath = Join-Path $env:TEMP "winget-inventory-$([guid]::NewGuid().ToString('N')).json"
        try {
            $arguments = @('export', '--output', $inventoryPath, '--include-versions', '--accept-source-agreements', '--disable-interactivity')
            if ($Source) { $arguments += @('--source', $Source) }
            $null = & winget @arguments 2>&1
            if ($LASTEXITCODE -ne 0) { throw "WinGet inventory failed with exit code $LASTEXITCODE." }
            $inventory = Get-Content -LiteralPath $inventoryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($inventory.Sources -isnot [array]) { throw 'WinGet returned an invalid inventory.' }
            foreach ($entry in $inventory.Sources) {
                if ($Source -and $entry.SourceDetails.Name -cne $Source) { continue }
                foreach ($package in $entry.Packages) {
                    if ($package.PackageIdentifier -ceq $PackageId -and $package.Version -ceq $Version) { return $true }
                }
            }
            return $false
        }
        finally {
            if (Test-Path -LiteralPath $inventoryPath) { Remove-Item -LiteralPath $inventoryPath -Force }
        }
    }

    $arguments = @('list', '--id', $PackageId, '--exact', '--accept-source-agreements', '--disable-interactivity')
    if ($Source) { $arguments += @('--source', $Source) }
    $result = & winget @arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return @($result -match ("(?:^|\s){0}(?:\s|$)" -f [regex]::Escape($PackageId))).Count -gt 0
}

function Write-WingetOutput {
    param(
        [object[]]$Output,
        [string]$Prefix = "WinGet:"
    )

    foreach ($line in @($Output)) {
        $text = "$line"
        $trimmed = $text.Trim()

        if (-not $trimmed) {
            continue
        }

        if ($trimmed -match '^[\|/\\-]+$') {
            continue
        }

        if ($trimmed -match '\d+(\.\d+)?\s*(KB|MB|GB)\s*/\s*\d+(\.\d+)?\s*(KB|MB|GB)') {
            continue
        }

        Write-Log "$Prefix $text" -Level INFO
    }
}

function Test-WingetRequiresUnelevatedRetry {
    param([object[]]$Output)

    foreach ($line in @($Output)) {
        if ("$line" -match "cannot be run from an administrator context|cannot be run as administrator|administrator context is not supported") {
            return $true
        }
    }

    return $false
}

function Update-WingetProgressFromLine {
    param(
        [string]$Line,
        [string]$Phase,
        [string]$Mode
    )

    if ($Line -match '^\((\d+)/(\d+)\)\s+Found .* \[(.+?)\]') {
        $packageIndex = [int]$Matches[1]
        $packageTotal = [int]$Matches[2]
        $packageId = $Matches[3]
        $lastPackage = $script:ProgressState.currentPackage

        Update-SetupProgress -Phase $Phase -Status ("Installing package {0} of {1}" -f $packageIndex, $packageTotal) -CurrentPackage $packageId -PackageIndex $packageIndex -PackageTotal $packageTotal -Mode $Mode

        if ($lastPackage -ne $packageId) {
            Write-Log ("Installing [{0}/{1}]: {2} ({3})" -f $packageIndex, $packageTotal, $packageId, $Mode) -Level INFO
        }

        return
    }

    if ($Line -match 'Starting package install') {
        $currentPackage = $script:ProgressState.currentPackage
        if ($currentPackage) {
            Update-SetupProgress -Phase $Phase -Status "Running installer" -CurrentPackage $currentPackage -Mode $Mode
        }
        return
    }

    if ($Line -match 'Successfully installed') {
        $currentPackage = $script:ProgressState.currentPackage
        if ($currentPackage) {
            Update-SetupProgress -Phase $Phase -Status "Installed successfully" -CurrentPackage $currentPackage -Mode $Mode
        }
    }
}

function Invoke-WingetPackageInstall {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,

        [string]$Source = '',

        [string]$Version = '',

        [switch]$Unelevated,

        [string]$Mode = 'admin',

        [int]$PackageIndex = 0,

        [int]$PackageTotal = 0,

        [int]$TimeoutSeconds = 14400,

        [Threading.CancellationToken]$CancellationToken = [Threading.CancellationToken]::None
    )

    $arguments = @(
        'install', '--id', $PackageId, '--exact',
        '--accept-package-agreements', '--accept-source-agreements'
    )
    if ($Source) { $arguments += @('--source', $Source) }
    if ($Version) { $arguments += @('--version', $Version) }

    if (-not $Unelevated) {
        $output = New-Object System.Collections.Generic.List[string]

        & winget @arguments 2>&1 | ForEach-Object {
            $line = $_.ToString()
            $output.Add($line)
            Update-WingetProgressFromLine -Line $line -Phase 'Installing packages' -Mode $Mode
        }

        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = @($output)
        }
    }

    $runnerPath = Join-Path $env:TEMP "winget-install-runner-$(Get-Random).ps1"
    $resultPath = Join-Path $env:TEMP "winget-install-result-$(Get-Random).json"
    $taskName = "WingetInstallUnelevated-$(Get-Random)"
    $taskRegistered = $false
    $result = [pscustomobject]@{ ExitCode = 1; Output = @(); RemainingWork = $false }

    try {
        $CancellationToken.ThrowIfCancellationRequested()
        $escapedPackageId = $PackageId.Replace("'", "''")
        $escapedResultPath = $resultPath.Replace("'", "''")
        $escapedProgressFile = $ProgressFile.Replace("'", "''")
        $serializedArguments = ($arguments | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ', '
        $runnerContent = @"
`$Host.UI.RawUI.WindowTitle = 'WinGet User-Scope Retry'

function Update-ProgressFile {
    param(
        [string]`$Phase,
        [string]`$Status,
        [string]`$CurrentPackage,
        [int]`$PackageIndex = 0,
        [int]`$PackageTotal = 0
    )

    [pscustomobject]@{
        phase = `$Phase
        status = `$Status
        currentPackage = `$CurrentPackage
        packageIndex = `$PackageIndex
        packageTotal = `$PackageTotal
        mode = 'user'
        lastUpdated = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 4 | Set-Content -Path '$escapedProgressFile' -Encoding UTF8 -Force
}

Write-Host 'Starting user-scope WinGet retry...' -ForegroundColor Cyan
Write-Host 'This window will show package installs that cannot run as administrator.' -ForegroundColor Cyan

`$output = New-Object System.Collections.Generic.List[string]
`$exitCode = 1
try {
Update-ProgressFile -Phase 'Retrying user-scope packages' -Status 'Installing package $PackageIndex of $PackageTotal' -CurrentPackage '$escapedPackageId' -PackageIndex $PackageIndex -PackageTotal $PackageTotal
`$arguments = @($serializedArguments)
& winget @arguments 2>&1 | ForEach-Object {
    `$line = `$_.ToString()
    `$output.Add(`$line)
    Write-Host `$line

    if (`$line -match 'Starting package install') {
        Update-ProgressFile -Phase 'Retrying user-scope packages' -Status 'Running installer' -CurrentPackage '$escapedPackageId' -PackageIndex $PackageIndex -PackageTotal $PackageTotal
    }
    elseif (`$line -match 'Successfully installed') {
        Update-ProgressFile -Phase 'Retrying user-scope packages' -Status 'Installed successfully' -CurrentPackage '$escapedPackageId' -PackageIndex $PackageIndex -PackageTotal $PackageTotal
    }
}

`$exitCode = `$LASTEXITCODE
}
catch { `$output.Add(`$_.Exception.Message) }
Write-Host "WinGet retry finished with exit code `$exitCode" -ForegroundColor Cyan
`$json = [pscustomobject]@{
    Completed = `$true
    ExitCode = `$exitCode
    Output = @(`$output)
} | ConvertTo-Json -Depth 5
`$temporaryResult = '$escapedResultPath.tmp'
`$bytes = [Text.UTF8Encoding]::new(`$false).GetBytes(`$json)
`$stream = [IO.File]::Open(`$temporaryResult, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    `$stream.Write(`$bytes, 0, `$bytes.Length)
    `$stream.Flush(`$true)
}
finally { `$stream.Dispose() }
[IO.File]::Move(`$temporaryResult, '$escapedResultPath')
"@

        Set-Content -Path $runnerPath -Value $runnerContent -Encoding UTF8 -Force

        $taskUser = if ($env:USERDOMAIN) { "$($env:USERDOMAIN)\$($env:USERNAME)" } else { $env:USERNAME }
        $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$runnerPath`""
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId $taskUser -LogonType Interactive -RunLevel Limited

        # On-demand only: a timer trigger can launch the installer a second time.
        $null = Register-ScheduledTask -TaskName $taskName -Action $taskAction -Principal $taskPrincipal -Force -ErrorAction Stop
        $taskRegistered = $true

        Start-ScheduledTask -TaskName $taskName -ErrorAction Stop

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            $CancellationToken.ThrowIfCancellationRequested()
            if (Test-Path -LiteralPath $resultPath) {
                break
            }
            $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
            $info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop
            # SCHED_S_TASK_HAS_NOT_RUN is 0x41303; a new task can briefly remain Ready.
            if ($task.State -notin @('Running', 'Queued') -and $info.LastTaskResult -ne 0x41303) {
                if (Test-Path -LiteralPath $resultPath) { break }
                throw "Non-admin scheduled task ended without a complete result, task exit code $($info.LastTaskResult)."
            }
            Start-Sleep -Seconds 2
        }

        if (-not (Test-Path -LiteralPath $resultPath)) {
            throw 'Timed out waiting for non-admin WinGet install to finish'
        }

        $published = Get-Content -LiteralPath $resultPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($published -isnot [pscustomobject] -or $published.Completed -isnot [bool] -or -not $published.Completed -or
            ($published.ExitCode -isnot [int] -and $published.ExitCode -isnot [long]) -or
            $published.ExitCode -lt [int]::MinValue -or $published.ExitCode -gt [int]::MaxValue -or $published.Output -isnot [array] -or
            @($published.Output | Where-Object { $_ -isnot [string] }).Count) {
            throw 'Malformed or incomplete non-admin WinGet result.'
        }
        $result.ExitCode = $published.ExitCode
        $result.Output = @($published.Output)
    }
    catch {
        $result.Output = @("Non-admin scheduled task failed: $($_.Exception.Message)")
    }
    finally {
        $settled = -not $taskRegistered
        if ($taskRegistered) {
            try {
                $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
                if ($task.State -in @('Running', 'Queued')) {
                    Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop
                    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
                }
                $settled = $task.State -in @('Ready', 'Disabled')
                if ($settled) {
                    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
                }
            }
            catch { $result.Output += "Scheduled task cleanup failed: $($_.Exception.Message)" }
        }
        if ($settled) {
            foreach ($path in @($runnerPath, $resultPath, "$resultPath.tmp")) {
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
            }
        }
        else {
            $result.ExitCode = 1
            $result.RemainingWork = $true
            $result.Output += "Remaining work: scheduled task '$taskName' could not be confirmed stopped. Retained runner '$runnerPath' and result '$resultPath'; settle this task before retrying."
        }
    }
    return $result
}

function Get-WingetFailureReason {
    param([object]$Result)

    $outputText = $Result.Output -join "`n"
    $code = '0x{0:X8}' -f ($Result.ExitCode -band 0xFFFFFFFFL)
    # Summaries use known diagnostic categories, never arbitrary installer output or URLs.
    $cause = if ($Result.RemainingWork) {
        'Installer task still active or unknown; settle the retained task listed in install.log before retrying'
    }
    elseif ($code -eq '0x8A150011' -or $outputText -match 'installer hash does not match|hash mismatch') {
        'Integrity failure: installer hash mismatch'
    }
    elseif ($outputText -match 'Failed to (open|update) (the )?(package )?source|source.*unavailable|dependency.*failed|dependencies.*failed|App Installer.*(unavailable|not registered)') {
        'Prerequisite failure: package source, dependency or App Installer unavailable'
    }
    elseif ($outputText -match 'Timed out|cancelled|scheduled task|remaining work') {
        'Installer task failure: retry did not finish cleanly'
    }
    else { 'Installer failure' }
    return "$cause; WinGet exit code $($Result.ExitCode) ($code). See install.log for native output."
}

function Set-WingetPackageOutcome {
    param([string]$StepId, [object]$Package, [string]$Status, [object]$ExitCode = $null, [string]$Reason = '')

    if (-not $SetupState -or $DryRun) { return }
    $step = $SetupState.steps[$StepId]
    $outcomes = @($step.packages | Where-Object {
        $_ -and ($_.PackageId -cne $Package.PackageId -or $_.Source -cne $Package.Source -or $_.Version -cne $Package.Version)
    })
    $outcomes += [pscustomobject]@{
        PackageId = $Package.PackageId
        Source = $Package.Source
        Version = $Package.Version
        Status = $Status
        ExitCode = $ExitCode
        Reason = $Reason
        CheckedAt = (Get-Date).ToString('o')
    }
    $step | Add-Member -MemberType NoteProperty -Name packages -Value $outcomes -Force
    Save-State -State $SetupState -StatePath $StateFile
}

function Invoke-WingetManifestInstall {
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,

        [Parameter(Mandatory)]
        [string]$StepId,

        [Parameter(Mandatory)]
        [string]$SummaryStep,

        [Parameter(Mandatory)]
        [string]$MarkerPath,

        [Parameter(Mandatory)]
        [string]$ManifestLabel,

        [Parameter(Mandatory)]
        [string]$MissingManifestMessage
    )

    if (-not (Test-Path $ManifestPath)) {
        Write-Log "WARNING: $ManifestLabel not found at $ManifestPath - skipping application import" -Level WARNING
        Add-SummaryItem -Step $SummaryStep -Status "FAIL" -Message $MissingManifestMessage
        Set-StepState -StepId $StepId -Status "failed" -Message $MissingManifestMessage
        return $false
    }

    try {
        Write-Log "Found $ManifestLabel at $ManifestPath" -Level INFO

        $packages = Get-WingetPackagesFromJson -Path $ManifestPath
        if (-not $packages -or $packages.Count -eq 0) {
            Write-Log "$ManifestLabel contains no packages to install" -Level WARNING
            Add-SummaryItem -Step $SummaryStep -Status "WARN" -Message "No packages found in $ManifestLabel"
            Set-StepState -StepId $StepId -Status "done" -Message "No packages found"
            return $true
        }

        Assert-WingetReady
        Assert-WingetSources -Packages $packages
        Set-StepState -StepId $StepId -Status 'pending' -Message 'Checking package inventory'
        $appsHash = (Get-FileHash -Path $ManifestPath -Algorithm SHA256).Hash
        $markerHash = $null
        if (Test-Path $MarkerPath) {
            $markerHash = (Get-Content -Path $MarkerPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
        }

        $missingPackages = New-Object System.Collections.Generic.List[object]
        $installedCount = 0
        $totalPackages = $packages.Count

        Update-SetupProgress -Phase 'Scanning packages' -Status ("Checking package 1 of {0}" -f $totalPackages) -CurrentPackage '' -PackageIndex 0 -PackageTotal $totalPackages -Mode 'admin'

        for ($index = 0; $index -lt $totalPackages; $index++) {
            $package = $packages[$index]
            $packageId = $package.PackageId
            $packageArguments = @{ PackageId = $packageId; Source = $package.Source; Version = $package.Version }
            $currentNumber = $index + 1

            Update-SetupProgress -Phase 'Scanning packages' -Status ("Checking package {0} of {1}" -f $currentNumber, $totalPackages) -CurrentPackage $packageId -PackageIndex $currentNumber -PackageTotal $totalPackages -Mode 'admin'
            Write-Log "[$currentNumber/$totalPackages] Checking package: $packageId" -Level INFO

            if (Test-WingetPackageInstalled @packageArguments) {
                $installedCount++
                Set-WingetPackageOutcome -StepId $StepId -Package $package -Status verified
                Write-Log "[$currentNumber/$totalPackages] Already installed: $packageId" -Level INFO
            }
            else {
                $missingPackages.Add($package)
                Write-Log "[$currentNumber/$totalPackages] Missing: $packageId" -Level INFO
            }
        }

        Write-Log ("Package scan complete for {0}: {1} missing, {2} already installed" -f $ManifestLabel, $missingPackages.Count, $installedCount) -Level INFO

        if ($missingPackages.Count -eq 0) {
            Write-Log "All packages from $ManifestLabel are already installed" -Level SUCCESS
            Set-Content -Path $MarkerPath -Value $appsHash -Force
            Add-SummaryItem -Step $SummaryStep -Status "OK" -Message "Already up to date ($MarkerPath)"
            Set-StepState -StepId $StepId -Status "done" -Message "Already up to date"
            return $true
        }

        if ($markerHash -and $markerHash -ne $appsHash) {
            Write-Log "$ManifestLabel changed since last WinGet run" -Level INFO
        }

        # Let WinGet contact the required source and installer endpoints only when packages are missing.
        Write-Log "Keep this window open. Some installers may open their own windows or ask for confirmation." -Level INFO
        Write-Log "Installing $($missingPackages.Count) missing packages from $ManifestLabel" -Level INFO
        Update-SetupProgress -Phase 'Installing packages' -Status ("Installing 1 of {0}" -f $missingPackages.Count) -CurrentPackage '' -PackageIndex 0 -PackageTotal $missingPackages.Count -Mode 'admin'

        $installedPackages = [System.Collections.Generic.List[string]]::new()
        $unverifiedPackages = [System.Collections.Generic.List[string]]::new()
        $failedPackages = [System.Collections.Generic.List[string]]::new()
        $packageNumber = 0

        foreach ($package in $missingPackages) {
            $packageId = $package.PackageId
            $packageArguments = @{ PackageId = $packageId; Source = $package.Source; Version = $package.Version }
            $packageLabel = $packageId
            if ($package.Source) { $packageLabel += " [source: $($package.Source)]" }
            if ($package.Version) { $packageLabel += " [version: $($package.Version)]" }
            $packageNumber++
            $installed = $false
            $verified = $false
            $unverified = $false

            Write-Log ("Installing [{0}/{1}]: {2} (admin)" -f $packageNumber, $missingPackages.Count, $packageId) -Level INFO
            Update-SetupProgress -Phase 'Installing packages' -Status ("Installing package {0} of {1}" -f $packageNumber, $missingPackages.Count) -CurrentPackage $packageId -PackageIndex $packageNumber -PackageTotal $missingPackages.Count -Mode 'admin'

            $installResult = Invoke-WingetPackageInstall @packageArguments -Mode 'admin' -PackageIndex $packageNumber -PackageTotal $missingPackages.Count
            Write-WingetOutput -Output $installResult.Output -Prefix "WinGet:"
            $finalResult = $installResult

            if (Test-WingetPackageInstalled @packageArguments) {
                $installed = $true
                $verified = $true
            }
            elseif (Test-WingetRequiresUnelevatedRetry -Output $installResult.Output) {
                Write-Log "Retrying $packageId in a non-administrator session" -Level INFO
                Write-Log "A second PowerShell window may appear for user-scope installers. Leave it open until it finishes." -Level INFO
                Update-SetupProgress -Phase 'Retrying user-scope packages' -Status ("Retrying package {0} of {1}" -f $packageNumber, $missingPackages.Count) -CurrentPackage $packageId -PackageIndex $packageNumber -PackageTotal $missingPackages.Count -Mode 'user'

                $retryResult = Invoke-WingetPackageInstall @packageArguments -Unelevated -Mode 'user' -PackageIndex $packageNumber -PackageTotal $missingPackages.Count
                Write-WingetOutput -Output $retryResult.Output -Prefix "WinGet (user):"
                $finalResult = $retryResult

                if (-not $retryResult.RemainingWork -and (Test-WingetPackageInstalled @packageArguments)) {
                    $installed = $true
                    $verified = $true
                }
                elseif ($retryResult.ExitCode -eq 0) {
                    $installed = $true
                    $unverified = $true
                }
                else {
                    Write-Log "Non-admin WinGet install exited with code $($retryResult.ExitCode) for $packageId" -Level WARNING
                }
            }
            elseif ($installResult.ExitCode -eq 0) {
                $installed = $true
                $unverified = $true
            }
            else {
                Write-Log "WinGet install exited with code $($installResult.ExitCode) for $packageId" -Level WARNING
            }

            if ($verified) {
                $installedPackages.Add($packageId)
                Set-WingetPackageOutcome -StepId $StepId -Package $package -Status verified -ExitCode $finalResult.ExitCode
                Write-Log "Successfully installed and verified $packageId" -Level SUCCESS
                continue
            }

            if ($unverified) {
                $unverifiedPackages.Add($packageId)
                $reason = 'Verification uncertain: WinGet returned exit code 0, but inventory did not verify the requested package. Setup will check again on the next run.'
                Set-WingetPackageOutcome -StepId $StepId -Package $package -Status unverified -ExitCode $finalResult.ExitCode -Reason $reason
                Add-FailedItem -Category "$SummaryStep Verification" -Item $packageLabel -Reason $reason -Status WARN
                Write-Log "WARNING: $packageId install reported success, but winget list did not verify it" -Level WARNING
                continue
            }

            if (-not $installed) {
                $failedPackages.Add($packageId)
                $reason = Get-WingetFailureReason -Result $finalResult
                Set-WingetPackageOutcome -StepId $StepId -Package $package -Status failed -ExitCode $finalResult.ExitCode -Reason $reason
                Add-FailedItem -Category $SummaryStep -Item $packageLabel -Reason $reason
                Write-Log "WARNING: $packageId failed to install" -Level WARNING
                if ($finalResult.RemainingWork) { throw $reason }
            }
        }

        $failCount = @($failedPackages).Count
        $unverifiedCount = @($unverifiedPackages).Count

        if ($failCount -eq 0) {
            Update-SetupProgress -Phase 'Installing packages' -Status 'Completed' -CurrentPackage '' -PackageIndex $missingPackages.Count -PackageTotal $missingPackages.Count -Mode 'admin'
            Write-Log "WinGet install from $ManifestLabel completed successfully" -Level SUCCESS

            if ($unverifiedCount -gt 0) {
                Add-SummaryItem -Step $SummaryStep -Status "WARN" -Message "Installed $($installedPackages.Count) package(s); $unverifiedCount verification warning(s)"
                Set-StepState -StepId $StepId -Status "unverified" -Message "Installed with $unverifiedCount verification warning(s)"
            }
            else {
                Set-Content -Path $MarkerPath -Value $appsHash -Force
                Add-SummaryItem -Step $SummaryStep -Status "OK" -Message "Installed $($installedPackages.Count) package(s)"
                Set-StepState -StepId $StepId -Status "done" -Message "Installed $($installedPackages.Count) package(s)"
            }

            return $true
        }

        Update-SetupProgress -Phase 'Installing packages' -Status ("Completed with {0} failure(s)" -f $failCount) -CurrentPackage '' -PackageIndex ($missingPackages.Count - $failCount) -PackageTotal $missingPackages.Count -Mode 'admin'
        Write-Log "WinGet install from $ManifestLabel finished; $failCount package(s) failed" -Level WARNING

        $warningSuffix = if ($unverifiedCount -gt 0) { "; $unverifiedCount verification warning(s)" } else { "" }
        Add-SummaryItem -Step $SummaryStep -Status "WARN" -Message "$failCount package(s) failed$warningSuffix - see Failed Installs.txt"
        Set-StepState -StepId $StepId -Status "failed" -Message "$failCount package(s) failed$warningSuffix"
        return $false
    }
    catch {
        Write-Log "ERROR during WinGet install from ${ManifestLabel}: $($_.Exception.Message)" -Level ERROR
        Add-SummaryItem -Step $SummaryStep -Status "FAIL" -Message "WinGet install failed: $($_.Exception.Message)"
        Set-StepState -StepId $StepId -Status "failed" -Message "WinGet install failed: $($_.Exception.Message)"
        return $false
    }
}
