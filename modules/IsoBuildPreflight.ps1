function Get-IsoOutputPath {
    param(
        [Parameter(Mandatory)][string]$SourceISO,
        [Parameter(Mandatory)][string]$OutputISO
    )

    $provider = $null
    $drive = $null
    $outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
        $OutputISO, [ref]$provider, [ref]$drive
    )
    if ($provider.Name -ne 'FileSystem') {
        throw "ISO output must be a filesystem path: $OutputISO"
    }
    $fileName = [IO.Path]::GetFileName($outputPath)
    if ($fileName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw "Invalid ISO output filename: $fileName"
    }
    $sourcePath = (Get-Item -LiteralPath $SourceISO -ErrorAction Stop).FullName
    if ($outputPath -eq $sourcePath) {
        throw "Source and output ISO must be different files: $outputPath"
    }
    if (Test-Path -LiteralPath $outputPath) {
        throw "Output already exists; choose a new ISO path: $outputPath"
    }

    $outputDir = Split-Path $outputPath -Parent
    try {
        [void][IO.Directory]::CreateDirectory($outputDir)
        # Probe the actual filename and permissions without leaving an output file.
        # CreateNew never truncates a file created by another build.
        $probe = [IO.FileStream]::new(
            $outputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write,
            [IO.FileShare]::None, 4096, [IO.FileOptions]::DeleteOnClose
        )
        $probe.Dispose()
    }
    catch {
        throw "Cannot create ISO output '$outputPath': $($_.Exception.Message)"
    }
    return $outputPath
}

function Assert-IsoBuildSpace {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][object[]]$Payload,
        [Parameter(Mandatory)][string]$StagingDirectory,
        [Parameter(Mandatory)][string]$OutputDirectory
    )

    $sourceBytes = (Get-ChildItem -LiteralPath $SourceRoot -File -Recurse -Force -ErrorAction Stop |
        Measure-Object -Property Length -Sum).Sum
    $payloadBytes = ($Payload | ForEach-Object {
        (Get-Item -LiteralPath $_.Source -ErrorAction Stop).Length
    } | Measure-Object -Sum).Sum
    $estimatedBytes = [long]$sourceBytes + [long]$payloadBytes

    # Both the expanded source tree and the resulting ISO coexist during the build.
    # This is an input-sized estimate, not a guarantee about filesystem/ISO overhead.
    $requirements = @{}
    foreach ($directory in @($StagingDirectory, $OutputDirectory)) {
        $volume = Get-Volume -FilePath ($directory.TrimEnd('\') + '\') -ErrorAction Stop
        if (-not $volume.UniqueId -or $null -eq $volume.SizeRemaining) {
            throw "Cannot determine free space for '$directory'; choose a local volume with available space information."
        }
        if (-not $requirements.ContainsKey($volume.UniqueId)) {
            $requirements[$volume.UniqueId] = @{
                Required = [long]0
                Available = [long]$volume.SizeRemaining
                Locations = @()
            }
        }
        $requirements[$volume.UniqueId].Required += $estimatedBytes
        $requirements[$volume.UniqueId].Locations += $directory
    }

    foreach ($requirement in $requirements.Values) {
        $locations = $requirement.Locations -join ', '
        Write-Host "Space estimate for $($locations): $($requirement.Required) bytes required; $($requirement.Available) bytes available."
        if ($requirement.Available -lt $requirement.Required) {
            throw "Insufficient space for $($locations): estimated $($requirement.Required) bytes required, $($requirement.Available) available. Free space or change TEMP/output location."
        }
    }
}
