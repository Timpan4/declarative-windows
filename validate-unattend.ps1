#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$UnattendPath,

    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$SourceISO,

    [Parameter(Mandatory = $false)]
    [string]$SchemaDllPath
)

$ErrorActionPreference = "Stop"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-Success {
    param([string]$Message)
    Write-Host "[ OK ] $Message" -ForegroundColor Green
}

function Find-UnattendSchemaDll {
    param([string]$OverridePath)

    if ($OverridePath) {
        if (-not (Test-Path $OverridePath -PathType Leaf)) {
            throw "Specified schema DLL was not found: $OverridePath"
        }

        return (Resolve-Path $OverridePath).Path
    }

    $candidatePaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\WSIM\amd64\microsoft.componentstudio.componentplatforminterface.dll",
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\WSIM\x86\microsoft.componentstudio.componentplatforminterface.dll",
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\WSIM\arm64\microsoft.componentstudio.componentplatforminterface.dll",
        "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\WSIM\amd64\microsoft.componentstudio.componentplatforminterface.dll"
    )

    foreach ($candidatePath in $candidatePaths) {
        if (Test-Path $candidatePath -PathType Leaf) {
            return $candidatePath
        }
    }

    throw "Windows SIM schema DLL not found. Install the Windows ADK Deployment Tools + Windows System Image Manager, or pass -SchemaDllPath."
}

function Get-UnattendSchemaString {
    param([string]$DllPath)

    $assembly = [Reflection.Assembly]::LoadFile($DllPath)
    $resourceManagerName = ($assembly.GetManifestResourceNames() | Where-Object { $_ -like '*.resources' } | Select-Object -First 1)
    if (-not $resourceManagerName) {
        throw "Unable to find embedded resources in schema DLL: $DllPath"
    }

    $resourceManager = [System.Resources.ResourceManager]::new($resourceManagerName.Replace('.resources', ''), $assembly)
    $cultureCandidates = @(
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.CultureInfo]::GetCultureInfo('en-US'),
        [System.Globalization.CultureInfo]::GetCultureInfo('en-GB')
    )

    foreach ($culture in $cultureCandidates) {
        $resourceSet = $resourceManager.GetResourceSet($culture, $true, $true)
        if (-not $resourceSet) {
            continue
        }

        foreach ($entry in $resourceSet) {
            if ($entry.Name -like 'Unattend*') {
                return [System.Text.Encoding]::ASCII.GetString($entry.Value)
            }
        }
    }

    throw "Unable to extract unattend schema from $DllPath"
}

function Test-XmlAgainstSchema {
    param(
        [string]$XmlPath,
        [string]$SchemaText
    )

    $validationErrors = [System.Collections.Generic.List[string]]::new()
    $eventHandler = [System.Xml.Schema.ValidationEventHandler]{
        param($sender, $eventArgs)
        $validationErrors.Add($eventArgs.Message)
    }

    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.ValidationType = [System.Xml.ValidationType]::Schema
    $settings.ValidationFlags = [System.Xml.Schema.XmlSchemaValidationFlags]::ProcessIdentityConstraints
    $settings.add_ValidationEventHandler($eventHandler)

    $schemaReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($SchemaText))
    try {
        $settings.Schemas.Add('urn:schemas-microsoft-com:unattend', $schemaReader) | Out-Null
    }
    finally {
        $schemaReader.Dispose()
    }

    $xmlReader = [System.Xml.XmlReader]::Create($XmlPath, $settings)
    try {
        while ($xmlReader.Read()) {
        }
    }
    finally {
        $xmlReader.Dispose()
    }

    if ($validationErrors.Count -gt 0) {
        throw ("Schema validation failed: " + ($validationErrors -join ' | '))
    }
}

