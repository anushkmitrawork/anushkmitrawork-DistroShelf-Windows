# DistroShelf - package acquisition strategy helpers
# Track commands acquire reusable artifacts. Profile commands consume only the bridged Track artifacts.

function New-DistroShelfPackageStage {
    param([string]$Id,[string]$Manager,[string[]]$Packages,[string[]]$Tests,[string]$ParallelGroup='packages')
    $names=($Packages -join ' ')
    switch($Manager){
        'apt' {
            $acquire="mkdir -p /tmp/ds-$Id/packages; apt-get update; apt-get --download-only -y -o Dir::Cache::archives=/tmp/ds-$Id/packages install $names"
            $install="apt-get -y --no-download -o Dir::Cache::archives=/tmp/ds-$Id/packages install $names"
            $profile="apt-get -y --no-download install /track-stage/$Id/packages/*.deb"
            $export='apt-cache'
        }
        'dnf' {
            # Prefer DNF5's dedicated download command because --downloadonly uses the
            # package-manager cache and may remove packages after a later transaction.
            # Fall back to the DNF4 download plugin when dnf5 is unavailable; the stage
            # exporter persists the resulting RPMs into the transaction before proceeding.
            $acquire="mkdir -p /tmp/ds-$Id/packages; if command -v dnf5 >/dev/null 2>&1; then dnf5 download --resolve --alldeps --destdir=/tmp/ds-$Id/packages $names; elif dnf download --resolve --destdir=/tmp/ds-$Id/packages $names; then true; else echo 'DistroShelf requires dnf5 download or the dnf download plugin for durable Track acquisition.' >&2; exit 127; fi"
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

function New-DistroShelfTerminalStage {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Manager,
        [Parameter(Mandatory)][string]$TerminalName,
        [Parameter(Mandatory)][string]$PackageName,
        [Parameter(Mandatory)][string]$Executable
    )
    $stage=New-DistroShelfPackageStage -Id $Id -Manager $Manager -Packages @($PackageName) -Tests @(
        (New-StageTest "$TerminalName-command" "command -v $Executable"),
        (New-StageTest "$TerminalName-version" "$Executable --version")
    ) -ParallelGroup 'terminals'
    # PSCustomObject is intentionally used by the stage contracts; add terminal-specific
    # fields as members instead of assignment so PowerShell 7 does not reject new properties.
    $stage | Add-Member -NotePropertyName Kind -NotePropertyValue 'terminal' -Force
    $stage | Add-Member -NotePropertyName TerminalName -NotePropertyValue $TerminalName -Force
    $stage | Add-Member -NotePropertyName TerminalPackage -NotePropertyValue $PackageName -Force
    $stage | Add-Member -NotePropertyName TerminalExecutable -NotePropertyValue $Executable -Force
    return $stage
}
