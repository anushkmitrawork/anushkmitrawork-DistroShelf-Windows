Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Describe 'I.4 Profile commit AS-IS contract' {
    BeforeAll {
        $commitPath=Join-Path $PSScriptRoot '..\src\Profile\ProfileCommit.ps1'
        $commit=Get-Content -LiteralPath $commitPath -Raw
    }

    It 'promotes the existing accepted artifact without rebuilding or mirroring it' {
        $commit | Should -Match 'Move-DistroShelfDirectoryAtomic|Move-Item|Rename-Item'
        $commit | Should -Not -Match '(?i)Copy-Item|Compress-Archive|Expand-Archive|wsl\.exe\s+--export'
    }

    It 'requires and verifies the existing accepted artifact hash before promotion' {
        $commit | Should -Match '(?i)Get-FileHash'
        $commit | Should -Match '(?i)SHA256'
        $commit | Should -Match '(?i)Test-Path'
    }

    It 'routes failed promotion to Troubleshoot and does not silently replace the artifact' {
        $commit | Should -Match 'Move-DistroShelfTransactionToTroubleshoot'
    }
}
