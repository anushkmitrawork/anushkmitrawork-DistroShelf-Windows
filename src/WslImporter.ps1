# DistroShelf for Windows - verified WSL import engine
#
# Imports only a rootfs that has already passed SHA-256 verification.
# No existing WSL distribution is overwritten: profile names are unique and
# collisions are rejected before wsl.exe --import is invoked.

. (Join-Path $PSScriptRoot 'ProfileManager.ps1')
. (Join-Path $PSScriptRoot 'RootfsProvider.ps1')

function Invoke-DistroShelfWslImport {
    param(
        [Parameter(Mandatory)][pscustomobject]$Profile,
        [Parameter(Mandatory)][string]$RootfsPath,
        [Parameter(Mandatory)][string]$ExpectedSha256,
        [string]$StorageRoot = (Join-Path $env:LOCALAPPDATA 'DistroShelf\wsl')
    )

    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw 'wsl.exe was not found. WSL must be installed before creating a DistroShelf profile.'
    }

    if (-not (Test-Path -LiteralPath $RootfsPath -PathType Leaf)) {
        throw "Rootfs file not found: $RootfsPath"
    }

    $actual = (Get-FileHash -LiteralPath $RootfsPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $expected = ($ExpectedSha256 -replace '^0x','').ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "Refusing import: rootfs SHA-256 mismatch. Expected $expected, received $actual."
    }

    $existing = @((& wsl.exe --list --quiet 2>$null) | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
    if ($existing -contains $Profile.WslName) {
        throw "Refusing import: WSL distribution '$($Profile.WslName)' already exists."
    }

    $installLocation = Join-Path $StorageRoot $Profile.WslName
    if (Test-Path -LiteralPath $installLocation) {
        throw "Refusing import: installation directory already exists: $installLocation"
    }

    New-Item -ItemType Directory -Path $installLocation -Force | Out-Null

    & wsl.exe --import $Profile.WslName $installLocation $RootfsPath --version 2
    if ($LASTEXITCODE -ne 0) {
        throw "WSL import failed for '$($Profile.WslName)' with exit code $LASTEXITCODE."
    }

    $verify = @(& wsl.exe --list --verbose 2>$null) -join "`n"
    if ($verify -notmatch [regex]::Escape($Profile.WslName)) {
        throw "WSL import completed without a verifiable '$($Profile.WslName)' registration."
    }

    return [pscustomobject][ordered]@{
        ProfileId = $Profile.Id
        WslName = $Profile.WslName
        InstallLocation = $installLocation
        RootfsSha256 = $actual
        Imported = $true
    }
}
