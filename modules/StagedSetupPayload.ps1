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

function Get-StagedSetupRequiredFiles {
    param(
        [Parameter(Mandatory)]
        [string]$WorkRoot,

        [Parameter(Mandatory)]
        [bool]$HasOptionalApps
    )

    $stagedSetupRoot = Join-Path $WorkRoot 'sources\$OEM$\$1\Setup'
    $requiredStagedFiles = @(
        (Join-Path $WorkRoot 'autounattend.xml'),
        (Join-Path $stagedSetupRoot 'bootstrap.ps1'),
        (Join-Path $stagedSetupRoot 'apps.json'),
        (Join-Path $stagedSetupRoot 'Sophia-Preset.ps1'),
        (Join-Path $stagedSetupRoot 'restore-backup.ps1'),
        (Join-Path $stagedSetupRoot 'apply-registry.ps1'),
        (Join-Path $stagedSetupRoot 'modules\BootstrapRun.ps1'),
        (Join-Path $stagedSetupRoot 'modules\WinGetInstall.ps1'),
        (Join-Path $stagedSetupRoot 'modules\BackupManifest.ps1'),
        (Join-Path $stagedSetupRoot 'modules\StagedSetupPayload.ps1'),
        (Join-Path $stagedSetupRoot 'modules\DeclarativeConfig.ps1'),
        (Join-Path $stagedSetupRoot 'config\registry.json'),
        (Join-Path $stagedSetupRoot 'config\backup.template.json')
    )

    if ($HasOptionalApps) {
        $requiredStagedFiles += Join-Path $stagedSetupRoot 'optional-apps.json'
    }

    return $requiredStagedFiles
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

    Write-Success 'Staged ISO layout validation passed'
}
