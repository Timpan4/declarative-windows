function Get-WingetPackageIdsFromJson {
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

    $packageIds = @()

    for ($sourceIndex = 0; $sourceIndex -lt $data.Sources.Count; $sourceIndex++) {
        $source = $data.Sources[$sourceIndex]
        if ($source -isnot [pscustomobject] -or $null -eq $source.PSObject.Properties['Packages'] -or
            $source.Packages -isnot [array]) {
            throw "Invalid WinGet manifest '${Path}': Sources[$sourceIndex] must contain a Packages array."
        }

        for ($packageIndex = 0; $packageIndex -lt $source.Packages.Count; $packageIndex++) {
            $package = $source.Packages[$packageIndex]
            if ($package -isnot [pscustomobject] -or $null -eq $package.PSObject.Properties['PackageIdentifier'] -or
                $package.PackageIdentifier -isnot [string] -or [string]::IsNullOrWhiteSpace($package.PackageIdentifier)) {
                throw "Invalid WinGet manifest '${Path}': Sources[$sourceIndex].Packages[$packageIndex].PackageIdentifier must be a non-empty string."
            }
            $packageIds += $package.PackageIdentifier
        }
    }

    return ,@($packageIds | Sort-Object -Unique)
}

function Test-WingetPackageInstalled {
    param([string]$PackageId)

    $result = winget list --id $PackageId --exact 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return $result -match [regex]::Escape($PackageId)
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

        [switch]$Unelevated,

        [string]$Mode = 'admin',

        [int]$PackageIndex = 0,

        [int]$PackageTotal = 0,

        [int]$TimeoutSeconds = 14400
    )

    if (-not $Unelevated) {
        $output = New-Object System.Collections.Generic.List[string]
        $arguments = @(
            'install',
            '--id', $PackageId,
            '--exact',
            '--accept-package-agreements',
            '--accept-source-agreements'
        )

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

    try {
        $escapedPackageId = $PackageId.Replace("'", "''")
        $escapedResultPath = $resultPath.Replace("'", "''")
        $escapedProgressFile = $ProgressFile.Replace("'", "''")
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
Update-ProgressFile -Phase 'Retrying user-scope packages' -Status 'Installing package $PackageIndex of $PackageTotal' -CurrentPackage '$escapedPackageId' -PackageIndex $PackageIndex -PackageTotal $PackageTotal
winget install --id '$escapedPackageId' --exact --accept-package-agreements --accept-source-agreements 2>&1 | ForEach-Object {
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
Write-Host "WinGet retry finished with exit code `$exitCode" -ForegroundColor Cyan
[pscustomobject]@{
    ExitCode = `$exitCode
    Output = @(`$output)
} | ConvertTo-Json -Depth 5 | Set-Content -Path '$escapedResultPath' -Encoding UTF8 -Force
"@

        Set-Content -Path $runnerPath -Value $runnerContent -Encoding UTF8 -Force

        $taskUser = if ($env:USERDOMAIN) { "$($env:USERDOMAIN)\$($env:USERNAME)" } else { $env:USERNAME }
        $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$runnerPath`""
        $taskTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId $taskUser -LogonType Interactive -RunLevel Limited

        try {
            $null = Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Force -ErrorAction Stop
        }
        catch {
            return [pscustomobject]@{
                ExitCode = 1
                Output = @("Failed to create non-admin scheduled task", $_.Exception.Message)
            }
        }

        try {
            Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
        }
        catch {
            return [pscustomobject]@{
                ExitCode = 1
                Output = @("Failed to start non-admin scheduled task", $_.Exception.Message)
            }
        }

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            if (Test-Path $resultPath) {
                break
            }

            Start-Sleep -Seconds 2
        }

        if (-not (Test-Path $resultPath)) {
            return [pscustomobject]@{
                ExitCode = 1
                Output = @("Timed out waiting for non-admin WinGet install to finish")
            }
        }

        $result = Get-Content -Path $resultPath -Raw | ConvertFrom-Json
        $output = @()
        if ($null -ne $result.Output) {
            $output = @($result.Output)
        }

        return [pscustomobject]@{
            ExitCode = [int]$result.ExitCode
            Output = $output
        }
    }
    finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

        if (Test-Path $runnerPath) {
            Remove-Item -Path $runnerPath -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path $resultPath) {
            Remove-Item -Path $resultPath -Force -ErrorAction SilentlyContinue
        }
    }
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

        $packageIds = Get-WingetPackageIdsFromJson -Path $ManifestPath
        if (-not $packageIds -or $packageIds.Count -eq 0) {
            Write-Log "$ManifestLabel contains no packages to install" -Level WARNING
            Add-SummaryItem -Step $SummaryStep -Status "WARN" -Message "No packages found in $ManifestLabel"
            Set-StepState -StepId $StepId -Status "done" -Message "No packages found"
            return $true
        }

        $appsHash = (Get-FileHash -Path $ManifestPath -Algorithm SHA256).Hash
        $markerHash = $null
        if (Test-Path $MarkerPath) {
            $markerHash = (Get-Content -Path $MarkerPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
        }

        $missingPackages = New-Object System.Collections.Generic.List[string]
        $installedCount = 0
        $totalPackages = $packageIds.Count

        Update-SetupProgress -Phase 'Scanning packages' -Status ("Checking package 1 of {0}" -f $totalPackages) -CurrentPackage '' -PackageIndex 0 -PackageTotal $totalPackages -Mode 'admin'

        for ($index = 0; $index -lt $totalPackages; $index++) {
            $packageId = $packageIds[$index]
            $currentNumber = $index + 1

            Update-SetupProgress -Phase 'Scanning packages' -Status ("Checking package {0} of {1}" -f $currentNumber, $totalPackages) -CurrentPackage $packageId -PackageIndex $currentNumber -PackageTotal $totalPackages -Mode 'admin'
            Write-Log "[$currentNumber/$totalPackages] Checking package: $packageId" -Level INFO

            if (Test-WingetPackageInstalled -PackageId $packageId) {
                $installedCount++
                Write-Log "[$currentNumber/$totalPackages] Already installed: $packageId" -Level INFO
            }
            else {
                $missingPackages.Add($packageId)
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

        foreach ($packageId in @($missingPackages)) {
            $packageNumber++
            $installed = $false
            $verified = $false
            $unverified = $false

            Write-Log ("Installing [{0}/{1}]: {2} (admin)" -f $packageNumber, $missingPackages.Count, $packageId) -Level INFO
            Update-SetupProgress -Phase 'Installing packages' -Status ("Installing package {0} of {1}" -f $packageNumber, $missingPackages.Count) -CurrentPackage $packageId -PackageIndex $packageNumber -PackageTotal $missingPackages.Count -Mode 'admin'

            $installResult = Invoke-WingetPackageInstall -PackageId $packageId -Mode 'admin' -PackageIndex $packageNumber -PackageTotal $missingPackages.Count
            Write-WingetOutput -Output $installResult.Output -Prefix "WinGet:"

            if (Test-WingetPackageInstalled -PackageId $packageId) {
                $installed = $true
                $verified = $true
            }
            elseif (Test-WingetRequiresUnelevatedRetry -Output $installResult.Output) {
                Write-Log "Retrying $packageId in a non-administrator session" -Level INFO
                Write-Log "A second PowerShell window may appear for user-scope installers. Leave it open until it finishes." -Level INFO
                Update-SetupProgress -Phase 'Retrying user-scope packages' -Status ("Retrying package {0} of {1}" -f $packageNumber, $missingPackages.Count) -CurrentPackage $packageId -PackageIndex $packageNumber -PackageTotal $missingPackages.Count -Mode 'user'

                $retryResult = Invoke-WingetPackageInstall -PackageId $packageId -Unelevated -Mode 'user' -PackageIndex $packageNumber -PackageTotal $missingPackages.Count
                Write-WingetOutput -Output $retryResult.Output -Prefix "WinGet (user):"

                if (Test-WingetPackageInstalled -PackageId $packageId) {
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
                Write-Log "Successfully installed and verified $packageId" -Level SUCCESS
                continue
            }

            if ($unverified) {
                $unverifiedPackages.Add($packageId)
                Add-FailedItem -Category "$SummaryStep Verification" -Item $packageId -Reason "WinGet reported success but winget list did not verify the package" -Status WARN
                Write-Log "WARNING: $packageId install reported success, but winget list did not verify it" -Level WARNING
                continue
            }

            if (-not $installed) {
                $failedPackages.Add($packageId)
                Write-Log "WARNING: $packageId failed to install" -Level WARNING
            }
        }

        foreach ($packageId in $failedPackages) {
            Add-FailedItem -Category $SummaryStep -Item $packageId -Reason "Not installed after per-package install from $ManifestLabel"
            Write-Log "WARNING: $packageId still not installed after WinGet install from $ManifestLabel" -Level WARNING
        }

        $failCount = @($failedPackages).Count
        $unverifiedCount = @($unverifiedPackages).Count

        if ($failCount -eq 0) {
            Update-SetupProgress -Phase 'Installing packages' -Status 'Completed' -CurrentPackage '' -PackageIndex $missingPackages.Count -PackageTotal $missingPackages.Count -Mode 'admin'
            Write-Log "WinGet install from $ManifestLabel completed successfully" -Level SUCCESS
            Set-Content -Path $MarkerPath -Value $appsHash -Force

            if ($unverifiedCount -gt 0) {
                Add-SummaryItem -Step $SummaryStep -Status "WARN" -Message "Installed $($installedPackages.Count) package(s); $unverifiedCount verification warning(s)"
                Set-StepState -StepId $StepId -Status "unverified" -Message "Installed with $unverifiedCount verification warning(s)"
            }
            else {
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
