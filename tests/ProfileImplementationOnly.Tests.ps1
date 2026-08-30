# DistroShelf - Profile implementation-only contract tests
# I.3: Profile consumes verified Track material and does not acquire Track-managed resources.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'src'
. (Join-Path $src 'Distro\Registry.ps1')
. (Join-Path $src 'Profile\ProfileArtifactInstaller.ps1')

function Pass([string]$Message) { Write-Host "PASS  $Message" }
function Fail([string]$Message) { throw "FAIL  $Message" }

$distros = @('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')
$remotePattern = '(^|[;&|`n\r]|\s)(curl|wget|Invoke-WebRequest|git\s+clone|apt(-get)?\s+.*https?://|dnf\s+.*https?://|zypper\s+.*https?://|pacman\s+.*https?://|flatpak\s+install\s+.*https?://)'

foreach($distro in $distros) {
    $provider = Get-DistroShelfProvider -Distro $distro
    foreach($stage in @($provider.Stages)) {
        $id = [string]$stage.Id
        if(-not $stage.Profile) { Fail "$distro/$id has no Profile contract" }
        if($stage.Profile.PSObject.Properties.Name -contains 'Acquire') { Fail "$distro/$id exposes Profile.Acquire" }
        foreach($command in @($stage.Profile.Install)) {
            if([string]$command -match $remotePattern) {
                Fail "$distro/$id contains a network acquisition command in Profile.Install: $command"
            }
        }
        if($id -ne 'rootfs' -and @($stage.Profile.Install).Count -eq 0 -and [string]$stage.Track.ExportType -notin @('wsl-path','flatpak-sideload')) {
            Fail "$distro/$id has no Profile implementation contract"
        }
        Test-DistroShelfProfileInstallCommands -Stage $stage | Out-Null
    }
    Pass "${distro}: Profile has implementation-only commands"
}

$installerText = Get-Content -LiteralPath (Join-Path $src 'Profile\ProfileArtifactInstaller.ps1') -Raw
# Inspect executable command positions only; the source file itself contains the forbidden
# command names inside Test-DistroShelfProfileInstallCommands' detection regex.
$installerExecutableLines = @($installerText -split "`r?`n" | Where-Object {
    $_ -notmatch '\$remotePattern\s*=' -and $_ -notmatch "contains a network acquisition command"
}) -join "`n"
if($installerExecutableLines -match '(?m)^\s*(Invoke-WebRequest|curl\s|wget\s|git\s+clone)') {
    Fail 'ProfileArtifactInstaller contains direct network acquisition commands'
}
if($installerText -notmatch '/track-stage/') {
    Fail 'ProfileArtifactInstaller is not bound to bridged Track artifacts'
}
Pass 'ProfileArtifactInstaller consumes Track-mounted artifacts'

$engineText = Get-Content -LiteralPath (Join-Path $src 'Profile\ProfileEngine.ps1') -Raw
if($engineText -match '(?m)^\s*(Invoke-WebRequest|curl\s|wget\s|git\s+clone)') {
    Fail 'ProfileEngine contains direct network acquisition commands'
}
if($engineText -notmatch 'Mount-DistroShelfTrackStageIntoProfile') {
    Fail 'ProfileEngine does not mount Track material before implementation'
}
if($engineText -notmatch 'Install-DistroShelfProfileStageFromTrack') {
    Fail 'ProfileEngine does not implement stages from Track material'
}
Pass 'ProfileEngine is bound to Track consumption'

Write-Host "`nI.3 Profile implementation-only contract tests passed."
