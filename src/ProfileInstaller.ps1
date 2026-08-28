# DistroShelf for Windows - profile installation orchestration
#
# This is the safe first installation layer: it creates and records an
# independent DistroShelf profile without modifying WSL yet. The next layer
# will provision the WSL instance using the recorded profile name.

$script:ProfileInstallerRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:ProfileInstallerRoot 'ProfileManager.ps1')

function New-DistroShelfInstallationProfile {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')]
        [string]$Distro,

        [string]$Terminal = 'GNOME Console'
    )

    $profile = New-DistroShelfProfile -Distro $Distro

    # Keep terminal preference per profile so two profiles of the same distro
    # can be configured independently.
    $profiles = @(Get-DistroShelfProfiles)
    foreach ($item in $profiles) {
        if ($item.Id -eq $profile.Id) {
            $item | Add-Member -NotePropertyName Terminal -NotePropertyValue $Terminal -Force
            $item | Add-Member -NotePropertyName Status -NotePropertyValue 'Awaiting WSL provisioning' -Force
            break
        }
    }
    Save-DistroShelfProfiles $profiles

    return (Get-DistroShelfProfiles | Where-Object { $_.Id -eq $profile.Id } | Select-Object -First 1)
}

function Test-DistroShelfProfileNameAvailable {
    param([Parameter(Mandatory)][string]$WslName)
    return -not ((Get-DistroShelfProfiles).WslName -contains $WslName)
}

function Get-DistroShelfInstallPlan {
    param([Parameter(Mandatory)][string]$Distro)

    $definition = Get-DistroShelfProfileDefinition $Distro

    return [pscustomobject][ordered]@{
        Distro = $Distro
        PackageManager = $definition.PackageManager
        Steps = @(
            'Provision unique WSL profile'
            'Verify WSL 2'
            'Install Podman'
            'Install Distrobox'
            'Install Flatpak'
            'Configure Flathub'
            'Install DistroShelf'
            'Configure preferred DistroShelf terminal'
            'Verify complete environment'
        )
    }
}
