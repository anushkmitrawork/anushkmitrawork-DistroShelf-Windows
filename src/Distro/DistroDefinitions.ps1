# DistroShelf - distro implementation contracts
# This file defines WHAT each stage needs. Engines decide WHEN it runs.

$script:DistroShelfDistroDefinitions = @{
    'Ubuntu' = @{
        Id='Ubuntu'; Track='Ubuntu0'; PackageManager='apt';
        Rootfs=@{ Name='Ubuntu'; Architecture='amd64' }
        Stages=@(
            @{ Id='rootfs'; Depends=@(); Kind='rootfs'; ParallelGroup='bootstrap' }
            @{ Id='podman'; Depends=@('rootfs'); Kind='dependency'; ParallelGroup='container-runtime' }
            @{ Id='distrobox'; Depends=@('rootfs','podman'); Kind='dependency'; ParallelGroup='container-runtime' }
            @{ Id='flatpak'; Depends=@('rootfs'); Kind='dependency'; ParallelGroup='desktop-runtime' }
            @{ Id='flathub'; Depends=@('rootfs','flatpak'); Kind='dependency'; ParallelGroup='desktop-runtime' }
            @{ Id='distroshelf'; Depends=@('rootfs','distrobox','flatpak','flathub'); Kind='dependency'; ParallelGroup='apps' }
            @{ Id='terminals'; Depends=@('rootfs'); Kind='terminal-set'; ParallelGroup='terminals' }
        )
    }
    'Debian' = @{
        Id='Debian'; Track='Debian0'; PackageManager='apt'; Rootfs=@{ Name='Debian'; Architecture='amd64' }
        Stages=@(
            @{ Id='rootfs'; Depends=@(); Kind='rootfs'; ParallelGroup='bootstrap' }
            @{ Id='podman'; Depends=@('rootfs'); Kind='dependency'; ParallelGroup='container-runtime' }
            @{ Id='distrobox'; Depends=@('rootfs','podman'); Kind='dependency'; ParallelGroup='container-runtime' }
            @{ Id='flatpak'; Depends=@('rootfs'); Kind='dependency'; ParallelGroup='desktop-runtime' }
            @{ Id='flathub'; Depends=@('rootfs','flatpak'); Kind='dependency'; ParallelGroup='desktop-runtime' }
            @{ Id='distroshelf'; Depends=@('rootfs','distrobox','flatpak','flathub'); Kind='dependency'; ParallelGroup='apps' }
            @{ Id='terminals'; Depends=@('rootfs'); Kind='terminal-set'; ParallelGroup='terminals' }
        )
    }
    'Fedora' = @{
        Id='Fedora'; Track='Fedora0'; PackageManager='dnf'; Rootfs=@{ Name='Fedora'; Architecture='amd64' }
        Stages=@(
            @{ Id='rootfs'; Depends=@(); Kind='rootfs'; ParallelGroup='bootstrap' }
            @{ Id='podman'; Depends=@('rootfs'); Kind='dependency'; ParallelGroup='container-runtime' }
            @{ Id='distrobox'; Depends=@('rootfs','podman'); Kind='dependency'; ParallelGroup='container-runtime' }
            @{ Id='flatpak'; Depends=@('rootfs'); Kind='dependency'; ParallelGroup='desktop-runtime' }
            @{ Id='flathub'; Depends=@('rootfs','flatpak'); Kind='dependency'; ParallelGroup='desktop-runtime' }
            @{ Id='distroshelf'; Depends=@('rootfs','distrobox','flatpak','flathub'); Kind='dependency'; ParallelGroup='apps' }
            @{ Id='terminals'; Depends=@('rootfs'); Kind='terminal-set'; ParallelGroup='terminals' }
        )
    }
    'Arch Linux' = @{
        Id='Arch Linux'; Track='ArchLinux0'; PackageManager='pacman'; Rootfs=@{ Name='Arch Linux'; Architecture='amd64' }
        Stages=@(
            @{ Id='rootfs'; Depends=@(); Kind='rootfs'; ParallelGroup='bootstrap' }
            @{ Id='podman'; Depends=@('rootfs'); Kind='dependency'; ParallelGroup='container-runtime' }
            @{ Id='distrobox'; Depends=@('rootfs','podman'); Kind='dependency'; ParallelGroup='container-runtime' }
            @{ Id='flatpak'; Depends=@('rootfs'); Kind='dependency'; ParallelGroup='desktop-runtime' }
            @{ Id='flathub'; Depends=@('rootfs','flatpak'); Kind='dependency'; ParallelGroup='desktop-runtime' }
            @{ Id='distroshelf'; Depends=@('rootfs','distrobox','flatpak','flathub'); Kind='dependency'; ParallelGroup='apps' }
            @{ Id='terminals'; Depends=@('rootfs'); Kind='terminal-set'; ParallelGroup='terminals' }
        )
    }
    'openSUSE' = @{
        Id='openSUSE'; Track='openSUSE0'; PackageManager='zypper'; Rootfs=@{ Name='openSUSE'; Architecture='amd64' }
        Stages=@(
            @{ Id='rootfs'; Depends=@(); Kind='rootfs'; ParallelGroup='bootstrap' }
            @{ Id='podman'; Depends=@('rootfs'); Kind='dependency'; ParallelGroup='container-runtime' }
            @{ Id='distrobox'; Depends=@('rootfs','podman'); Kind='dependency'; ParallelGroup='container-runtime' }
            @{ Id='flatpak'; Depends=@('rootfs'); Kind='dependency'; ParallelGroup='desktop-runtime' }
            @{ Id='flathub'; Depends=@('rootfs','flatpak'); Kind='dependency'; ParallelGroup='desktop-runtime' }
            @{ Id='distroshelf'; Depends=@('rootfs','distrobox','flatpak','flathub'); Kind='dependency'; ParallelGroup='apps' }
            @{ Id='terminals'; Depends=@('rootfs'); Kind='terminal-set'; ParallelGroup='terminals' }
        )
    }
}

function Get-DistroShelfDistroDefinition { param([Parameter(Mandatory)][string]$Distro) if(!$script:DistroShelfDistroDefinitions.ContainsKey($Distro)){throw "Unsupported distro: $Distro"}; return $script:DistroShelfDistroDefinitions[$Distro] }
