# DistroShelf - distro implementation contracts
# The engines own transaction semantics and scheduling.
# Each distro owns acquisition, installation and functional-test definitions.

function New-StageTest { param([string]$Name,[string]$Command,[int]$ExpectedExitCode=0,[string]$ExpectedOutput) [pscustomobject][ordered]@{Name=$Name;Command=$Command;ExpectedExitCode=$ExpectedExitCode;ExpectedOutput=$ExpectedOutput} }
function New-StageContract { param([string]$Id,[string[]]$Depends,[string]$PackageManager,[string[]]$TrackAcquire,[string[]]$TrackInstall,[object[]]$TrackTests,[string[]]$ProfileInstall,[object[]]$ProfileTests,[string]$Kind='dependency',[string]$ParallelGroup)
    [pscustomobject][ordered]@{Id=$Id;Depends=@($Depends);Kind=$Kind;ParallelGroup=$ParallelGroup;PackageManager=$PackageManager;Track=[pscustomobject][ordered]@{Acquire=@($TrackAcquire);Install=@($TrackInstall);Tests=@($TrackTests)};Profile=[pscustomobject][ordered]@{Install=@($ProfileInstall);Tests=@($ProfileTests)}}
}

function Get-DistroShelfAptStages { param([string]$Distro)
    $pod=[New-StageTest 'podman-command' 'command -v podman']+[New-StageTest 'podman-version' 'podman --version']+[New-StageTest 'podman-info' 'podman info --format json']
    $db=[New-StageTest 'distrobox-command' 'command -v distrobox']+[New-StageTest 'distrobox-version' 'distrobox --version']
    $fp=[New-StageTest 'flatpak-command' 'command -v flatpak']+[New-StageTest 'flatpak-version' 'flatpak --version']
    return @(
        (New-StageContract 'rootfs' @() 'apt' @() @() @(New-StageTest 'os-release' 'test -s /etc/os-release') @() @() 'rootfs' 'bootstrap'),
        (New-StageContract 'podman' @('rootfs') 'apt' @('apt-get update','apt-get --download-only -y install podman') @('apt-get -y install podman') $pod @('apt-get -y install --no-download podman') $pod 'dependency' 'container-runtime'),
        (New-StageContract 'distrobox' @('rootfs','podman') 'apt' @('apt-get --download-only -y install distrobox') @('apt-get -y install distrobox') $db @('apt-get -y install --no-download distrobox') $db 'dependency' 'container-runtime'),
        (New-StageContract 'flatpak' @('rootfs') 'apt' @('apt-get --download-only -y install flatpak') @('apt-get -y install flatpak') $fp @('apt-get -y install --no-download flatpak') $fp 'dependency' 'desktop-runtime'),
        (New-StageContract 'flathub' @('rootfs','flatpak') 'apt' @() @() @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') @('flatpak remotes --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo') @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') 'dependency' 'desktop-runtime'),
        (New-StageContract 'distroshelf' @('rootfs','distrobox','flatpak','flathub') 'apt' @() @() @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') @('flatpak install -y flathub com.ranfdev.DistroShelf') @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') 'dependency' 'apps'),
        (New-StageContract 'terminals' @('rootfs') 'apt' @() @() @(New-StageTest 'terminal-directory' 'test -d /usr/bin') @('apt-get -y install --no-install-recommends gnome-console gnome-terminal konsole kitty alacritty foot') @(New-StageTest 'terminal-artifacts' 'command -v gnome-console || command -v gnome-terminal || command -v konsole || command -v kitty || command -v alacritty || command -v foot') 'terminal-set' 'terminals')
    )
}
function Get-DistroShelfRpmStages { param([string]$Distro,[string]$Manager)
    return @(
        (New-StageContract 'rootfs' @() $Manager @() @() @(New-StageTest 'os-release' 'test -s /etc/os-release') @() @() 'rootfs' 'bootstrap'),
        (New-StageContract 'podman' @('rootfs') $Manager @("$Manager -y install --downloadonly podman") @("$Manager -y install podman") @([New-StageTest 'podman-command' 'command -v podman'],[New-StageTest 'podman-version' 'podman --version'],[New-StageTest 'podman-info' 'podman info --format json']) @("$Manager -y install --cacheonly podman") @([New-StageTest 'podman-command' 'command -v podman'],[New-StageTest 'podman-version' 'podman --version']) 'dependency' 'container-runtime'),
        (New-StageContract 'distrobox' @('rootfs','podman') $Manager @("$Manager -y install --downloadonly distrobox") @("$Manager -y install distrobox") @([New-StageTest 'distrobox-command' 'command -v distrobox'],[New-StageTest 'distrobox-version' 'distrobox --version']) @("$Manager -y install --cacheonly distrobox") @([New-StageTest 'distrobox-command' 'command -v distrobox']) 'dependency' 'container-runtime'),
        (New-StageContract 'flatpak' @('rootfs') $Manager @("$Manager -y install --downloadonly flatpak") @("$Manager -y install flatpak") @([New-StageTest 'flatpak-command' 'command -v flatpak'],[New-StageTest 'flatpak-version' 'flatpak --version']) @("$Manager -y install --cacheonly flatpak") @([New-StageTest 'flatpak-command' 'command -v flatpak']) 'dependency' 'desktop-runtime'),
        (New-StageContract 'flathub' @('rootfs','flatpak') $Manager @() @() @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') @('flatpak remotes --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo') @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') 'dependency' 'desktop-runtime'),
        (New-StageContract 'distroshelf' @('rootfs','distrobox','flatpak','flathub') $Manager @() @() @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') @('flatpak install -y flathub com.ranfdev.DistroShelf') @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') 'dependency' 'apps'),
        (New-StageContract 'terminals' @('rootfs') $Manager @() @() @(New-StageTest 'terminal-directory' 'test -d /usr/bin') @() @(New-StageTest 'terminal-artifacts' 'find /usr/bin -maxdepth 1 -type f | grep -E "(gnome-terminal|kitty|alacritty|konsole|foot)$"') 'terminal-set' 'terminals')
    )
}

