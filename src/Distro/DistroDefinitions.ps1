# DistroShelf - declarative distro implementations
# The engines execute this data. They do not contain distro-specific branches.

$script:DistroShelfSupportedTerminals = @('Alacritty','COSMIC Terminal','Deepin Terminal','Foot','GNOME Console','GNOME Terminal','Ghostty','Kitty','Konsole','Ptyxis','QTerminal')

function New-DistroShelfStage {
    param([string]$Id,[string[]]$Requires=@(),[string]$ExclusiveGroup,[string[]]$TrackAcquire=@(),[object[]]$TrackTests=@(),[string[]]$ProfileInstall=@(),[object[]]$ProfileTests=@(),[string[]]$Artifacts=@())
    [pscustomobject][ordered]@{Id=$Id;Requires=@($Requires);ExclusiveGroup=$ExclusiveGroup;TrackAcquire=@($TrackAcquire);TrackTests=@($TrackTests);ProfileInstall=@($ProfileInstall);ProfileTests=@($ProfileTests);Artifacts=@($Artifacts)}
}
function New-DistroShelfCommandTest { param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$Command) [pscustomobject][ordered]@{Name=$Name;Command=$Command} }

$script:DistroShelfDefinitions = @{}

$aptCommon = @(
    (New-DistroShelfStage 'podman' @('distro') 'apt' @('apt-get update','apt-get --download-only --reinstall install podman') @(New-DistroShelfCommandTest 'podman-version' 'podman --version') @(New-DistroShelfCommandTest 'podman-info' 'podman info') @('apt-get install -y --no-download podman') @(New-DistroShelfCommandTest 'podman-version' 'podman --version'),(New-DistroShelfCommandTest 'podman-info' 'podman info')),
    (New-DistroShelfStage 'distrobox' @('podman') 'apt' @('apt-get --download-only --reinstall install distrobox') @(New-DistroShelfCommandTest 'distrobox-version' 'distrobox --version') @('apt-get install -y --no-download distrobox') @(New-DistroShelfCommandTest 'distrobox-version' 'distrobox --version')),
    (New-DistroShelfStage 'flatpak' @('distro') 'apt' @('apt-get --download-only --reinstall install flatpak') @(New-DistroShelfCommandTest 'flatpak-version' 'flatpak --version') @('apt-get install -y --no-download flatpak') @(New-DistroShelfCommandTest 'flatpak-version' 'flatpak --version')),
    (New-DistroShelfStage 'flathub' @('flatpak') $null @() @(New-DistroShelfCommandTest 'flathub-remote' "flatpak remotes --columns=name | grep -Fx flathub") @('flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo') @(New-DistroShelfCommandTest 'flathub-remote' "flatpak remotes --columns=name | grep -Fx flathub")),
    (New-DistroShelfStage 'distroshelf' @('distrobox','flathub') $null @('flatpak install -y --noninteractive flathub com.ranfdev.DistroShelf') @(New-DistroShelfCommandTest 'distroshelf-info' 'flatpak info com.ranfdev.DistroShelf') @('flatpak install -y --noninteractive flathub com.ranfdev.DistroShelf') @(New-DistroShelfCommandTest 'distroshelf-info' 'flatpak info com.ranfdev.DistroShelf'))
)
$terminalStages = foreach($terminal in $script:DistroShelfSupportedTerminals) { New-DistroShelfStage ("terminal:" + $terminal) @('distro') $null @() @(New-DistroShelfCommandTest ("terminal-resource:"+$terminal) 'true') @() @() }
$script:DistroShelfDefinitions['Ubuntu'] = @{PackageManager='apt';WslIdentifier='Ubuntu';TrackStages=@($aptCommon + $terminalStages)}
$script:DistroShelfDefinitions['Debian'] = @{PackageManager='apt';WslIdentifier='Debian';TrackStages=@($aptCommon + $terminalStages)}

function New-DistroShelfDnfStages {
    @(
        (New-DistroShelfStage 'podman' @('distro') 'dnf' @('dnf makecache','dnf download --resolve podman') @(New-DistroShelfCommandTest 'podman-version' 'podman --version') @(New-DistroShelfCommandTest 'podman-info' 'podman info') @('dnf -y --cacheonly install podman') @(New-DistroShelfCommandTest 'podman-version' 'podman --version'),(New-DistroShelfCommandTest 'podman-info' 'podman info')),
        (New-DistroShelfStage 'distrobox' @('podman') 'dnf' @('dnf download --resolve distrobox') @(New-DistroShelfCommandTest 'distrobox-version' 'distrobox --version') @('dnf -y --cacheonly install distrobox') @(New-DistroShelfCommandTest 'distrobox-version' 'distrobox --version')),
        (New-DistroShelfStage 'flatpak' @('distro') 'dnf' @('dnf download --resolve flatpak') @(New-DistroShelfCommandTest 'flatpak-version' 'flatpak --version') @('dnf -y --cacheonly install flatpak') @(New-DistroShelfCommandTest 'flatpak-version' 'flatpak --version')),
        (New-DistroShelfStage 'flathub' @('flatpak') $null @() @(New-DistroShelfCommandTest 'flathub-remote' "flatpak remotes --columns=name | grep -Fx flathub") @('flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo') @(New-DistroShelfCommandTest 'flathub-remote' "flatpak remotes --columns=name | grep -Fx flathub")),
        (New-DistroShelfStage 'distroshelf' @('distrobox','flathub') $null @('flatpak install -y --noninteractive flathub com.ranfdev.DistroShelf') @(New-DistroShelfCommandTest 'distroshelf-info' 'flatpak info com.ranfdev.DistroShelf') @('flatpak install -y --noninteractive flathub com.ranfdev.DistroShelf') @(New-DistroShelfCommandTest 'distroshelf-info' 'flatpak info com.ranfdev.DistroShelf'))
    ) + $terminalStages
}
$script:DistroShelfDefinitions['Fedora'] = @{PackageManager='dnf';WslIdentifier='Fedora';TrackStages=New-DistroShelfDnfStages}

