# DistroShelf - openSUSE provider
. (Join-Path $PSScriptRoot '..\PackageAcquisition.ps1')
function New-DistroShelfOpenSUSEProvider {
    $pod=@(New-StageTest 'podman-command' 'command -v podman';New-StageTest 'podman-version' 'podman --version';New-StageTest 'podman-info' 'podman info --format json')
    $db=@(New-StageTest 'distrobox-command' 'command -v distrobox';New-StageTest 'distrobox-version' 'distrobox --version';New-StageTest 'distrobox-list' 'distrobox list')
    $fp=@(New-StageTest 'flatpak-command' 'command -v flatpak';New-StageTest 'flatpak-version' 'flatpak --version';New-StageTest 'flatpak-remotes' 'flatpak remotes --columns=name')
    $root=New-DistroShelfRootfsStage 'zypper'
    $root.Track.Tests=@(
        (New-StageTest 'os-release' 'test -s /etc/os-release')
        (New-StageTest 'architecture' 'test "$(uname -m)" = "x86_64"')
    )
    $root.Profile.Tests=@(
        (New-StageTest 'os-release' 'test -s /etc/os-release')
        (New-StageTest 'architecture' 'test "$(uname -m)" = "x86_64"')
    )
    $p=New-DistroShelfPackageStage 'podman' 'zypper' @('podman') $pod 'container-runtime'
    $d=New-DistroShelfPackageStage 'distrobox' 'zypper' @('distrobox') $db 'container-runtime';$d.Depends=@('rootfs','podman')
    $f=New-DistroShelfPackageStage 'flatpak' 'zypper' @('flatpak') $fp 'desktop-runtime'
    $terminalStages=@(
        (New-DistroShelfTerminalStage 'terminal-gnome-console' 'zypper' 'GNOME Console' 'gnome-console' 'kgx'),
        (New-DistroShelfTerminalStage 'terminal-kitty' 'zypper' 'Kitty' 'kitty' 'kitty'),
        (New-DistroShelfTerminalStage 'terminal-alacritty' 'zypper' 'Alacritty' 'alacritty' 'alacritty'),
        (New-DistroShelfTerminalStage 'terminal-foot' 'zypper' 'Foot' 'foot' 'foot'),
        (New-DistroShelfTerminalStage 'terminal-konsole' 'zypper' 'Konsole' 'konsole' 'konsole')
    )
    $fl=New-StageContract 'flathub' @('rootfs','flatpak') 'zypper' @('mkdir -p /tmp/ds-flathub; curl -fsSL https://dl.flathub.org/repo/flathub.flatpakrepo -o /tmp/ds-flathub/flathub.flatpakrepo') @('flatpak remote-add --if-not-exists flathub /tmp/ds-flathub/flathub.flatpakrepo') @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') @() @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') 'wsl-path' '/tmp/ds-flathub' 'dependency' 'desktop-runtime' 'flatpak'
    $ds=New-StageContract 'distroshelf' @('rootfs','distrobox','flatpak','flathub') 'zypper' @('flatpak install -y flathub com.ranfdev.DistroShelf') @() @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') @('flatpak install -y --sideload-repo=TRACK_SIDELOAD flathub com.ranfdev.DistroShelf') @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') 'flatpak-sideload' 'com.ranfdev.DistroShelf' 'dependency' 'apps' 'flatpak'
    [pscustomobject][ordered]@{SchemaVersion=4;Distro='openSUSE';Track='openSUSE0';PackageManager='zypper';Rootfs=@{Name='openSUSE';Architecture='amd64'};Stages=@($root,$p,$d,$f,$fl,$ds)+$terminalStages;TrackFinalTests=@(
        (New-StageTest 'podman-functional' 'podman run --rm quay.io/podman/hello')
        (New-StageTest 'distrobox-final' 'distrobox list')
        (New-StageTest 'flatpak-final' 'flatpak info com.ranfdev.DistroShelf')
    );ProfileFinalTests=@(
        (New-StageTest 'profile-os' 'test -s /etc/os-release')
        (New-StageTest 'profile-architecture' 'test "$(uname -m)" = "x86_64"')
    )}
}
