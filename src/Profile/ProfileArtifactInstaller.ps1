# DistroShelf - local Track artifact installer
# The Profile installer consumes only verified Track material.

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
    $stageId=([string]$Stage.Id -replace ':','-')
    $remotePattern='(^|[;&|`n\r]|\s)(curl|wget|Invoke-WebRequest|git\s+clone|apt(-get)?\s+.*https?://|dnf\s+.*https?://|zypper\s+.*https?://|pacman\s+.*https?://|flatpak\s+install\s+.*https?://)'
    switch($export){
        'apt-cache' {
            $source=Join-Path $root 'packages';if(-not(Test-Path $source -PathType Container)){throw "Track stage '$($Stage.Id)' has no package directory."}
            $count=@(Get-ChildItem -LiteralPath $source -Recurse -File -Filter '*.deb').Count;if($count -eq 0){throw "Track stage '$($Stage.Id)' contains no .deb artifacts."}
            $mounted="/track-stage/$stageId/packages/*.deb"
            Invoke-DistroShelfCommand -WslName $WslName -Command "test -n \"`$(find /track-stage/$stageId/packages -type f -name '*.deb' -print -quit)\""|Out-Null
            return Invoke-DistroShelfCommand -WslName $WslName -Command "apt-get install -y --no-download $mounted" -CaptureOutput
        }
        'rpm-cache' {
            $source=Join-Path $root 'packages';if(-not(Test-Path $source -PathType Container)){throw "Track stage '$($Stage.Id)' has no package directory."}
            $count=@(Get-ChildItem -LiteralPath $source -Recurse -File -Filter '*.rpm').Count;if($count -eq 0){throw "Track stage '$($Stage.Id)' contains no .rpm artifacts."}
            $mounted="/track-stage/$stageId/packages/*.rpm"
            if($manager -eq 'dnf'){return Invoke-DistroShelfCommand -WslName $WslName -Command "dnf install -y --disablerepo='*' $mounted" -CaptureOutput}
            if($manager -eq 'zypper'){return Invoke-DistroShelfCommand -WslName $WslName -Command "zypper --non-interactive install --no-recommends $mounted" -CaptureOutput}
            throw "No RPM local installer is defined for '$manager'."
        }
        'pacman-cache' {
            $source=Join-Path $root 'packages';if(-not(Test-Path $source -PathType Container)){throw "Track stage '$($Stage.Id)' has no package directory."}
            $count=@(Get-ChildItem -LiteralPath $source -Recurse -File -Include '*.pkg.tar.zst','*.pkg.tar.xz','*.pkg.tar.gz','*.pkg.tar').Count;if($count -eq 0){throw "Track stage '$($Stage.Id)' contains no Arch package artifacts."}
            $mounted="/track-stage/$stageId/packages/*.pkg.tar.*"
            return Invoke-DistroShelfCommand -WslName $WslName -Command "pacman -U --noconfirm $mounted" -CaptureOutput
        }
        'wsl-path' {
            if([string]$Stage.Id -eq 'flathub'){
                $repo=Join-Path $root 'flathub.flatpakrepo';if(-not(Test-Path $repo -PathType Leaf)){$repo=Get-ChildItem $root -Recurse -File -Filter '*.flatpakrepo'|Select-Object -First 1|ForEach-Object FullName};if(-not$repo){throw "Track Flathub stage contains no .flatpakrepo artifact."}
                $repoPath="/track-stage/$stageId/$(Split-Path -Leaf $repo)"
                return Invoke-DistroShelfCommand -WslName $WslName -Command "flatpak remote-add --if-not-exists flathub '$repoPath'" -CaptureOutput
            }
            throw "No local installer is defined for wsl-path stage '$($Stage.Id)'."
        }
        'flatpak-sideload' {
            $sideload=Join-Path $root 'sideload';if(-not(Test-Path $sideload -PathType Container)){throw "Track stage '$($Stage.Id)' has no sideload repository."}
            return Invoke-DistroShelfCommand -WslName $WslName -Command "flatpak install --assumeyes --sideload-repo=/track-stage/$stageId/sideload '$($Stage.Track.ExportValue)'" -CaptureOutput
        }
        default { throw "Unsupported Track export type '$export' for Profile stage '$($Stage.Id)'." }
    }
}

function Test-DistroShelfProfileInstallCommands {
    param([Parameter(Mandatory)][object]$Stage)
    foreach($cmd in @($Stage.Profile.Install)){
        if([string]$cmd -match $remotePattern){throw "Profile stage '$($Stage.Id)' contains a network acquisition command; Profile installation must consume Track artifacts only."}
    }
    $true
}
