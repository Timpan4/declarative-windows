BeforeAll {
    $repository = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repository 'preflight-backup.ps1'), [ref]$null, [ref]$null)
    foreach ($function in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        . ([scriptblock]::Create($function.Extent.Text))
    }
    # Execute production orchestration without requiring elevation for disposable fixtures.
    $backup = [scriptblock]::Create('[CmdletBinding(SupportsShouldProcess)]' + $ast.ParamBlock.Extent.Text + "`n" + '$PSScriptRoot = ''' + $repository.Replace("'", "''") + "'`n" + (($ast.EndBlock.Statements | ForEach-Object { $_.Extent.Text }) -join "`n"))
}

Describe 'backup preflight guards' {
    It 'copies included siblings while excluding nested directories and filename patterns' {
        $source = Join-Path $TestDrive 'source'
        $destination = Join-Path $TestDrive 'copied'
        foreach ($relative in @('node_modules', 'nested\node_modules', 'nested\keep')) {
            $folder = New-Item -ItemType Directory -Path (Join-Path $source $relative) -Force
            Set-Content -LiteralPath (Join-Path $folder.FullName 'file.txt') -Value $relative
        }
        Set-Content -LiteralPath (Join-Path $source 'nested\keep\scratch.tmp') -Value 'excluded'
        $result = & {
            [CmdletBinding(SupportsShouldProcess)]param()
            Copy-DirectoryWithRobocopy -Source $source -Destination $destination -ExcludePatterns @('**\\node_modules\\**', '*.tmp')
        }
        $result.Success | Should -BeTrue
        Test-Path (Join-Path $destination 'nested\keep\file.txt') | Should -BeTrue
        Test-Path (Join-Path $destination 'node_modules') | Should -BeFalse
        Test-Path (Join-Path $destination 'nested\node_modules') | Should -BeFalse
        Test-Path (Join-Path $destination 'nested\keep\scratch.tmp') | Should -BeFalse
    }

    It 'rejects invalid configuration before creating the destination' -ForEach @(
        @{ Labels = @('valid'); Patterns = @('nested\*.tmp'); Error = '*Unsupported backup exclusion*' }
        @{ Labels = @('Work.A', 'work-a'); Patterns = @(); Error = '*share identifier*' }
        @{ Labels = @('...'); Patterns = @(); Error = '*empty normalized identifier*' }
    ) {
        $configPath = Join-Path $TestDrive 'invalid.json'
        $destination = Join-Path $TestDrive 'not-created'
        @{
            knownFolders = @()
            extraPaths = @($Labels | ForEach-Object { @{ enabled = $true; label = $_; path = $TestDrive } })
            excludePatterns = $Patterns
            options = @{ backupRepoFiles = $false }
        } | ConvertTo-Json -Depth 5 | Set-Content $configPath
        { & $backup -DestinationRoot $destination -ConfigPath $configPath -BackupName 'session' -Force } | Should -Throw $Error
        Test-Path $destination | Should -BeFalse
    }

    It 'preserves all existing session content even with Force' {
        $destination = Join-Path $TestDrive 'existing'
        $session = New-Item -ItemType Directory -Path (Join-Path $destination 'declarative-windows-backup\session') -Force
        $manifest = Join-Path $session.FullName 'backup-manifest.json'
        $content = Join-Path $session.FullName 'saved.txt'
        Set-Content $manifest 'original manifest'
        Set-Content $content 'original content'
        $configPath = Join-Path $TestDrive 'config.json'
        '{}' | Set-Content $configPath
        { & $backup -DestinationRoot $destination -ConfigPath $configPath -BackupName 'session' -Force } | Should -Throw '*session already exists*'
        Get-Content $manifest | Should -Be 'original manifest'
        Get-Content $content | Should -Be 'original content'
        @(Get-ChildItem $session.FullName).Count | Should -Be 2
    }
}