$script:DistroShelfDistroDefinitions=@{
    'Ubuntu'=@{Id='Ubuntu';Track='Ubuntu0';PackageManager='apt';Rootfs=@{Name='Ubuntu';Architecture='amd64'};Stages=(Get-DistroShelfAptStages 'Ubuntu');TrackFinalTests=@(New-StageTest 'wsl-rootfs' 'test -s /etc/os-release',0);ProfileFinalTests=@(New-StageTest 'profile-os' 'test -s /etc/os-release',0)}
    'Debian'=@{Id='Debian';Track='Debian0';PackageManager='apt';Rootfs=@{Name='Debian';Architecture='amd64'};Stages=(Get-DistroShelfAptStages 'Debian');TrackFinalTests=@(New-StageTest 'wsl-rootfs' 'test -s /etc/os-release',0);ProfileFinalTests=@(New-StageTest 'profile-os' 'test -s /etc/os-release',0)}
    'Fedora'=@{Id='Fedora';Track='Fedora0';PackageManager='dnf';Rootfs=@{Name='Fedora';Architecture='amd64'};Stages=(Get-DistroShelfRpmStages 'Fedora' 'dnf');TrackFinalTests=@(New-StageTest 'wsl-rootfs' 'test -s /etc/os-release',0);ProfileFinalTests=@(New-StageTest 'profile-os' 'test -s /etc/os-release',0)}
    'Arch Linux'=@{Id='Arch Linux';Track='ArchLinux0';PackageManager='pacman';Rootfs=@{Name='Arch Linux';Architecture='amd64'};Stages=(Get-DistroShelfRpmStages 'Arch Linux' 'pacman');TrackFinalTests=@(New-StageTest 'wsl-rootfs' 'test -s /etc/os-release',0);ProfileFinalTests=@(New-StageTest 'profile-os' 'test -s /etc/os-release',0)}
    'openSUSE'=@{Id='openSUSE';Track='openSUSE0';PackageManager='zypper';Rootfs=@{Name='openSUSE';Architecture='amd64'};Stages=(Get-DistroShelfRpmStages 'openSUSE' 'zypper');TrackFinalTests=@(New-StageTest 'wsl-rootfs' 'test -s /etc/os-release',0);ProfileFinalTests=@(New-StageTest 'profile-os' 'test -s /etc/os-release',0)}
}
function Get-DistroShelfDistroDefinition {param([Parameter(Mandatory)][string]$Distro) if(!$script:DistroShelfDistroDefinitions.ContainsKey($Distro)){throw "Unsupported distro: $Distro"};$script:DistroShelfDistroDefinitions[$Distro]}
function Get-DistroShelfDistroStages {param([Parameter(Mandatory)][string]$Distro) return @(Get-DistroShelfDistroDefinition $Distro).Stages}