function New-DistroShelfPacmanStages {
    @(
        (New-DistroShelfStage 'podman' @('distro') 'pacman' @('pacman -Sy --noconfirm','pacman -Sw --noconfirm --cachedir /track-cache podman') @(New-DistroShelfCommandTest 'podman-version' 'podman --version') @(New-DistroShelfCommandTest 'podman-info' 'podman info') @('pacman -U --noconfirm --needed /track-cache/*.pkg.tar.*') @(New-DistroShelfCommandTest 'podman-version' 'podman --version'),(New-DistroShelfCommandTest 'podman-info' 'podman info')),
        (New-DistroShelfStage 'distrobox' @('podman') 'pacman' @('pacman -Sw --noconfirm --cachedir /track-cache distrobox') @(New-DistroShelfCommandTest 'distrobox-version' 'distrobox --version') @('pacman -U --noconfirm --needed /track-cache/*.pkg.tar.*') @(New-DistroShelfCommandTest 'distrobox-version' 'distrobox --version')),
        (New-DistroShelfStage 'flatpak' @('distro') 'pacman' @('pacman -Sw --noconfirm --cachedir /track-cache flatpak') @(New-DistroShelfCommandTest 'flatpak-version' 'flatpak --version') @('pacman -U --noconfirm --needed /track-cache/*.pkg.tar.*') @(New-DistroShelfCommandTest 'flatpak-version' 'flatpak --version')),
        (New-DistroShelfStage 'flathub' @('flatpak') $null @() @(New-DistroShelfCommandTest 'flathub-remote' "flatpak remotes --columns=name | grep -Fx flathub") @('flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo') @(New-DistroShelfCommandTest 'flathub-remote' "flatpak remotes --columns=name | grep -Fx flathub")),
        (New-DistroShelfStage 'distroshelf' @('distrobox','flathub') 'pacman' @('pacman -Sw --noconfirm --cachedir /track-cache distroshelf') @(New-DistroShelfCommandTest 'distroshelf-package' 'pacman -Q distroshelf') @('pacman -U --noconfirm --needed /track-cache/*.pkg.tar.*') @(New-DistroShelfCommandTest 'distroshelf-package' 'pacman -Q distroshelf'))
    ) + $terminalStages
}
$script:DistroShelfDefinitions['Arch Linux'] = @{PackageManager='pacman';WslIdentifier='Arch';TrackStages=New-DistroShelfPacmanStages}

function New-DistroShelfZypperStages {
    @(
        (New-DistroShelfStage 'podman' @('distro') 'zypper' @('zypper --non-interactive refresh','zypper --non-interactive download podman') @(New-DistroShelfCommandTest 'podman-version' 'podman --version') @(New-DistroShelfCommandTest 'podman-info' 'podman info') @('zypper --non-interactive --no-refresh install /var/cache/zypp/packages/*.rpm') @(New-DistroShelfCommandTest 'podman-version' 'podman --version'),(New-DistroShelfCommandTest 'podman-info' 'podman info')),
        (New-DistroShelfStage 'distrobox' @('podman') 'zypper' @('zypper --non-interactive download distrobox') @(New-DistroShelfCommandTest 'distrobox-version' 'distrobox --version') @('zypper --non-interactive --no-refresh install /var/cache/zypp/packages/*.rpm') @(New-DistroShelfCommandTest 'distrobox-version' 'distrobox --version')),
        (New-DistroShelfStage 'flatpak' @('distro') 'zypper' @('zypper --non-interactive download flatpak') @(New-DistroShelfCommandTest 'flatpak-version' 'flatpak --version') @('zypper --non-interactive --no-refresh install /var/cache/zypp/packages/*.rpm') @(New-DistroShelfCommandTest 'flatpak-version' 'flatpak --version')),
        (New-DistroShelfStage 'flathub' @('flatpak') $null @() @(New-DistroShelfCommandTest 'flathub-remote' "flatpak remotes --columns=name | grep -Fx flathub") @('flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo') @(New-DistroShelfCommandTest 'flathub-remote' "flatpak remotes --columns=name | grep -Fx flathub")),
        (New-DistroShelfStage 'distroshelf' @('distrobox','flathub') $null @('flatpak install -y --noninteractive flathub com.ranfdev.DistroShelf') @(New-DistroShelfCommandTest 'distroshelf-info' 'flatpak info com.ranfdev.DistroShelf') @('flatpak install -y --noninteractive flathub com.ranfdev.DistroShelf') @(New-DistroShelfCommandTest 'distroshelf-info' 'flatpak info com.ranfdev.DistroShelf'))
    ) + $terminalStages
}
$script:DistroShelfDefinitions['openSUSE'] = @{PackageManager='zypper';WslIdentifier='openSUSE';TrackStages=New-DistroShelfZypperStages}

function Get-DistroShelfDistroDefinition { param([Parameter(Mandatory)][string]$Distro) if(!$script:DistroShelfDefinitions.ContainsKey($Distro)){throw "Unsupported distro: $Distro"};return $script:DistroShelfDefinitions[$Distro] }
function Get-DistroShelfDistroStages { param([Parameter(Mandatory)][string]$Distro) return @((Get-DistroShelfDistroDefinition $Distro).TrackStages) }
