# Non-destructive architecture contract tests for Track acquisition/implementation vs Profile implementation.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'src'
. (Join-Path $src 'Distro\Registry.ps1')

function Pass([string]$m){Write-Host "PASS  $m"}
function Fail([string]$m){throw "FAIL  $m"}

$distros=@('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')
foreach($distro in $distros){
    $provider=Get-DistroShelfProvider -Distro $distro
    $stages=@($provider.Stages)
    if(!$stages.Count){Fail "No stages for $distro"}

    foreach($stage in $stages){
        $id=[string]$stage.Id
        if(!$stage.Track -or !$stage.Profile){Fail "$distro/$id is missing Track/Profile contracts"}
        if($id -eq 'rootfs'){continue}

        if(@($stage.Track.Acquire).Count -eq 0){Fail "$distro/$id does not acquire resources in Track"}
        if(-not ($stage.Track.PSObject.Properties.Name -contains 'Install')){Fail "$distro/$id has no Track implementation contract"}
        if(@($stage.Profile.Install).Count -eq 0){Fail "$distro/$id does not implement resources in Profile"}
        if($stage.Profile.PSObject.Properties.Name -contains 'Acquire'){Fail "$distro/$id incorrectly exposes Profile acquisition"}
    }
    Pass "$distro: Track acquires; Track implements; Profile only implements"
}

$packageText=Get-Content (Join-Path $src 'Distro\PackageAcquisition.ps1') -Raw
foreach($token in @('Track=[pscustomobject][ordered]@{Acquire=','Install=','Profile=[pscustomobject][ordered]@{Install=')){
    if($packageText -notmatch [regex]::Escape($token)){Fail "Package acquisition contract missing: $token"}
}
if($packageText -notmatch 'apt-get -y --no-download'){Fail 'APT Profile implementation is not offline'}
if($packageText -notmatch 'dnf -y --disablerepo='){Fail 'DNF Profile implementation is not offline'}
if($packageText -notmatch 'pacman -U --noconfirm /track-stage/'){Fail 'Pacman Profile implementation does not consume Track artifacts'}
if($packageText -notmatch 'zypper --non-interactive install /track-stage/'){Fail 'Zypper Profile implementation does not consume Track artifacts'}
Pass 'Profile package implementations consume Track artifacts without network acquisition'

$trackText=Get-Content (Join-Path $src 'Track\TrackEngine.ps1') -Raw
$acquirePos=$trackText.IndexOf('Invoke-DistroShelfCommands -WslName $builderName -Commands @($Stage.Track.Acquire)')
$installPos=$trackText.IndexOf('Invoke-DistroShelfCommands -WslName $builderName -Commands @($Stage.Track.Install)')
$testPos=$trackText.IndexOf('Invoke-DistroShelfStageTests -WslName $builderName -Tests @($Stage.Track.Tests)')
if($acquirePos -lt 0 -or $installPos -lt 0 -or $testPos -lt 0){Fail 'Track stage executor does not expose acquire → implement → test flow'}
if(-not($acquirePos -lt $installPos -and $installPos -lt $testPos)){Fail 'Track stage execution order is not acquire → implement → test'}
Pass 'Track engine executes acquisition before implementation and testing'

Write-Host "`nTrack/Profile responsibility contract tests passed."
exit 0
