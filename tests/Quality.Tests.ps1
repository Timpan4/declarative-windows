Describe "repository quality checks" {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
    }

    It "parses all PowerShell scripts" {
        $scripts = Get-ChildItem -Path $repoRoot -Recurse -File -Filter "*.ps1" |
            Where-Object { $_.FullName -notmatch '\\.git\\' }

        foreach ($script in $scripts) {
            $tokens = $null
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty -Because "$($script.FullName) should parse"
        }
    }

    It "does not contain unresolved merge conflict markers" {
        $files = Get-ChildItem -Path $repoRoot -Recurse -File |
            Where-Object {
                $_.FullName -notmatch '\\.git\\' -and
                $_.Extension -in @(".ps1", ".md", ".json", ".xml")
            }

        $matches = foreach ($file in $files) {
            Select-String -LiteralPath $file.FullName -Pattern '^(<<<<<<<|\|\|\|\|\|\|\||=======|>>>>>>>)'
        }

        $matches | Should -BeNullOrEmpty
    }
}
