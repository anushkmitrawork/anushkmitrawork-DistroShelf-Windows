# DistroShelf for Windows - distro-aware dependency engine
#
# This layer builds and executes a dependency plan INSIDE one selected WSL
# profile. Execution is intentionally opt-in; the planner can be used by the
# GUI without changing the machine.

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
            [pscustomobject]@{ Name='Flathub'; Command='configure official Flathub remote' }
            [pscustomobject]@{ Name='DistroShelf'; Command='install verified DistroShelf package' }
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

function Invoke-DistroShelfDependencyInstall {
    param([Parameter(Mandatory)][pscustomobject]$Profile)

    $plan = Get-DistroShelfDependencyPlan $Profile.Distro

    foreach ($step in $plan.Steps[0..3]) {
        Invoke-DistroShelfProfileCommand -WslName $Profile.WslName -Command $step.Command
    }

    # Flathub and DistroShelf installation are kept as separate provisioning
    # stages because their official package/app identifiers must be verified
    # before this function is allowed to make those changes.
    throw "Core dependencies are provisioned for '$($Profile.WslName)'. Flathub and DistroShelf provisioning remains gated pending verified official package identifiers."
}
