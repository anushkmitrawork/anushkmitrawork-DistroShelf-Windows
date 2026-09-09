# DistroShelf - Debian provider
. (Join-Path $PSScriptRoot '..\PackageAcquisition.ps1')

function New-DistroShelfDebianProvider {
    $pod=@(
        (New-StageTest 'podman-command' 'command -v podman')
        (New-StageTest 'podman-version' 'podman --version')
        (New-StageTest 'podman-info' 'podman info --format json')
    )
    $db=@(
        (New-StageTest 'distrobox-command' 'command -v distrobox')
        (New-StageTest 'distrobox-version' 'distrobox --version')
        (New-StageTest 'distrobox-list' 'distrobox list')
    )
    $fp=@(
        (New-StageTest 'flatpak-command' 'command -v flatpak')
        (New-StageTest 'flatpak-version' 'flatpak --version')
        (New-StageTest 'flatpak-remotes' 'flatpak remotes --columns=name')
    )
    $root=New-DistroShelfRootfsStage 'apt'
    $root.Track.Tests=@(
        (New-StageTest 'os-release' 'test -s /etc/os-release')
        (New-StageTest 'architecture' 'test "$(uname -m)" = "x86_64"')
    )
    $root.Profile.Tests=@(
        (New-StageTest 'os-release' 'test -s /etc/os-release')
        (New-StageTest 'architecture' 'test "$(uname -m)" = "x86_64"')
    )

    # Bulletproof Bookworm sources list generation
    $aptFixCmds=@(
        'cat << "EOF" > /etc/apt/sources.list
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF',
        'rm -rf /etc/apt/sources.list.d/*',
        'apt-get clean',
        'apt-get update -o Acquire::Check-Valid-Until=false'
    )

    $aptFix=New-StageContract 'apt-fix' @('rootfs') 'apt' $aptFixCmds @() @(New-StageTest 'apt-workable' 'apt-get update') @() @() 'wsl-path' '/etc/apt' 'dependency' 'rootfs' 'apt'

    $p=New-DistroShelfPackageStage 'podman' 'apt' @('podman','crun') $pod 'container-runtime';$p.Depends=@('apt-fix')
    $d=New-DistroShelfPackageStage 'distrobox' 'apt' @('distrobox') $db 'container-runtime';$d.Depends=@('apt-fix','podman')
    $f=New-DistroShelfPackageStage 'flatpak' 'apt' @('flatpak') $fp 'desktop-runtime';$f.Depends=@('apt-fix')
    $terminalStages=@(
        (New-DistroShelfTerminalStage 'terminal-gnome-console' 'apt' 'GNOME Console' 'gnome-console' 'kgx'),
        (New-DistroShelfTerminalStage 'terminal-kitty' 'apt' 'Kitty' 'kitty' 'kitty'),
        (New-DistroShelfTerminalStage 'terminal-alacritty' 'apt' 'Alacritty' 'alacritty' 'alacritty'),
        (New-DistroShelfTerminalStage 'terminal-foot' 'apt' 'Foot' 'foot' 'foot'),
        (New-DistroShelfTerminalStage 'terminal-konsole' 'apt' 'Konsole' 'konsole' 'konsole')
    )
    foreach($t in $terminalStages){$t.Depends=@('apt-fix')}
    
    $fl=New-StageContract 'flathub' @('rootfs','flatpak') 'apt' @('mkdir -p /tmp/ds-flathub; curl -fsSL https://dl.flathub.org/repo/flathub.flatpakrepo -o /tmp/ds-flathub/flathub.flatpakrepo') @('flatpak remote-add --if-not-exists flathub /tmp/ds-flathub/flathub.flatpakrepo','flatpak remote-modify --collection-id=org.flathub.Stable flathub') @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') @('flatpak remote-modify --collection-id=org.flathub.Stable flathub') @(New-StageTest 'flathub-remote' 'flatpak remotes --columns=name | grep -Fx flathub') 'wsl-path' '/tmp/ds-flathub' 'dependency' 'desktop-runtime' 'flatpak'
    $ds=New-StageContract 'distroshelf' @('rootfs','distrobox','flatpak','flathub') 'apt' @('flatpak remote-modify --collection-id=org.flathub.Stable flathub','flatpak install -y flathub com.ranfdev.DistroShelf') @() @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') @('flatpak remote-modify --collection-id=org.flathub.Stable flathub','flatpak install -y --sideload-repo=TRACK_SIDELOAD flathub com.ranfdev.DistroShelf') @(New-StageTest 'distroshelf-install' 'flatpak info com.ranfdev.DistroShelf') 'flatpak-sideload' 'com.ranfdev.DistroShelf' 'dependency' 'apps' 'flatpak'
    [pscustomobject][ordered]@{SchemaVersion=4;Distro='Debian';Track='Debian0';PackageManager='apt';Rootfs=@{Name='Debian';Architecture='amd64'};Stages=@($root,$aptFix,$p,$d,$f,$fl,$ds)+$terminalStages;TrackFinalTests=@(
        (New-StageTest 'podman-functional' 'podman run --rm quay.io/podman/hello')
        (New-StageTest 'distrobox-final' 'distrobox list')
        (New-StageTest 'flatpak-final' 'flatpak info com.ranfdev.DistroShelf')
    );ProfileFinalTests=@(
        (New-StageTest 'profile-os' 'test -s /etc/os-release')
        (New-StageTest 'profile-architecture' 'test "$(uname -m)" = "x86_64"')
    )}
}
