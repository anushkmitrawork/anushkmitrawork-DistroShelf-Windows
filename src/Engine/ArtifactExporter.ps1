# DistroShelf - Track artifact export helpers

function Export-DistroShelfPackageDirectory {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$Destination)
    $share="\\wsl$\$WslName$SourcePath"
    if(!(Test-Path -LiteralPath $share -PathType Container)){throw "Track package source does not exist: $SourcePath"}
    $files=@(Get-ChildItem -LiteralPath $share -Recurse -File -ErrorAction Stop)
    if(!$files.Count){throw "Track package source is empty: $SourcePath"}
    New-Item -ItemType Directory -Path $Destination -Force|Out-Null
    Copy-Item -Path (Join-Path $share '*') -Destination $Destination -Recurse -Force -ErrorAction Stop
    return $files.Count
}

function Export-DistroShelfWslPath {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$WslPath,[Parameter(Mandatory)][string]$Destination)
    return Export-DistroShelfPackageDirectory -WslName $WslName -SourcePath $WslPath -Destination $Destination
}
function Export-DistroShelfAptCache {param([string]$WslName,[string]$Destination,[string]$StageId) if(!$StageId){throw 'APT export requires StageId.'};return Export-DistroShelfPackageDirectory -WslName $WslName -SourcePath "/tmp/ds-$StageId/packages" -Destination (Join-Path $Destination 'packages')}
function Export-DistroShelfDnfCache {param([string]$WslName,[string]$Destination,[string]$StageId) if(!$StageId){throw 'DNF export requires StageId.'};return Export-DistroShelfPackageDirectory -WslName $WslName -SourcePath "/tmp/ds-$StageId/packages" -Destination (Join-Path $Destination 'packages')}
function Export-DistroShelfPacmanCache {param([string]$WslName,[string]$Destination,[string]$StageId) if(!$StageId){throw 'Pacman export requires StageId.'};return Export-DistroShelfPackageDirectory -WslName $WslName -SourcePath "/tmp/ds-$StageId/packages" -Destination (Join-Path $Destination 'packages')}
function Export-DistroShelfZypperCache {param([string]$WslName,[string]$Destination,[string]$StageId) if(!$StageId){throw 'Zypper export requires StageId.'};return Export-DistroShelfPackageDirectory -WslName $WslName -SourcePath "/tmp/ds-$StageId/packages" -Destination (Join-Path $Destination 'packages')}

function Export-DistroShelfFlatpakSideload {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$AppId,[Parameter(Mandatory)][string]$Destination)
    $tmp="/tmp/distroShelf-sideload-$([guid]::NewGuid().ToString('N'))"
    $r=Invoke-DistroShelfCommand -WslName $WslName -Command "rm -rf '$tmp'; mkdir -p '$tmp'; flatpak create-usb '$tmp' '$AppId'" -CaptureOutput
    if($r.ExitCode -ne 0){throw "Flatpak sideload export failed for '$AppId'.`n$($r.Output)"}
    $share="\\wsl$\$WslName$tmp";if(!(Test-Path $share)){throw "Flatpak sideload export directory was not created: $tmp"}
    $files=@(Get-ChildItem $share -Recurse -File -ErrorAction SilentlyContinue);if(!$files.Count){throw 'Flatpak sideload export produced no files.'}
    $out=Join-Path $Destination 'sideload';New-Item -ItemType Directory -Path $out -Force|Out-Null;Copy-Item (Join-Path $share '*') $out -Recurse -Force
    Invoke-DistroShelfCommand -WslName $WslName -Command "rm -rf '$tmp'"|Out-Null
    return $files.Count
}