function Assert-UnattendPolicy {
    param(
        [xml]$Document,
        $NamespaceManager
    )

    $emptyProductKey = $Document.SelectSingleNode("//u:ProductKey[normalize-space(u:Key)='']", $NamespaceManager)
    if ($emptyProductKey) {
        throw "autounattend.xml contains an empty ProductKey block. Remove ProductKey entirely instead of leaving <Key></Key>."
    }

    if ($Document.SelectSingleNode('//u:DiskConfiguration', $NamespaceManager)) {
        throw "autounattend.xml must not contain DiskConfiguration. Disk and partition selection should remain manual."
    }

    if ($Document.SelectSingleNode('//u:InstallTo', $NamespaceManager)) {
        throw "autounattend.xml must not contain InstallTo. Disk and partition selection should remain manual."
    }

    $bootstrapCommand = $Document.SelectSingleNode("//u:FirstLogonCommands/u:SynchronousCommand/u:CommandLine[contains(., 'C:\Setup\bootstrap.ps1')]", $NamespaceManager)
    if (-not $bootstrapCommand) {
        throw "autounattend.xml must include a FirstLogonCommands entry that runs C:\Setup\bootstrap.ps1."
    }

    Write-Success "Unattend policy checks passed"
}

function Test-SourceIsoImage {
    param([string]$IsoPath)

    if (-not $IsoPath) {
        Write-Info "Source ISO not provided; skipping image validation"
        return
    }

    Write-Info "Validating Windows image inside source ISO"
    $mount = $null
    $resolvedIsoPath = (Resolve-Path $IsoPath).Path

    try {
        $mount = Mount-DiskImage -ImagePath $resolvedIsoPath -PassThru
        $driveLetter = ($mount | Get-Volume).DriveLetter
        if (-not $driveLetter) {
            throw "Mounted ISO does not have an accessible drive letter."
        }

        $sourceRoot = "${driveLetter}:\"
        $wimPath = Join-Path $sourceRoot 'sources\install.wim'
        $esdPath = Join-Path $sourceRoot 'sources\install.esd'
        $imagePath = if (Test-Path $wimPath) { $wimPath } elseif (Test-Path $esdPath) { $esdPath } else { $null }

        if (-not $imagePath) {
            throw "Source ISO is missing sources\install.wim or sources\install.esd."
        }

        $imageInfo = Get-WindowsImage -ImagePath $imagePath -ErrorAction Stop
        if (-not $imageInfo) {
            throw "Unable to read Windows image metadata from $imagePath."
        }

        $editionNames = @($imageInfo | Select-Object -ExpandProperty ImageName)
        Write-Success "Windows image validation passed: found $($editionNames.Count) edition(s)"
        Write-Info ("Editions: " + ($editionNames -join ', '))
    }
    finally {
        if ($mount) {
            Dismount-DiskImage -ImagePath $resolvedIsoPath -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

$resolvedUnattendPath = (Resolve-Path $UnattendPath).Path
Write-Info "Validating unattend file: $resolvedUnattendPath"

$xmlContent = Get-Content -Path $resolvedUnattendPath -Raw
$document = [System.Xml.XmlDocument]::new()
$document.PreserveWhitespace = $true
$document.LoadXml($xmlContent)
Write-Success "autounattend.xml is well-formed XML"

$resolvedSchemaDllPath = Find-UnattendSchemaDll -OverridePath $SchemaDllPath
Write-Info "Using schema DLL: $resolvedSchemaDllPath"
$schemaText = Get-UnattendSchemaString -DllPath $resolvedSchemaDllPath
Test-XmlAgainstSchema -XmlPath $resolvedUnattendPath -SchemaText $schemaText
Write-Success "autounattend.xml passed schema validation"

$namespaceManager = [System.Xml.XmlNamespaceManager]::new($document.NameTable)
[void]$namespaceManager.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
Assert-UnattendPolicy -Document $document -NamespaceManager $namespaceManager
Test-SourceIsoImage -IsoPath $SourceISO

Write-Success "Unattend validation completed successfully"
