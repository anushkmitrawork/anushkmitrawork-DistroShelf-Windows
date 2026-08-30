# DistroShelf - Track artifact export helpers

function Export-DistroShelfWslPath {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$WslPath,[Parameter(Mandatory)][string]$Destination)
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $share="\\wsl$\$WslName$WslPath"
    if(-not(Test-Path -LiteralPath $share)){throw "Track artifact source does not exist in WSL: $WslPath"}
    $files=@(Get-ChildItem -LiteralPath $share -Recurse -File -ErrorAction Stop)
    if(!$files.Count){throw "Track artifact source is empty: $WslPath"}
    Copy-Item -LiteralPath (Join-Path $share '*') -Destination $Destination -Recurse -Force -ErrorAction Stop
    return $files.Count
}
function Export-DistroShelfAptCache {param([string]$WslName,[string]$Destination) return Export-DistroShelfWslPath -WslName $WslName -WslPath '/var/cache/apt/archives' -Destination (Join-Path $Destination 'packages')}
function Export-DistroShelfDnfCache {param([string]$WslName,[string]$Destination) $share="\\wsl$\$WslName\var\cache\dnf";if(!(Test-Path $share)){throw 'DNF package cache is unavailable.'};$rpms=@(Get-ChildItem $share -Recurse -File -Filter '*.rpm' -ErrorAction SilentlyContinue);if(!$rpms.Count){throw 'No RPM artifacts were produced by the DNF acquisition stage.'};$out=Join-Path $Destination 'packages';New-Item -ItemType Directory -Path $out -Force|Out-Null;foreach($rpm in $rpms){Copy-Item $rpm.FullName $out -Force};return $rpms.Count}
function Export-DistroShelfPacmanCache {param([string]$WslName,[string]$Destination) return Export-DistroShelfWslPath -WslName $WslName -WslPath '/var/cache/pacman/pkg' -Destination (Join-Path $Destination 'packages')}
function Export-DistroShelfZypperCache {param([string]$WslName,[string]$Destination) return Export-DistroShelfWslPath -WslName $WslName -WslPath '/var/cache/zypp/packages' -Destination (Join-Path $Destination 'packages')}
function Export-DistroShelfFlatpakSideload {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$AppId,[Parameter(Mandatory)][string]$Destination)
    $tmp="/tmp/distroShelf-sideload-$([guid]::NewGuid().ToString('N'))"
    $r=Invoke-DistroShelfCommand -WslName $WslName -Command "rm -rf '$tmp'; mkdir -p '$tmp'; flatpak create-usb '$tmp' '$AppId'" -CaptureOutput
    if($r.ExitCode-ne 0){throw "Flatpak sideload export failed for '$AppId'.`n$($r.Output)"}
    $share="\\wsl$\$WslName$tmp";if(!(Test-Path $share)){throw "Flatpak sideload export directory was not created: $tmp"}
    $files=@(Get-ChildItem $share -Recurse -File -ErrorAction SilentlyContinue);if(!$files.Count){throw 'Flatpak sideload export produced no files.'}
    $out=Join-Path $Destination 'sideload';New-Item -ItemType Directory -Path $out -Force|Out-Null;Copy-Item (Join-Path $share '*') $out -Recurse -Force
    Invoke-DistroShelfCommand -WslName $WslName -Command "rm -rf '$tmp'"|Out-Null
    return $files.Count
}
