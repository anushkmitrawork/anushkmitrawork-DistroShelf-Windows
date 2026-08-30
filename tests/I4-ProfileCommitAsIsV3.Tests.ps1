Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Describe 'I.4 Profile commit AS-IS contract' {
    BeforeAll {
        $commitPath=Join-Path $PSScriptRoot '..\src\Profile\ProfileCommit.ps1'
        $commit=Get-Content -LiteralPath $commitPath -Raw
    }

    It 'uses promotion of the existing accepted transaction output rather than rebuilding it' {
        $commit | Should -Match 'Move-DistroShelfDirectoryAtomic|Move-Item|Rename-Item'
        $commit | Should -Not -Match '(?i)Copy-Item|Compress-Archive|Expand-Archive|wsl\.exe\s+--export'
    }

    It 'checks the existing artifact and its SHA-256 before promotion' {
        $commit | Should -Match '(?i)Get-FileHash|Test-DistroShelfHashRecord|Hash'
        $commit | Should -Match '(?i)SHA256|sha256'
        $commit | Should -Match '(?i)Test-Path'
    }

    It 'preserves failed commits through the Troubleshoot path' {
        $commit | Should -Match 'Move-DistroShelfTransactionToTroubleshoot'
    }
}
