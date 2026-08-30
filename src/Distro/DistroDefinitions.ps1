# DistroShelf - distro implementation contracts
# Engines own scheduling and transaction semantics. Each distro supplies commands and tests.

. (Join-Path $PSScriptRoot 'PackageAcquisition.ps1')

function New-StageTest { param([string]$Name,[string]$Command,[int]$ExpectedExitCode=0,[string]$ExpectedOutput) [pscustomobject][ordered]@{Name=$Name;Command=$Command;ExpectedExitCode=$ExpectedExitCode;ExpectedOutput=$ExpectedOutput} }
function New-StageContract {
    param([string]$Id,[string[]]$Depends,[string]$PackageManager,[string[]]$TrackAcquire,[string[]]$TrackInstall,[object[]]$TrackTests,[string[]]$ProfileInstall,[object[]]$ProfileTests,[string]$ExportType,[string]$ExportValue,[string]$Kind='dependency',[string]$ParallelGroup,[string]$ResourceLock)
    [pscustomobject][ordered]@{Id=$Id;Depends=@($Depends);Kind=$Kind;ParallelGroup=$ParallelGroup;PackageManager=$PackageManager;ResourceLock=$ResourceLock;Track=[pscustomobject][ordered]@{Acquire=@($TrackAcquire);Install=@($TrackInstall);Tests=@($TrackTests);ExportType=$ExportType;ExportValue=$ExportValue};Profile=[pscustomobject][ordered]@{Install=@($ProfileInstall);Tests=@($ProfileTests)}}
}
function New-DistroShelfRootfsStage {param([string]$Manager)[pscustomobject][ordered]@{Id='rootfs';Depends=@();Kind='rootfs';ParallelGroup='bootstrap';PackageManager=$Manager;ResourceLock='wsl-rootfs';Track=[pscustomobject][ordered]@{Acquire=@();Install=@();Tests=@(New-StageTest 'os-release' 'test -s /etc/os-release');ExportType='none';ExportValue=''};Profile=[pscustomobject][ordered]@{Install=@();Tests=@(New-StageTest 'os-release' 'test -s /etc/os-release')}}

function Get-DistroShelfAptStages {
    param([string[]]$Terminals)
    $pod=@(New-StageTest 'podman-command' 'command -v podman';New-StageTest 'podman-version' 'podman --version';New-StageTest 'podman-info' 'podman info --format json')
    $db=@(New-StageTest 'distrobox-command' 'command -v distrobox';New-StageTest 'distrobox-version' 'distrobox --version')
    $fp=@(New-StageTest 'flatpak-command' 'command -v flatpak';New-StageTest 'flatpak-version' 'flatpak --version')
    $p=New-DistroShelfPackageStage 'podman' 'apt' @('podman') $pod 'container-runtime';$d=New-DistroShelfPackageStage 'distrobox' 'apt' @('distrobox') $db 'container-runtime';$f=New-DistroShelfPackageStage 'flatpak' 'apt' @('flatpak') $fp 'desktop-runtime'
    $t=New-DistroShelfPackageStage 'terminals' 'apt' $Terminals (@($Terminals|ForEach-Object{New-StageTest $_ "command -v $_"}) ) 'terminals';$t.Depends=@('rootfs');$t.Kind='terminal-set'
    $fl=New-StageContract 'flathub' @('rootfs','flatpak') 'apt' @('mkdir -p /tmp/ds-flathub; curl -fsSL https://dl.flathub.org/repo/flathub.flatpakrepo -o /tmp/ds-flathub/flathub.flatpakrepo') @('flatpak remote-add --if-not-exists flathub /tmp/ds-flathub/flathub.flatpakrepo') @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') @() @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') 'wsl-path' '/tmp/ds-flathub' 'dependency' 'desktop-runtime' 'flatpak'
    $ds=New-StageContract 'distroshelf' @('rootfs','distrobox','flatpak','flathub') 'apt' @('flatpak install -y flathub com.ranfdev.DistroShelf') @() @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') @('flatpak install -y --sideload-repo=TRACK_SIDELOAD flathub com.ranfdev.DistroShelf') @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') 'flatpak-sideload' 'com.ranfdev.DistroShelf' 'dependency' 'apps' 'flatpak'
    $root=New-DistroShelfRootfsStage 'apt';$p.Depends=@('rootfs');$d.Depends=@('rootfs','podman');$f.Depends=@('rootfs');$t.Depends=@('rootfs')
    @($root,$p,$d,$f,$fl,$ds,$t)
}

