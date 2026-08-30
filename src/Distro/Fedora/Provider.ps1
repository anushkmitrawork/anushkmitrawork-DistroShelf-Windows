# DistroShelf - Fedora provider
. (Join-Path $PSScriptRoot '..\PackageAcquisition.ps1')
function New-DistroShelfFedoraProvider {
    $pod=@(New-StageTest 'podman-command' 'command -v podman';New-StageTest 'podman-version' 'podman --version';New-StageTest 'podman-info' 'podman info --format json')
    $db=@(New-StageTest 'distrobox-command' 'command -v distrobox';New-StageTest 'distrobox-version' 'distrobox --version')
    $fp=@(New-StageTest 'flatpak-command' 'command -v flatpak';New-StageTest 'flatpak-version' 'flatpak --version')
    $root=New-DistroShelfRootfsStage 'dnf'
    $p=New-DistroShelfPackageStage 'podman' 'dnf' @('podman') $pod 'container-runtime'
    $d=New-DistroShelfPackageStage 'distrobox' 'dnf' @('distrobox') $db 'container-runtime';$d.Depends=@('rootfs','podman')
    $f=New-DistroShelfPackageStage 'flatpak' 'dnf' @('flatpak') $fp 'desktop-runtime'
    $names=@('kitty','alacritty','foot','konsole');$t=New-DistroShelfPackageStage 'terminals' 'dnf' $names (@($names|%{New-StageTest $_ "command -v $_"})) 'terminals';$t.Kind='terminal-set'
    $fl=New-StageContract 'flathub' @('rootfs','flatpak') 'dnf' @('mkdir -p /tmp/ds-flathub; curl -fsSL https://dl.flathub.org/repo/flathub.flatpakrepo -o /tmp/ds-flathub/flathub.flatpakrepo') @('flatpak remote-add --if-not-exists flathub /tmp/ds-flathub/flathub.flatpakrepo') @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') @() @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') 'wsl-path' '/tmp/ds-flathub' 'dependency' 'desktop-runtime' 'flatpak'
    $ds=New-StageContract 'distroshelf' @('rootfs','distrobox','flatpak','flathub') 'dnf' @('flatpak install -y flathub com.ranfdev.DistroShelf') @() @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') @('flatpak install -y --sideload-repo=TRACK_SIDELOAD flathub com.ranfdev.DistroShelf') @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') 'flatpak-sideload' 'com.ranfdev.DistroShelf' 'dependency' 'apps' 'flatpak'
    [pscustomobject][ordered]@{SchemaVersion=1;Distro='Fedora';Track='Fedora0';PackageManager='dnf';Rootfs=@{Name='Fedora';Architecture='amd64'};Stages=@($root,$p,$d,$f,$fl,$ds,$t);TrackFinalTests=@(New-StageTest 'podman-functional' 'podman run --rm quay.io/podman/hello true');ProfileFinalTests=@(New-StageTest 'profile-os' 'test -s /etc/os-release')}
}
