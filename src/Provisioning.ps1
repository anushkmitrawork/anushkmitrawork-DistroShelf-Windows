# DistroShelf for Windows - WSL profile provisioning
# Safe first provisioning implementation: creates an isolated WSL instance
# from a supported Microsoft Store/WSL distribution without installing Linux
# dependencies yet.

. (Join-Path $PSScriptRoot 'ProfileManager.ps1')

$script:WslDistroIdentifiers = @{
    'Ubuntu' = 'Ubuntu'
    'Debian' = 'Debian'
    'Fedora' = 'Fedora'
    'Arch Linux' = 'Arch'
    'openSUSE' = 'openSUSE'
}

function Test-WslAvailable {
    try {
        $null = Get-Command wsl.exe -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Get-WslInstances {
    if (-not (Test-WslAvailable)) { return @() }
    try {
        return @((& wsl.exe --list --quiet 2>$null) | ForEach-Object {
            ($_ -replace "`0", '').Trim()
        } | Where-Object { $_ })
    } catch { return @() }
}

function Test-WslInstanceExists {
    param([Parameter(Mandatory)][string]$Name)
    return ((Get-WslInstances) -contains $Name)
}

function Get-DistroShelfWslIdentifier {
    param([Parameter(Mandatory)][string]$Distro)
    if (-not $script:WslDistroIdentifiers.ContainsKey($Distro)) {
        throw "Unsupported WSL distro: $Distro"
    }
    return $script:WslDistroIdentifiers[$Distro]
}

function Invoke-WslDistroInstall {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$ProfileWslName
    )

    if (-not (Test-WslAvailable)) {
        throw 'WSL is not available. Install/enable WSL 2 before provisioning a profile.'
    }

    if (Test-WslInstanceExists $ProfileWslName) {
        throw "A WSL instance named '$ProfileWslName' already exists."
    }

    $source = Get-DistroShelfWslIdentifier $Distro

    # Import a fresh root filesystem into a unique WSL instance. The actual
    # rootfs acquisition is intentionally a separate step so the installer can
    # verify the exact source before modifying the machine.
    throw "Provisioning is staged: WSL source '$source' is selected for '$ProfileWslName', but rootfs acquisition has not been enabled yet."
}

function Set-DistroShelfProfileStatus {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Status
    )

    $profiles = @(Get-DistroShelfProfiles)
    $found = $false
    foreach ($profile in $profiles) {
        if ($profile.Id -eq $Id) {
            $profile.Status = $Status
            $found = $true
            break
        }
    }
    if (-not $found) { throw "Profile not found: $Id" }
    Save-DistroShelfProfiles $profiles
}

function Get-DistroShelfProvisioningPlan {
    param([Parameter(Mandatory)][string]$Distro)

    $definition = Get-DistroShelfProfileDefinition $Distro
    return [pscustomobject][ordered]@{
        Distro = $Distro
        WslBase = $definition.WslBaseName
        PackageManager = $definition.PackageManager
        Isolation = 'Independent WSL instance per profile'
        NextStep = 'Acquire and verify a distro root filesystem, then import it with wsl.exe --import'
    }
}
