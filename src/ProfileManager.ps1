# DistroShelf for Windows - independent profile manager
#
# A profile represents one independent WSL environment. Multiple profiles can
# use the same Linux distribution without sharing their Linux userspace.
#
# Example:
#   DistroShelf-Ubuntu1
#   DistroShelf-Ubuntu2
#   DistroShelf-Fedora1
#
# This module intentionally does NOT install WSL distributions yet. It provides
# the naming, metadata and persistence layer that the installer will use.

$script:DistroShelfProfileRoot = Join-Path $env:LOCALAPPDATA 'DistroShelf'
$script:DistroShelfProfileFile = Join-Path $script:DistroShelfProfileRoot 'profiles.json'

$script:DistroShelfProfileDefinitions = @{
    'Ubuntu' = @{ WslBaseName='Ubuntu'; PackageManager='apt' }
    'Debian' = @{ WslBaseName='Debian'; PackageManager='apt' }
    'Fedora' = @{ WslBaseName='Fedora'; PackageManager='dnf' }
    'Arch Linux' = @{ WslBaseName='Arch'; PackageManager='pacman' }
    'openSUSE' = @{ WslBaseName='openSUSE'; PackageManager='zypper' }
}

function Initialize-DistroShelfProfileStore {
    if (-not (Test-Path -LiteralPath $script:DistroShelfProfileRoot)) {
        New-Item -ItemType Directory -Path $script:DistroShelfProfileRoot -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $script:DistroShelfProfileFile)) {
        '[]' | Set-Content -LiteralPath $script:DistroShelfProfileFile -Encoding UTF8
    }
}

function Get-DistroShelfProfiles {
    Initialize-DistroShelfProfileStore

    try {
        $raw = Get-Content -LiteralPath $script:DistroShelfProfileFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $profiles = $raw | ConvertFrom-Json
        if ($null -eq $profiles) { return @() }
        return @($profiles)
    } catch {
        throw "DistroShelf profile store is invalid: $($_.Exception.Message)"
    }
}

function Save-DistroShelfProfiles {
    param([object[]]$Profiles)

    Initialize-DistroShelfProfileStore
    $json = @($Profiles) | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $script:DistroShelfProfileFile -Value $json -Encoding UTF8
}

function Get-DistroShelfProfileDefinition {
    param([Parameter(Mandatory)][string]$Distro)

    if (-not $script:DistroShelfProfileDefinitions.ContainsKey($Distro)) {
        throw "Unsupported WSL distro: $Distro"
    }

    return $script:DistroShelfProfileDefinitions[$Distro]
}

function Get-NextDistroShelfProfileNumber {
    param([Parameter(Mandatory)][string]$Distro)

    $definition = Get-DistroShelfProfileDefinition $Distro
    $prefix = "DistroShelf-$($definition.WslBaseName)"
    $highest = 0

    foreach ($profile in Get-DistroShelfProfiles) {
        if ($profile.WslName -match "^$([regex]::Escape($prefix))([0-9]+)$") {
            $number = [int]$Matches[1]
            if ($number -gt $highest) { $highest = $number }
        }
    }

    return ($highest + 1)
}

function New-DistroShelfProfile {
    param([Parameter(Mandatory)][ValidateSet('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')][string]$Distro)

    $definition = Get-DistroShelfProfileDefinition $Distro
    $number = Get-NextDistroShelfProfileNumber $Distro
    $wslName = "DistroShelf-$($definition.WslBaseName)$number"
    $profileName = "$($definition.WslBaseName)$number"

    $profiles = @(Get-DistroShelfProfiles)

    if ($profiles.WslName -contains $wslName) {
        throw "Profile name collision detected: $wslName"
    }

    $profile = [ordered]@{
        Id = [guid]::NewGuid().ToString()
        Name = $profileName
        Distro = $Distro
        WslName = $wslName
        PackageManager = $definition.PackageManager
        Status = 'Pending'
        CreatedAt = [DateTime]::UtcNow.ToString('o')
        Dependencies = [ordered]@{
            Wsl2 = $false
            Podman = $false
            Distrobox = $false
            Flatpak = $false
            Flathub = $false
            DistroShelf = $false
        }
    }

    $profiles += [pscustomobject]$profile
    Save-DistroShelfProfiles $profiles
    return [pscustomobject]$profile
}

function Remove-DistroShelfProfileRecord {
    param([Parameter(Mandatory)][string]$Id)

    $profiles = @(Get-DistroShelfProfiles)
    $remaining = @($profiles | Where-Object { $_.Id -ne $Id })

    if ($remaining.Count -eq $profiles.Count) {
        throw "Profile not found: $Id"
    }

    Save-DistroShelfProfiles $remaining
}

function Get-DistroShelfPackageManager {
    param([Parameter(Mandatory)][string]$Distro)
    return (Get-DistroShelfProfileDefinition $Distro).PackageManager
}
