# DistroShelf for Windows - distro-aware dependency engine
#
# This layer builds and executes a dependency plan INSIDE one selected WSL
# profile. Every command is targeted at that profile's unique WSL name.

. (Join-Path $PSScriptRoot 'ProfileManager.ps1')

$script:DistroShelfDependencyPackages = @{
    'Ubuntu' = @{
        Update = 'apt-get update'
        Podman = 'apt-get install -y podman'
        Distrobox = 'apt-get install -y distrobox'
        Flatpak = 'apt-get install -y flatpak'
    }
    'Debian' = @{
        Update = 'apt-get update'
        Podman = 'apt-get install -y podman'
        Distrobox = 'apt-get install -y distrobox'
        Flatpak = 'apt-get install -y flatpak'
    }
    'Fedora' = @{
        Update = 'dnf makecache'
        Podman = 'dnf install -y podman'
        Distrobox = 'dnf install -y distrobox'
        Flatpak = 'dnf install -y flatpak'
    }
    'Arch Linux' = @{
        Update = 'pacman -Sy --noconfirm'
        Podman = 'pacman -S --noconfirm podman'
        Distrobox = 'pacman -S --noconfirm distrobox'
        Flatpak = 'pacman -S --noconfirm flatpak'
    }
    'openSUSE' = @{
        Update = 'zypper --non-interactive refresh'
        Podman = 'zypper --non-interactive install podman'
        Distrobox = 'zypper --non-interactive install distrobox'
        Flatpak = 'zypper --non-interactive install flatpak'
    }
}

$script:DistroShelfFlathubUrl = 'https://dl.flathub.org/repo/flathub.flatpakrepo'
$script:DistroShelfFlatpakId = 'com.ranfdev.DistroShelf'

function Get-DistroShelfDependencyPlan {
    param([Parameter(Mandatory)][string]$Distro)

    if (-not $script:DistroShelfDependencyPackages.ContainsKey($Distro)) {
        throw "No dependency plan exists for '$Distro'."
    }

    $p = $script:DistroShelfDependencyPackages[$Distro]
    return [pscustomobject][ordered]@{
        Distro = $Distro
        PackageManager = (Get-DistroShelfPackageManager $Distro)
        Steps = @(
            [pscustomobject]@{ Name='Package metadata'; Command=$p.Update }
            [pscustomobject]@{ Name='Podman'; Command=$p.Podman }
            [pscustomobject]@{ Name='Distrobox'; Command=$p.Distrobox }
            [pscustomobject]@{ Name='Flatpak'; Command=$p.Flatpak }
            [pscustomobject]@{ Name='Flathub'; Command="flatpak remote-add --if-not-exists flathub $script:DistroShelfFlathubUrl" }
            [pscustomobject]@{ Name='DistroShelf'; Command="flatpak install -y flathub $script:DistroShelfFlatpakId" }
        )
    }
}

function Invoke-DistroShelfProfileCommand {
    param(
        [Parameter(Mandatory)][string]$WslName,
        [Parameter(Mandatory)][string]$Command
    )

    & wsl.exe --distribution $WslName -- bash -lc $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed in '$WslName' with exit code $LASTEXITCODE: $Command"
    }
}

function Test-DistroShelfProfileDependency {
    param(
        [Parameter(Mandatory)][string]$WslName,
        [Parameter(Mandatory)][string]$Command
    )

    & wsl.exe --distribution $WslName -- bash -lc "command -v '$Command' >/dev/null 2>&1"
    return ($LASTEXITCODE -eq 0)
}

function Test-DistroShelfFlatpakApp {
    param([Parameter(Mandatory)][string]$WslName)
    & wsl.exe --distribution $WslName -- bash -lc "flatpak info '$script:DistroShelfFlatpakId' >/dev/null 2>&1"
    return ($LASTEXITCODE -eq 0)
}

function Test-DistroShelfFlathub {
    param([Parameter(Mandatory)][string]$WslName)
    & wsl.exe --distribution $WslName -- bash -lc "flatpak remotes --columns=name 2>/dev/null | grep -Fx flathub >/dev/null"
    return ($LASTEXITCODE -eq 0)
}

function Invoke-DistroShelfDependencyInstall {
    param([Parameter(Mandatory)][pscustomobject]$Profile)

    $plan = Get-DistroShelfDependencyPlan $Profile.Distro

    foreach ($step in $plan.Steps) {
        Invoke-DistroShelfProfileCommand -WslName $Profile.WslName -Command $step.Command
    }

    if (-not (Test-DistroShelfProfileDependency -WslName $Profile.WslName -Command 'podman')) {
        throw "Podman verification failed in '$($Profile.WslName)'."
    }
    if (-not (Test-DistroShelfProfileDependency -WslName $Profile.WslName -Command 'distrobox')) {
        throw "Distrobox verification failed in '$($Profile.WslName)'."
    }
    if (-not (Test-DistroShelfProfileDependency -WslName $Profile.WslName -Command 'flatpak')) {
        throw "Flatpak verification failed in '$($Profile.WslName)'."
    }
    if (-not (Test-DistroShelfFlathub -WslName $Profile.WslName)) {
        throw "Flathub verification failed in '$($Profile.WslName)'."
    }
    if (-not (Test-DistroShelfFlatpakApp -WslName $Profile.WslName)) {
        throw "DistroShelf Flatpak verification failed in '$($Profile.WslName)'."
    }

    return [pscustomobject][ordered]@{
        Profile = $Profile.WslName
        Podman = $true
        Distrobox = $true
        Flatpak = $true
        Flathub = $true
        DistroShelf = $true
    }
}
