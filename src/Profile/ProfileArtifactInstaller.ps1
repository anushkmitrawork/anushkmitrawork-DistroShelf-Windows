# DistroShelf - local Track artifact installer

function Get-DistroShelfProfileStageRoot {
    param([Parameter(Mandatory)][string]$TrackRoot,[Parameter(Mandatory)][string]$StageId)
    $root=Join-Path $TrackRoot ($StageId -replace ':','-')
    if(-not(Test-Path -LiteralPath $root -PathType Container)){throw "Track stage '$StageId' is missing."}
    return $root
}

function Install-DistroShelfProfileStageFromTrack {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)]$Stage,[Parameter(Mandatory)][string]$TrackRoot)
    $root=Get-DistroShelfProfileStageRoot -TrackRoot $TrackRoot -StageId ([string]$Stage.Id)
    $export=[string]$Stage.Track.ExportType
    $manager=[string]$Stage.PackageManager
    switch($export){
        'apt-cache' {
            $source=Join-Path $root 'packages';if(-not(Test-Path $source)){throw "Track stage '$($Stage.Id)' has no package directory."}
            Invoke-DistroShelfCommand -WslName $WslName -Command "test -n \"`$(find /track-stage -type f -name '*.deb' -print -quit)\""|Out-Null
            return Invoke-DistroShelfCommand -WslName $WslName -Command "apt-get install -y --no-download /track-stage/*.deb" -CaptureOutput
        }
        'rpm-cache' {
            $source=Join-Path $root 'packages';if(-not(Test-Path $source)){throw "Track stage '$($Stage.Id)' has no package directory."}
            if($manager -eq 'dnf'){return Invoke-DistroShelfCommand -WslName $WslName -Command "dnf install -y /track-stage/*.rpm" -CaptureOutput}
            if($manager -eq 'zypper'){return Invoke-DistroShelfCommand -WslName $WslName -Command "zypper --non-interactive install --no-recommends /track-stage/*.rpm" -CaptureOutput}
            throw "No RPM local installer is defined for '$manager'."
        }
        'pacman-cache' { return Invoke-DistroShelfCommand -WslName $WslName -Command "pacman -U --noconfirm /track-stage/*.pkg.tar.*" -CaptureOutput }
        'wsl-path' {
            if([string]$Stage.Id -eq 'flathub'){return Invoke-DistroShelfCommand -WslName $WslName -Command 'flatpak remote-add --if-not-exists flathub /track-stage/flathub.flatpakrepo' -CaptureOutput}
            throw "No local installer is defined for wsl-path stage '$($Stage.Id)'."
        }
        'flatpak-sideload' { return Invoke-DistroShelfCommand -WslName $WslName -Command "flatpak install --assumeyes --sideload-repo=/track-stage/sideload flathub '$($Stage.Track.ExportValue)'" -CaptureOutput }
        'none' { return [pscustomobject]@{ExitCode=0;Output=''} }
        default { throw "Unsupported Track export type '$export' for Profile stage '$($Stage.Id)'." }
    }
}
