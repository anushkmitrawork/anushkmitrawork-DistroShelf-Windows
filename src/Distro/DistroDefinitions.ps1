# DistroShelf - distro implementation definitions
# Commands are intentionally data: the generic engines execute them.

$script:DistroShelfDefinitions = @{
    'Ubuntu' = @{
        PackageManager='apt'
        WslIdentifier='Ubuntu'
        Track=@{
            Rootfs=$true
            Stages=@(
                @{Id='podman';Requires=@('distro');ExclusiveGroup='apt';Acquire=@('apt-get download podman') ;ProfileInstall=@('apt-get install -y --no-download podman');Tests=@(@{Name='podman-version';Command='podman --version'},@{Name='podman-info';Command='podman info'})}
                @{Id='distrobox';Requires=@('podman');ExclusiveGroup='apt';Acquire=@('apt-get download distrobox');ProfileInstall=@('apt-get install -y --no-download distrobox');Tests=@(@{Name='distrobox-version';Command='distrobox --version'})}
                @{Id='flatpak';Requires=@('distro');ExclusiveGroup='apt';Acquire=@('apt-get download flatpak');ProfileInstall=@('apt-get install -y --no-download flatpak');Tests=@(@{Name='flatpak-version';Command='flatpak --version'})}
                @{Id='flathub';Requires=@('flatpak');Acquire=@('flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo');ProfileInstall=@('flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo');Tests=@(@{Name='flathub-remote';Command="flatpak remotes --columns=name | grep -Fx flathub"})}
                @{Id='distroshelf';Requires=@('distrobox','flathub');Acquire=@('flatpak install -y flathub com.ranfdev.DistroShelf');ProfileInstall=@('flatpak install -y flathub com.ranfdev.DistroShelf');Tests=@(@{Name='distroshelf-info';Command='flatpak info com.ranfdev.DistroShelf'})}
                @{Id='terminals';Requires=@('distro');Acquire=@();ProfileInstall=@();Tests=@(@{Name='terminal-stage';Command='true'})}
            )
        }
    }
    'Debian' = @{
        PackageManager='apt';WslIdentifier='Debian'
        Track=@{
            Rootfs=$true
            Stages=@(
                @{Id='podman';Requires=@('distro');ExclusiveGroup='apt';Acquire=@('apt-get download podman');ProfileInstall=@('apt-get install -y --no-download podman');Tests=@(@{Name='podman-version';Command='podman --version'},@{Name='podman-info';Command='podman info'})}
                @{Id='distrobox';Requires=@('podman');ExclusiveGroup='apt';Acquire=@('apt-get download distrobox');ProfileInstall=@('apt-get install -y --no-download distrobox');Tests=@(@{Name='distrobox-version';Command='distrobox --version'})}
                @{Id='flatpak';Requires=@('distro');ExclusiveGroup='apt';Acquire=@('apt-get download flatpak');ProfileInstall=@('apt-get install -y --no-download flatpak');Tests=@(@{Name='flatpak-version';Command='flatpak --version'})}
                @{Id='flathub';Requires=@('flatpak');Acquire=@('flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo');ProfileInstall=@('flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo');Tests=@(@{Name='flathub-remote';Command="flatpak remotes --columns=name | grep -Fx flathub"})}
                @{Id='distroshelf';Requires=@('distrobox','flathub');Acquire=@('flatpak install -y flathub com.ranfdev.DistroShelf');ProfileInstall=@('flatpak install -y flathub com.ranfdev.DistroShelf');Tests=@(@{Name='distroshelf-info';Command='flatpak info com.ranfdev.DistroShelf'})}
                @{Id='terminals';Requires=@('distro');Acquire=@();ProfileInstall=@();Tests=@(@{Name='terminal-stage';Command='true'})}
            )
        }
    }
    'Fedora' = @{
        PackageManager='dnf';WslIdentifier='Fedora'
        Track=@{
            Rootfs=$true
            Stages=@(
                @{Id='podman';Requires=@('distro');ExclusiveGroup='dnf';Acquire=@('dnf download --resolve podman');ProfileInstall=@('dnf -y --cacheonly install podman');Tests=@(@{Name='podman-version';Command='podman --version'},@{Name='podman-info';Command='podman info'})}
                @{Id='distrobox';Requires=@('podman');ExclusiveGroup='dnf';Acquire=@('dnf download --resolve distrobox');ProfileInstall=@('dnf -y --cacheonly install distrobox');Tests=@(@{Name='distrobox-version';Command='distrobox --version'})}
                @{Id='flatpak';Requires=@('distro');ExclusiveGroup='dnf';Acquire=@('dnf download --resolve flatpak');ProfileInstall=@('dnf -y --cacheonly install flatpak');Tests=@(@{Name='flatpak-version';Command='flatpak --version'})}
                @{Id='flathub';Requires=@('flatpak');Acquire=@('flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo');ProfileInstall=@('flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo');Tests=@(@{Name='flathub-remote';Command="flatpak remotes --columns=name | grep -Fx flathub"})}
                @{Id='distroshelf';Requires=@('distrobox','flathub');Acquire=@('flatpak install -y flathub com.ranfdev.DistroShelf');ProfileInstall=@('flatpak install -y flathub com.ranfdev.DistroShelf');Tests=@(@{Name='distroshelf-info';Command='flatpak info com.ranfdev.DistroShelf'})}
                @{Id='terminals';Requires=@('distro');Acquire=@();ProfileInstall=@();Tests=@(@{Name='terminal-stage';Command='true'})}
            )
        }
    }
    'Arch Linux' = @{
        PackageManager='pacman';WslIdentifier='Arch'
        Track=@{
            Rootfs=$true
            Stages=@(
                @{Id='podman';Requires=@('distro');ExclusiveGroup='pacman';Acquire=@('pacman -Sw --noconfirm --cachedir /track-cache podman');ProfileInstall=@('pacman -U --noconfirm --needed /track-cache/*.pkg.tar.*');Tests=@(@{Name='podman-version';Command='podman --version'},@{Name='podman-info';Command='podman info'})}
                @{Id='distrobox';Requires=@('podman');ExclusiveGroup='pacman';Acquire=@('pacman -Sw --noconfirm --cachedir /track-cache distrobox');ProfileInstall=@('pacman -U --noconfirm --needed /track-cache/*.pkg.tar.*');Tests=@(@{Name='distrobox-version';Command='distrobox --version'})}
                @{Id='flatpak';Requires=@('distro');ExclusiveGroup='pacman';Acquire=@('pacman -Sw --noconfirm --cachedir /track-cache flatpak');ProfileInstall=@('pacman -U --noconfirm --needed /track-cache/*.pkg.tar.*');Tests=@(@{Name='flatpak-version';Command='flatpak --version'})}
                @{Id='flathub';Requires=@('flatpak');Acquire=@('flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo');ProfileInstall=@('flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo');Tests=@(@{Name='flathub-remote';Command="flatpak remotes --columns=name | grep -Fx flathub"})}
                @{Id='distroshelf';Requires=@('distrobox','flathub');Acquire=@('pacman -Sw --noconfirm --cachedir /track-cache distroshelf');ProfileInstall=@('pacman -U --noconfirm --needed /track-cache/*.pkg.tar.*');Tests=@(@{Name='distroshelf-command';Command='command -v distroshelf'})}
                @{Id='terminals';Requires=@('distro');Acquire=@();ProfileInstall=@();Tests=@(@{Name='terminal-stage';Command='true'})}
            )
        }
    }
    'openSUSE' = @{
        PackageManager='zypper';WslIdentifier='openSUSE'
        Track=@{
            Rootfs=$true
            Stages=@(
                @{Id='podman';Requires=@('distro');ExclusiveGroup='zypper';Acquire=@('zypper --non-interactive download podman');ProfileInstall=@('zypper --non-interactive --no-refresh install /var/cache/zypp/packages/*.rpm');Tests=@(@{Name='podman-version';Command='podman --version'},@{Name='podman-info';Command='podman info'})}
                @{Id='distrobox';Requires=@('podman');ExclusiveGroup='zypper';Acquire=@('zypper --non-interactive download distrobox');ProfileInstall=@('zypper --non-interactive --no-refresh install /var/cache/zypp/packages/*.rpm');Tests=@(@{Name='distrobox-version';Command='distrobox --version'})}
                @{Id='flatpak';Requires=@('distro');ExclusiveGroup='zypper';Acquire=@('zypper --non-interactive download flatpak');ProfileInstall=@('zypper --non-interactive --no-refresh install /var/cache/zypp/packages/*.rpm');Tests=@(@{Name='flatpak-version';Command='flatpak --version'})}
                @{Id='flathub';Requires=@('flatpak');Acquire=@('flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo');ProfileInstall=@('flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo');Tests=@(@{Name='flathub-remote';Command="flatpak remotes --columns=name | grep -Fx flathub"})}
                @{Id='distroshelf';Requires=@('distrobox','flathub');Acquire=@('flatpak install -y flathub com.ranfdev.DistroShelf');ProfileInstall=@('flatpak install -y flathub com.ranfdev.DistroShelf');Tests=@(@{Name='distroshelf-info';Command='flatpak info com.ranfdev.DistroShelf'})}
                @{Id='terminals';Requires=@('distro');Acquire=@();ProfileInstall=@();Tests=@(@{Name='terminal-stage';Command='true'})}
            )
        }
    }
}

function Get-DistroShelfDistroDefinition { param([Parameter(Mandatory)][string]$Distro) if(!$script:DistroShelfDefinitions.ContainsKey($Distro)){throw "Unsupported distro: $Distro"};return $script:DistroShelfDefinitions[$Distro] }
function Get-DistroShelfDistroStages { param([Parameter(Mandatory)][string]$Distro) return @((Get-DistroShelfDistroDefinition $Distro).Track.Stages) }
