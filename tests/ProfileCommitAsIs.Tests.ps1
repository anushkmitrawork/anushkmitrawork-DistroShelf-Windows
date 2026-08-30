Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Describe 'Profile commit is AS-IS' {
    It 'does not rebuild, mirror, or transform the accepted artifact during commit' {
        $path=Join-Path $PSScriptRoot '..\src\Profile\ProfileCommit.ps1'
        $source=Get-Content -LiteralPath $path -Raw
        $source | Should -Match 'Move-DistroShelfDirectoryAtomic|Move-Item|Rename-Item'
        $source | Should -Not -Match '(?i)Copy-Item|Compress-Archive|Expand-Archive|ConvertTo-|Export-DistroShelf|wsl\.exe\s+--export'
    }

    It 'requires the accepted artifact and verifies its hash before promotion' {
        $path=Join-Path $PSScriptRoot '..\src\Profile\ProfileCommit.ps1'
        $source=Get-Content -LiteralPath $path -Raw
        $source | Should -Match '(?i)Test-Path'
        $source | Should -Match '(?i)Get-FileHash'
        $source | Should -Match '(?i)SHA256'
    }

    It 'preserves failed commit attempts in Troubleshoot rather than replacing them with a rebuilt copy' {
        $path=Join-Path $PSScriptRoot '..\src\Profile\ProfileCommit.ps1'
        $source=Get-Content -LiteralPath $path -Raw
        $source | Should -Match 'Move-DistroShelfTransactionToTroubleshoot'
    }
}
