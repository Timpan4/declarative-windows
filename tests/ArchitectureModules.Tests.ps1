Describe "architecture module checks" {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
        $moduleRoot = Join-Path $repoRoot "modules"
        $bootstrap = Get-Content (Join-Path $repoRoot "bootstrap.ps1") -Raw
        $buildIso = Get-Content (Join-Path $repoRoot "build-iso.ps1") -Raw
        $applyRegistry = Get-Content (Join-Path $repoRoot "apply-registry.ps1") -Raw
        $modules = @{
            BootstrapRun = Get-Content (Join-Path $moduleRoot "BootstrapRun.ps1") -Raw
            WinGetInstall = Get-Content (Join-Path $moduleRoot "WinGetInstall.ps1") -Raw
            BackupManifest = Get-Content (Join-Path $moduleRoot "BackupManifest.ps1") -Raw
            StagedSetupPayload = Get-Content (Join-Path $moduleRoot "StagedSetupPayload.ps1") -Raw
            DeclarativeConfig = Get-Content (Join-Path $moduleRoot "DeclarativeConfig.ps1") -Raw
        }
    }

    It "has a deep BootstrapRun module for state progress and reports" {
        $bootstrap | Should -Match "BootstrapRun\.ps1"
        $modules.BootstrapRun | Should -Match "function Initialize-State"
        $modules.BootstrapRun | Should -Match "function Update-SetupProgress"
        $modules.BootstrapRun | Should -Match "function Invoke-BootstrapRunStep"
    }

    It "has a deep WinGetInstall module for per-package install classification" {
        $bootstrap | Should -Match "WinGetInstall\.ps1"
        $modules.WinGetInstall | Should -Match "function Invoke-WingetManifestInstall"
        $modules.WinGetInstall | Should -Match "Invoke-WingetPackageInstall"
        $modules.WinGetInstall | Should -Match "WinGet reported success but winget list did not verify the package"
        $modules.WinGetInstall | Should -Match "Retrying user-scope packages"
    }

    It "has a shared BackupManifest module for source and target remapping" {
        $modules.BackupManifest | Should -Match "function Find-BackupManifest"
        $modules.BackupManifest | Should -Match "function Get-BackupManifestRoot"
        $modules.BackupManifest | Should -Match "function Get-RestoreTargetMap"
        $modules.BackupManifest | Should -Match "function New-BackupManifest"
    }

    It "has a StagedSetupPayload module and requires it in ISO output" {
        $buildIso | Should -Match "StagedSetupPayload\.ps1"
        $modules.StagedSetupPayload | Should -Match "function Get-StagedSetupRequiredFiles"
        $modules.StagedSetupPayload | Should -Match "modules\\BootstrapRun\.ps1"
        $modules.StagedSetupPayload | Should -Match "modules\\DeclarativeConfig\.ps1"
    }

    It "has a DeclarativeConfig interface for registry application" {
        $applyRegistry | Should -Match "DeclarativeConfig\.ps1"
        $applyRegistry | Should -Match "Invoke-DeclarativeConfig"
        $modules.DeclarativeConfig | Should -Match "function Invoke-DeclarativeConfig"
        $modules.DeclarativeConfig | Should -Match "ValidateSet\(\""Registry\""\)"
    }
}
