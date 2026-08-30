# DistroShelf - package acquisition strategy helpers
# Track commands acquire reusable artifacts. Profile commands consume only the bridged Track artifacts.

function New-DistroShelfPackageStage {
    param([string]$Id,[string]$Manager,[string[]]$Packages,[string[]]$Tests,[string]$ParallelGroup='packages')
    $names=($Packages -join ' ')
    switch($Manager){
        'apt' {
            $acquire="mkdir -p /tmp/ds-$Id/packages; apt-get update; apt-get --download-only -y -o Dir::Cache::archives=/tmp/ds-$Id/packages install $names"
            $install="apt-get -y --no-download -o Dir::Cache::archives=/tmp/ds-$Id/packages install $names"
            $profile="apt-get -y --no-download install /track-stage/$Id/*.deb /track-stage/$Id/packages/*.deb"
            $export='apt-cache'
        }
        'dnf' {
            $acquire="mkdir -p /tmp/ds-$Id/packages; dnf -y --refresh --downloadonly --downloaddir=/tmp/ds-$Id/packages install $names"
            $install="dnf -y --disablerepo='*' install /tmp/ds-$Id/packages/*.rpm"
            $profile="dnf -y --disablerepo='*' install /track-stage/$Id/packages/*.rpm"
            $export='rpm-cache'
        }
        'pacman' {
            $acquire="mkdir -p /tmp/ds-$Id/packages; pacman -Sy --noconfirm; pacman -Sw --noconfirm --cachedir /tmp/ds-$Id/packages $names"
            $install="pacman -U --noconfirm /tmp/ds-$Id/packages/*.pkg.tar.*"
            $profile="pacman -U --noconfirm /track-stage/$Id/packages/*.pkg.tar.*"
            $export='pacman-cache'
        }
        'zypper' {
            $acquire="mkdir -p /tmp/ds-$Id/packages; zypper --non-interactive --pkg-cache-dir /tmp/ds-$Id/packages install --download-only $names"
            $install="zypper --non-interactive install /tmp/ds-$Id/packages/*.rpm"
            $profile="zypper --non-interactive install /track-stage/$Id/packages/*.rpm"
            $export='rpm-cache'
        }
        default { throw "Unsupported package manager: $Manager" }
    }
    [pscustomobject][ordered]@{
        Id=$Id; Depends=@('rootfs'); Kind='dependency'; ParallelGroup=$ParallelGroup; PackageManager=$Manager
        Track=[pscustomobject][ordered]@{Acquire=@($acquire);Install=@($install);Tests=@($Tests);ExportType=$export;ExportValue=''}
        Profile=[pscustomobject][ordered]@{Install=@($profile);Tests=@($Tests)}
    }
}