function Get-DistroShelfPacmanStages {
    param([string[]]$Terminals)
    $pod=@(New-StageTest 'podman-command' 'command -v podman';New-StageTest 'podman-version' 'podman --version';New-StageTest 'podman-info' 'podman info --format json')
    $db=@(New-StageTest 'distrobox-command' 'command -v distrobox';New-StageTest 'distrobox-version' 'distrobox --version')
    $fp=@(New-StageTest 'flatpak-command' 'command -v flatpak';New-StageTest 'flatpak-version' 'flatpak --version')
    $p=New-DistroShelfPackageStage 'podman' 'pacman' @('podman') $pod 'container-runtime';$d=New-DistroShelfPackageStage 'distrobox' 'pacman' @('distrobox') $db 'container-runtime';$f=New-DistroShelfPackageStage 'flatpak' 'pacman' @('flatpak') $fp 'desktop-runtime';$t=New-DistroShelfPackageStage 'terminals' 'pacman' $Terminals (@($Terminals|ForEach-Object{New-StageTest $_ "command -v $_"}) ) 'terminals';$t.Kind='terminal-set';
    $fl=New-StageContract 'flathub' @('rootfs','flatpak') 'pacman' @('mkdir -p /tmp/ds-flathub; curl -fsSL https://dl.flathub.org/repo/flathub.flatpakrepo -o /tmp/ds-flathub/flathub.flatpakrepo') @('flatpak remote-add --if-not-exists flathub /tmp/ds-flathub/flathub.flatpakrepo') @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') @() @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') 'wsl-path' '/tmp/ds-flathub' 'dependency' 'desktop-runtime' 'flatpak'
    $ds=New-StageContract 'distroshelf' @('rootfs','distrobox','flatpak','flathub') 'pacman' @('flatpak install -y flathub com.ranfdev.DistroShelf') @() @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') @('flatpak install -y --sideload-repo=TRACK_SIDELOAD flathub com.ranfdev.DistroShelf') @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') 'flatpak-sideload' 'com.ranfdev.DistroShelf' 'dependency' 'apps' 'flatpak'
    $root=New-DistroShelfRootfsStage 'pacman';$p.Depends=@('rootfs');$d.Depends=@('rootfs','podman');$f.Depends=@('rootfs');$t.Depends=@('rootfs')
    @($root,$p,$d,$f,$fl,$ds,$t)
}

function Get-DistroShelfRpmStages { param([ValidateSet('dnf','zypper')][string]$Manager,[string[]]$Terminals)
    $pod=@(New-StageTest 'podman-command' 'command -v podman';New-StageTest 'podman-version' 'podman --version';New-StageTest 'podman-info' 'podman info --format json');$db=@(New-StageTest 'distrobox-command' 'command -v distrobox';New-StageTest 'distrobox-version' 'distrobox --version');$fp=@(New-StageTest 'flatpak-command' 'command -v flatpak';New-StageTest 'flatpak-version' 'flatpak --version')
    $p=New-DistroShelfPackageStage 'podman' $Manager @('podman') $pod 'container-runtime';$d=New-DistroShelfPackageStage 'distrobox' $Manager @('distrobox') $db 'container-runtime';$f=New-DistroShelfPackageStage 'flatpak' $Manager @('flatpak') $fp 'desktop-runtime';$t=New-DistroShelfPackageStage 'terminals' $Manager $Terminals (@($Terminals|ForEach-Object{New-StageTest $_ "command -v $_"}) ) 'terminals';$t.Kind='terminal-set'
    $fl=New-StageContract 'flathub' @('rootfs','flatpak') $Manager @('mkdir -p /tmp/ds-flathub; curl -fsSL https://dl.flathub.org/repo/flathub.flatpakrepo -o /tmp/ds-flathub/flathub.flatpakrepo') @('flatpak remote-add --if-not-exists flathub /tmp/ds-flathub/flathub.flatpakrepo') @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') @() @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') 'wsl-path' '/tmp/ds-flathub' 'dependency' 'desktop-runtime' 'flatpak'
    $ds=New-StageContract 'distroshelf' @('rootfs','distrobox','flatpak','flathub') $Manager @('flatpak install -y flathub com.ranfdev.DistroShelf') @() @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') @('flatpak install -y --sideload-repo=TRACK_SIDELOAD flathub com.ranfdev.DistroShelf') @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') 'flatpak-sideload' 'com.ranfdev.DistroShelf' 'dependency' 'apps' 'flatpak'
    $root=New-DistroShelfRootfsStage $Manager;foreach($s in @($p,$d,$f,$t)){$s.Depends=@('rootfs')};$d.Depends=@('rootfs','podman');$t.Depends=@('rootfs')
    @($root,$p,$d,$f,$fl,$ds,$t)
}

