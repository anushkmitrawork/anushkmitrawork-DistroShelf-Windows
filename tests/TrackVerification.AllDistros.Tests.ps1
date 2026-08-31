$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'src'
. (Join-Path $src 'Distro\Registry.ps1')
. (Join-Path $src 'Engine\HashEngine.ps1')

function Fail([string]$m){throw "FAIL  $m"}
function Pass([string]$m){Write-Host "PASS  $m"}

$distros=@('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')
foreach($distro in $distros){
    $provider=Get-DistroShelfProvider -Distro $distro
    $stages=@($provider.Stages)
    if(!$stages.Count){Fail "$distro has no Track stages"}
    if(@($provider.TrackFinalTests).Count -eq 0){Fail "$distro has no Track final acceptance tests"}

    foreach($stage in $stages){
        $id=[string]$stage.Id
        if($id -eq 'rootfs'){
            if(@($stage.Track.Tests).Count -eq 0){Fail "$distro rootfs has no Track tests"}
            continue
        }
        if(@($stage.Track.Acquire).Count -eq 0){Fail "$distro stage '$id' has no Track acquisition commands"}
        if(@($stage.Track.Install).Count -eq 0){Fail "$distro stage '$id' has no Track implementation commands"}
        if(@($stage.Track.Tests).Count -eq 0){Fail "$distro stage '$id' has no Track tests"}
        if([string]::IsNullOrWhiteSpace([string]$stage.Track.ExportType)){Fail "$distro stage '$id' has no Track artifact export type"}
    }
    Pass "$distro defines per-stage Track acquisition/install/test/export contracts and aggregate acceptance"
}

$trackText=Get-Content -LiteralPath (Join-Path $src 'Track\TrackEngine.ps1') -Raw
foreach($required in @('Invoke-DistroShelfTrackStage','Write-DistroShelfHashRecord','Test-DistroShelfHashRecord','Invoke-DistroShelfTrackAcceptance','Get-DistroShelfTreeHash')){
    if($trackText -notmatch [regex]::Escape($required)){Fail "Track engine is missing required verification primitive '$required'"}
}
Pass 'Track engine contains both dependency-level and aggregate verification primitives'

Write-Host "`nI.4 all-distro Track verification contract tests passed."
