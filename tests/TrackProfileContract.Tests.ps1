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

Write-Host "`nTrack/Profile responsibility contract tests passed."
exit 0