$script:DistroShelfDistroDefinitions=@{
    'Ubuntu'=@{Id='Ubuntu';Track='Ubuntu0';PackageManager='apt';Rootfs=@{Name='Ubuntu';Architecture='amd64'};Stages=(Get-DistroShelfAptStages @('gnome-terminal','kitty','alacritty','foot','konsole'));TrackFinalTests=@(New-StageTest 'podman-functional' 'podman run --rm quay.io/podman/hello true');ProfileFinalTests=@(New-StageTest 'profile-os' 'test -s /etc/os-release')}
    'Debian'=@{Id='Debian';Track='Debian0';PackageManager='apt';Rootfs=@{Name='Debian';Architecture='amd64'};Stages=(Get-DistroShelfAptStages @('gnome-terminal','kitty','alacritty','foot','konsole'));TrackFinalTests=@(New-StageTest 'podman-functional' 'podman run --rm quay.io/podman/hello true');ProfileFinalTests=@(New-StageTest 'profile-os' 'test -s /etc/os-release')}
    'Fedora'=@{Id='Fedora';Track='Fedora0';PackageManager='dnf';Rootfs=@{Name='Fedora';Architecture='amd64'};Stages=(Get-DistroShelfRpmStages 'dnf' @('gnome-terminal','kitty','alacritty','foot','konsole'));TrackFinalTests=@(New-StageTest 'podman-functional' 'podman run --rm quay.io/podman/hello true');ProfileFinalTests=@(New-StageTest 'profile-os' 'test -s /etc/os-release')}
    'Arch Linux'=@{Id='Arch Linux';Track='ArchLinux0';PackageManager='pacman';Rootfs=@{Name='Arch Linux';Architecture='amd64'};Stages=(Get-DistroShelfPacmanStages @('gnome-terminal','kitty','alacritty','foot','konsole'));TrackFinalTests=@(New-StageTest 'podman-functional' 'podman run --rm quay.io/podman/hello true');ProfileFinalTests=@(New-StageTest 'profile-os' 'test -s /etc/os-release')}
    'openSUSE'=@{Id='openSUSE';Track='openSUSE0';PackageManager='zypper';Rootfs=@{Name='openSUSE';Architecture='amd64'};Stages=(Get-DistroShelfRpmStages 'zypper' @('gnome-terminal','kitty','alacritty','foot','konsole'));TrackFinalTests=@(New-StageTest 'podman-functional' 'podman run --rm quay.io/podman/hello true');ProfileFinalTests=@(New-StageTest 'profile-os' 'test -s /etc/os-release')}
}

function Get-DistroShelfDistroDefinition { param([Parameter(Mandatory)][string]$Distro) if(!$script:DistroShelfDistroDefinitions.ContainsKey($Distro)){throw "Unsupported distro: $Distro"};$script:DistroShelfDistroDefinitions[$Distro] }
