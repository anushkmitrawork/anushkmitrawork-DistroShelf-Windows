# DistroShelf - Arch Linux provider
. (Join-Path $PSScriptRoot '..\PackageAcquisition.ps1')
function New-DistroShelfArchLinuxProvider {
    $pod=@(New-StageTest 'podman-command' 'command -v podman';New-StageTest 'podman-version' 'podman --version';New-StageTest 'podman-info' 'podman info --format json')
    $db=@(New-StageTest 'distrobox-command' 'command -v distrobox';New-StageTest 'distrobox-version' 'distrobox --version')
    $fp=@(New-StageTest 'flatpak-command' 'command -v flatpak';New-StageTest 'flatpak-version' 'flatpak --version')
    $root=New-DistroShelfRootfsStage 'pacman'
    $p=New-DistroShelfPackageStage 'podman' 'pacman' @('podman') $pod 'container-runtime'
    $d=New-DistroShelfPackageStage 'distrobox' 'pacman' @('distrobox') $db 'container-runtime';$d.Depends=@('rootfs','podman')
    $f=New-DistroShelfPackageStage 'flatpak' 'pacman' @('flatpak') $fp 'desktop-runtime'
    $terminalStages=@(
        (New-DistroShelfTerminalStage 'terminal-gnome-console' 'pacman' 'GNOME Console' 'gnome-console' 'kgx'),
        (New-DistroShelfTerminalStage 'terminal-kitty' 'pacman' 'Kitty' 'kitty' 'kitty'),
        (New-DistroShelfTerminalStage 'terminal-alacritty' 'pacman' 'Alacritty' 'alacritty' 'alacritty'),
        (New-DistroShelfTerminalStage 'terminal-foot' 'pacman' 'Foot' 'foot' 'foot'),
        (New-DistroShelfTerminalStage 'terminal-konsole' 'pacman' 'Konsole' 'konsole' 'konsole')
    )
    $fl=New-StageContract 'flathub' @('rootfs','flatpak') 'pacman' @('mkdir -p /tmp/ds-flathub; curl -fsSL https://dl.flathub.org/repo/flathub.flatpakrepo -o /tmp/ds-flathub/flathub.flatpakrepo') @('flatpak remote-add --if-not-exists flathub /tmp/ds-flathub/flathub.flatpakrepo') @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') @() @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') 'wsl-path' '/tmp/ds-flathub' 'dependency' 'desktop-runtime' 'flatpak'
    $ds=New-StageContract 'distroshelf' @('rootfs','distrobox','flatpak','flathub') 'pacman' @('flatpak install -y flathub com.ranfdev.DistroShelf') @() @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') @('flatpak install -y --sideload-repo=TRACK_SIDELOAD flathub com.ranfdev.DistroShelf') @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') 'flatpak-sideload' 'com.ranfdev.DistroShelf' 'dependency' 'apps' 'flatpak'
    [pscustomobject][ordered]@{SchemaVersion=2;Distro='Arch Linux';Track='ArchLinux0';PackageManager='pacman';Rootfs=@{Name='Arch Linux';Architecture='amd64'};Stages=@($root,$p,$d,$f,$fl,$ds)+$terminalStages;TrackFinalTests=@(New-StageTest 'podman-functional' 'podman run --rm quay.io/podman/hello true');ProfileFinalTests=@(New-StageTest 'profile-os' 'test -s /etc/os-release')}
}
