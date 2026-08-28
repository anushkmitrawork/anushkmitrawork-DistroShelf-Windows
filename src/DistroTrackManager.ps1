# DistroShelf for Windows - per-distro track manager
# Track 0 is the reusable artifact/cache source for one distro.

$script:DistroShelfTrackRoot = Join-Path $env:LOCALAPPDATA 'DistroShelf\tracks'

function Get-DistroShelfTrackDefinition {
    param([Parameter(Mandatory)][string]$Distro)
    $safeName = switch ($Distro) {
        'Ubuntu' { 'Ubuntu' }; 'Debian' { 'Debian' }; 'Fedora' { 'Fedora' }; 'Arch Linux' { 'ArchLinux' }; 'openSUSE' { 'openSUSE' }
        default { throw "Unsupported DistroShelf track: $Distro" }
    }
    [pscustomobject][ordered]@{ Distro=$Distro; Name="${safeName}0"; Root=(Join-Path $script:DistroShelfTrackRoot "${safeName}0") }
}

function Initialize-DistroShelfTrack {
    param([Parameter(Mandatory)][string]$Distro)
    $track=Get-DistroShelfTrackDefinition $Distro
    foreach($d in @($track.Root,(Join-Path $track.Root 'Distro'),(Join-Path $track.Root 'Podman'),(Join-Path $track.Root 'Distrobox'),(Join-Path $track.Root 'Flatpak'),(Join-Path $track.Root 'DistroShelf'),(Join-Path $track.Root 'metadata'))){if(!(Test-Path -LiteralPath $d)){New-Item -ItemType Directory -Path $d -Force|Out-Null}}
    return $track
}

function Get-DistroShelfTrackArtifactDirectory {
    param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][ValidateSet('Distro','Podman','Distrobox','Flatpak','DistroShelf','metadata')][string]$Component)
    return Join-Path (Initialize-DistroShelfTrack $Distro).Root $Component
}
function Get-DistroShelfTrackManifestPath { param([Parameter(Mandatory)][string]$Distro) return Join-Path (Initialize-DistroShelfTrack $Distro).Root 'metadata\track.json' }
function Get-DistroShelfTrackManifest { param([Parameter(Mandatory)][string]$Distro) $p=Get-DistroShelfTrackManifestPath $Distro;if(!(Test-Path -LiteralPath $p)){return $null};try{return Get-Content -LiteralPath $p -Raw|ConvertFrom-Json}catch{return $null} }
function Set-DistroShelfTrackManifest { param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][object]$Manifest) $Manifest|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Get-DistroShelfTrackManifestPath $Distro) -Encoding UTF8 }

function Write-DistroShelfTrackManifest {
    param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][string]$RootfsFile,[Parameter(Mandatory)][string]$RootfsSha256,[bool]$Podman=$false,[bool]$Distrobox=$false,[bool]$Flatpak=$false,[bool]$DistroShelf=$false)
    Set-DistroShelfTrackManifest $Distro ([pscustomobject][ordered]@{SchemaVersion=1;Distro=$Distro;Track=(Get-DistroShelfTrackDefinition $Distro).Name;Rootfs=[pscustomobject]@{File=$RootfsFile;Sha256=$RootfsSha256;Verified=$true};Dependencies=[pscustomobject]@{Podman=$Podman;Distrobox=$Distrobox;Flatpak=$Flatpak;DistroShelf=$DistroShelf};CreatedAt=[DateTime]::UtcNow.ToString('o');UpdatedAt=[DateTime]::UtcNow.ToString('o')})
}
function Set-DistroShelfTrackDependencyReady {
    param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][ValidateSet('Podman','Distrobox','Flatpak','DistroShelf')][string]$Component)
    $m=Get-DistroShelfTrackManifest $Distro;if(!$m){return};$m.Dependencies.$Component=$true;$m.UpdatedAt=[DateTime]::UtcNow.ToString('o');Set-DistroShelfTrackManifest $Distro $m
}
function Test-DistroShelfTrackDependencyReady { param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][ValidateSet('Podman','Distrobox','Flatpak','DistroShelf')][string]$Component) $m=Get-DistroShelfTrackManifest $Distro;return [bool]($m -and $m.Dependencies -and $m.Dependencies.$Component -eq $true) }

function Get-DistroShelfWslPath {
    param([Parameter(Mandatory)][string]$WindowsPath)
    $resolved=(Resolve-Path -LiteralPath $WindowsPath -ErrorAction Stop).Path;$r=& wsl.exe wslpath -a -u -- "$resolved" 2>$null;if($LASTEXITCODE-ne 0-or !$r){throw "Unable to convert Windows path to WSL path: $WindowsPath"};return ([string]($r|Select-Object -First 1)).Trim()
}

function Invoke-DistroShelfWslCopyCache {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][ValidateSet('Podman','Distrobox','Flatpak','DistroShelf')][string]$Component,[ValidateSet('Export','Seed')][string]$Mode='Export')
    $target=Get-DistroShelfTrackArtifactDirectory $Distro $Component;$targetWsl=Get-DistroShelfWslPath $target
    $cachePath=switch($Distro){'Ubuntu'{'/var/cache/apt/archives'}'Debian'{'/var/cache/apt/archives'}'Fedora'{'/var/cache/dnf'}'Arch Linux'{'/var/cache/pacman/pkg'}'openSUSE'{'/var/cache/zypp/packages'}}
    if($Mode-eq'Export'){$cmd="mkdir -p '$targetWsl'; find '$cachePath' -type f \( -name '*.deb' -o -name '*.rpm' -o -name '*.pkg.tar.*' \) -exec cp -f {} '$targetWsl/' \;"}else{$cmd="mkdir -p '$cachePath'; find '$targetWsl' -maxdepth 1 -type f -exec cp -f {} '$cachePath/' \;"}
    & wsl.exe --distribution $WslName -- bash -lc $cmd;if($LASTEXITCODE-ne 0){throw "Unable to $Mode cached packages for $Component in '$WslName'."}
}
