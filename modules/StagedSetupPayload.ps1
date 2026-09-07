function Get-UnattendSetupFileReferences {
    param(
        [Parameter(Mandatory)]
        [string]$UnattendPath
    )

    $document = [xml](Get-Content -Path $UnattendPath -Raw)
    $namespaceManager = [System.Xml.XmlNamespaceManager]::new($document.NameTable)
    [void]$namespaceManager.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')

    $references = [System.Collections.Generic.List[string]]::new()
    $commandNodes = $document.SelectNodes('//u:FirstLogonCommands/u:SynchronousCommand/u:CommandLine', $namespaceManager)

    foreach ($commandNode in $commandNodes) {
        foreach ($match in [regex]::Matches($commandNode.InnerText, '(?i)\bC:\\Setup\\[^\s"'';]+')) {
            $references.Add($match.Value)
        }
    }

    return $references | Sort-Object -Unique
}

function Get-SetupPayloadRelativePaths {
    param([bool]$HasOptionalApps)

    @(
        'bootstrap.ps1'
        'apps.json'
        'Sophia-Preset.ps1'
        'restore-backup.ps1'
        'apply-registry.ps1'
        'modules\BootstrapRun.ps1'
        'modules\WinGetInstall.ps1'
        'modules\BackupManifest.ps1'
        'modules\DeclarativeConfig.ps1'
        'modules\Run-SophiaPreset.ps1'
        'config\registry.json'
        'config\backup.template.json'
    )
    if ($HasOptionalApps) { 'optional-apps.json' }
}

function Get-IsoSetupPayload {
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $paths = @('autounattend.xml') + @(Get-SetupPayloadRelativePaths -HasOptionalApps (
        Test-Path -LiteralPath (Join-Path $ProjectRoot 'optional-apps.json') -PathType Leaf
    ))
    foreach ($relativePath in $paths) {
        $source = Join-Path $ProjectRoot $relativePath
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Missing required payload file: $source"
        }
        $destination = if ($relativePath -eq 'autounattend.xml') {
            $relativePath
        }
        else {
            Join-Path 'sources\$OEM$\$1\Setup' $relativePath
        }
        [pscustomobject]@{ Source = $source; RelativePath = $destination }
    }
}

function Copy-IsoSetupPayload {
    param(
        [Parameter(Mandatory)][object[]]$Payload,
        [Parameter(Mandatory)][string]$WorkRoot
    )

    foreach ($file in $Payload) {
        $destination = Join-Path $WorkRoot $file.RelativePath
        [void][IO.Directory]::CreateDirectory((Split-Path $destination -Parent))
        Copy-Item -LiteralPath $file.Source -Destination $destination -Force -ErrorAction Stop
    }
}

function Get-StagedSetupRequiredFiles {
    param(
        [Parameter(Mandatory)][string]$WorkRoot,
        [Parameter(Mandatory)][bool]$HasOptionalApps
    )

    Join-Path $WorkRoot 'autounattend.xml'
    $stagedSetupRoot = Join-Path $WorkRoot 'sources\$OEM$\$1\Setup'
    foreach ($relativePath in (Get-SetupPayloadRelativePaths -HasOptionalApps $HasOptionalApps)) {
        Join-Path $stagedSetupRoot $relativePath
    }
}
function Validate-StagedIsoLayout {
    param(
        [Parameter(Mandatory)]
        [string]$WorkRoot,

        [Parameter(Mandatory)]
        [string]$UnattendPath,

        [Parameter(Mandatory)]
        [bool]$HasOptionalApps
    )

    $stagedSetupRoot = Join-Path $WorkRoot 'sources\$OEM$\$1\Setup'

    foreach ($stagedFile in (Get-StagedSetupRequiredFiles -WorkRoot $WorkRoot -HasOptionalApps $HasOptionalApps)) {
        if (-not (Test-Path $stagedFile -PathType Leaf)) {
            throw "Staged ISO is missing required file: $stagedFile"
        }
    }

    foreach ($setupReference in (Get-UnattendSetupFileReferences -UnattendPath $UnattendPath)) {
        $relativePath = $setupReference.Substring('C:\Setup\'.Length)
        $stagedReference = Join-Path $stagedSetupRoot $relativePath

        if (-not (Test-Path $stagedReference -PathType Leaf)) {
            throw "autounattend.xml references $setupReference, but staged ISO is missing $stagedReference"
        }
    }

    if (Get-Command Write-Success -ErrorAction SilentlyContinue) {
        Write-Success 'Staged ISO layout validation passed'
    }
    else {
        Write-Host 'Staged ISO layout validation passed' -ForegroundColor Green
    }
}
