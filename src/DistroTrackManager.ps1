# DistroShelf for Windows - per-distro track manager
# Track 0 is the reusable artifact/cache source for one distro.
# A transaction can override the final track root so incomplete attempts never
# modify the committed Track 0.

$script:DistroShelfTrackRoot = Join-Path $env:LOCALAPPDATA 'DistroShelf\tracks'

function Get-DistroShelfEffectiveTrackRoot {
    if ($env:DISTROSHELF_TRACK_ROOT_OVERRIDE) { return [string]$env:DISTROSHELF_TRACK_ROOT_OVERRIDE }
    return $script:DistroShelfTrackRoot
}

function Get-DistroShelfTrackDefinition { param([Parameter(Mandatory)][string]$Distro)
    $safeName=switch($Distro){'Ubuntu'{'Ubuntu'}'Debian'{'Debian'}'Fedora'{'Fedora'}'Arch Linux'{'ArchLinux'}'openSUSE'{'openSUSE'}default{throw "Unsupported DistroShelf track: $Distro"}}
    [pscustomobject][ordered]@{Distro=$Distro;Name="${safeName}0";Root=(Join-Path (Get-DistroShelfEffectiveTrackRoot) "${safeName}0")}
}
function Initialize-DistroShelfTrack { param([Parameter(Mandatory)][string]$Distro)
    $track=Get-DistroShelfTrackDefinition $Distro
    foreach($d in @($track.Root,(Join-Path $track.Root 'Distro'),(Join-Path $track.Root 'Podman'),(Join-Path $track.Root 'Distrobox'),(Join-Path $track.Root 'Flatpak'),(Join-Path $track.Root 'DistroShelf'),(Join-Path $track.Root 'metadata'))){if(!(Test-Path -LiteralPath $d)){New-Item -ItemType Directory -Path $d -Force|Out-Null}}
    return $track
}
function Get-DistroShelfTrackArtifactDirectory { param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][ValidateSet('Distro','Podman','Distrobox','Flatpak','DistroShelf','metadata')][string]$Component) return Join-Path (Initialize-DistroShelfTrack $Distro).Root $Component }
function Get-DistroShelfTrackManifestPath { param([Parameter(Mandatory)][string]$Distro) return Join-Path (Initialize-DistroShelfTrack $Distro).Root 'metadata\track.json' }
function Get-DistroShelfTrackManifest { param([Parameter(Mandatory)][string]$Distro) $p=Get-DistroShelfTrackManifestPath $Distro;if(!(Test-Path -LiteralPath $p)){return $null};try{return Get-Content -LiteralPath $p -Raw|ConvertFrom-Json}catch{return $null} }
function Set-DistroShelfTrackManifest { param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][object]$Manifest) $Manifest|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Get-DistroShelfTrackManifestPath $Distro) -Encoding UTF8 }
function Write-DistroShelfTrackManifest { param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][string]$RootfsFile,[Parameter(Mandatory)][string]$RootfsSha256,[bool]$Podman=$false,[bool]$Distrobox=$false,[bool]$Flatpak=$false,[bool]$DistroShelf=$false) Set-DistroShelfTrackManifest $Distro ([pscustomobject][ordered]@{SchemaVersion=1;Distro=$Distro;Track=(Get-DistroShelfTrackDefinition $Distro).Name;Rootfs=[pscustomobject]@{File=$RootfsFile;Sha256=$RootfsSha256;Verified=$true};Dependencies=[pscustomobject]@{Podman=$Podman;Distrobox=$Distrobox;Flatpak=$Flatpak;DistroShelf=$DistroShelf};CreatedAt=[DateTime]::UtcNow.ToString('o');UpdatedAt=[DateTime]::UtcNow.ToString('o')}) }
function Set-DistroShelfTrackDependencyReady { param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][ValidateSet('Podman','Distrobox','Flatpak','DistroShelf')][string]$Component) $m=Get-DistroShelfTrackManifest $Distro;if(!$m){return};$m.Dependencies.$Component=$true;$m.UpdatedAt=[DateTime]::UtcNow.ToString('o');Set-DistroShelfTrackManifest $Distro $m }
function Test-DistroShelfTrackDependencyReady { param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][ValidateSet('Podman','Distrobox','Flatpak','DistroShelf')][string]$Component) $m=Get-DistroShelfTrackManifest $Distro;return [bool]($m -and $m.Dependencies -and $m.Dependencies.$Component -eq $true) }
function Test-DistroShelfTrackComplete { param([Parameter(Mandatory)][string]$Distro)
    $t=Get-DistroShelfTrackDefinition $Distro;$m=Get-DistroShelfTrackManifest $Distro
    if(!$m -or !$m.Rootfs -or !$m.Rootfs.File -or !$m.Rootfs.Sha256){return $false}
    $rootfs=Join-Path (Join-Path $t.Root 'Distro') ([string]$m.Rootfs.File)
    if(!(Test-Path -LiteralPath $rootfs -PathType Leaf)){return $false}
    try{if((Get-FileHash -LiteralPath $rootfs -Algorithm SHA256).Hash.ToLowerInvariant() -ne ([string]$m.Rootfs.Sha256).ToLowerInvariant()){return $false}}catch{return $false}
    foreach($c in @('Podman','Distrobox','Flatpak','DistroShelf')){if(-not (Test-DistroShelfTrackDependencyReady $Distro $c)){return $false}}
    $pod=@(Get-ChildItem (Get-DistroShelfTrackArtifactDirectory $Distro 'Podman') -File -ErrorAction SilentlyContinue).Count
    $db=@(Get-ChildItem (Get-DistroShelfTrackArtifactDirectory $Distro 'Distrobox') -File -ErrorAction SilentlyContinue).Count
    $flat=@(Get-ChildItem (Get-DistroShelfTrackArtifactDirectory $Distro 'Flatpak') -File -ErrorAction SilentlyContinue).Count
    $bundle=Test-Path -LiteralPath (Join-Path (Get-DistroShelfTrackArtifactDirectory $Distro 'DistroShelf') 'DistroShelf.flatpak') -PathType Leaf
    return ($pod -gt 0 -and $db -gt 0 -and $flat -gt 0 -and $bundle)
}
function Get-DistroShelfWslPath { param([Parameter(Mandatory)][string]$WindowsPath) $resolved=(Resolve-Path -LiteralPath $WindowsPath -ErrorAction Stop).Path;$r=& wsl.exe wslpath -a -u -- "$resolved" 2>$null;if($LASTEXITCODE -ne 0 -or !$r){throw "Unable to convert Windows path to WSL path: $WindowsPath"};return ([string]($r|Select-Object -First 1)).Trim() }
function Invoke-DistroShelfWslCopyCache {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][ValidateSet('Podman','Distrobox','Flatpak','DistroShelf')][string]$Component,[ValidateSet('Export','Seed')][string]$Mode='Export')
    $target=Get-DistroShelfTrackArtifactDirectory $Distro $Component;$targetWsl=Get-DistroShelfWslPath $target
    $cachePath=switch($Distro){'Ubuntu'{'/var/cache/apt/archives'}'Debian'{'/var/cache/apt/archives'}'Fedora'{'/var/cache/dnf'}'Arch Linux'{'/var/cache/pacman/pkg'}'openSUSE'{'/var/cache/zypp/packages'}}
    if($Mode -eq 'Export'){$cmd="mkdir -p '$targetWsl'; find '$cachePath' -type f \( -name '*.deb' -o -name '*.rpm' -o -name '*.pkg.tar.*' \) -exec cp -f {} '$targetWsl/' \;"}else{$cmd="mkdir -p '$cachePath'; find '$targetWsl' -maxdepth 1 -type f -exec cp -f {} '$cachePath/' \;"}
    & wsl.exe --distribution $WslName -- bash -lc $cmd;if($LASTEXITCODE -ne 0){throw "Unable to $Mode cached packages for $Component in '$WslName'."}
}
function New-DistroShelfFlatpakBundle {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$Distro)
    $target=Get-DistroShelfTrackArtifactDirectory $Distro 'DistroShelf';$targetWsl=Get-DistroShelfWslPath $target;$bundle=Join-Path $target 'DistroShelf.flatpak';$bundleWsl=Join-Path $targetWsl 'DistroShelf.flatpak'
    $cmd="if command -v flatpak >/dev/null 2>&1 && flatpak info com.ranfdev.DistroShelf >/dev/null 2>&1 && [ -d /var/lib/flatpak/repo ]; then flatpak build-bundle /var/lib/flatpak/repo '$bundleWsl' com.ranfdev.DistroShelf --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo; fi"
    & wsl.exe --distribution $WslName -- bash -lc $cmd
    if($LASTEXITCODE -ne 0){throw "Unable to create the DistroShelf Flatpak artifact for '$Distro'."}
    return (Test-Path -LiteralPath $bundle -PathType Leaf)
}
