# DistroShelf - Track artifact export helpers

function Export-DistroShelfWslPath {
    param(
        [Parameter(Mandatory)][string]$WslName,
        [Parameter(Mandatory)][string]$WslPath,
        [Parameter(Mandatory)][string]$Destination
    )
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $share = "\\wsl$\$WslName$WslPath"
    if (-not (Test-Path -LiteralPath $share)) { throw "Track artifact source does not exist in WSL: $WslPath" }
    $files = @(Get-ChildItem -LiteralPath $share -Recurse -File -ErrorAction Stop)
    if (-not $files.Count) { throw "Track artifact source is empty: $WslPath" }
    Copy-Item -LiteralPath (Join-Path $share '*') -Destination $Destination -Recurse -Force -ErrorAction Stop
    return $files.Count
}

function Export-DistroShelfAptCache {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$Destination)
    return Export-DistroShelfWslPath -WslName $WslName -WslPath '/var/cache/apt/archives' -Destination (Join-Path $Destination 'packages')
}

function Export-DistroShelfDnfCache {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$Destination)
    $result = Invoke-DistroShelfCommand -WslName $WslName -Command "find /var/cache/dnf -type f -name '*.rpm' -print0 | tar --null -cf - --files-from=-" -CaptureOutput
    if ($result.ExitCode -ne 0) { throw "Unable to inspect the DNF package cache: $($result.Output)" }
    $share = "\\wsl$\$WslName\var\cache\dnf"
    if (-not (Test-Path $share)) { throw 'DNF cache is unavailable.' }
    $rpms = @(Get-ChildItem $share -Recurse -File -Filter '*.rpm' -ErrorAction SilentlyContinue)
    if (-not $rpms.Count) { throw 'No RPM artifacts were produced by the DNF acquisition stage.' }
    $out=Join-Path $Destination 'packages';New-Item -ItemType Directory -Path $out -Force|Out-Null
    foreach($rpm in $rpms){Copy-Item $rpm.FullName $out -Force}
    return $rpms.Count
}

function Export-DistroShelfPacmanCache {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$Destination)
    return Export-DistroShelfWslPath -WslName $WslName -WslPath '/var/cache/pacman/pkg' -Destination (Join-Path $Destination 'packages')
}

function Export-DistroShelfZypperCache {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$Destination)
    $share = "\\wsl$\$WslName\var\cache\zypp\packages"
    if (-not (Test-Path $share)) { throw 'Zypper package cache is unavailable.' }
    $pkgs=@(Get-ChildItem $share -Recurse -File -ErrorAction SilentlyContinue)
    if(-not $pkgs.Count){throw 'No Zypper package artifacts were produced.'}
    $out=Join-Path $Destination 'packages';New-Item -ItemType Directory -Path $out -Force|Out-Null
    foreach($p in $pkgs){Copy-Item $p.FullName $out -Force}
    return $pkgs.Count
}
