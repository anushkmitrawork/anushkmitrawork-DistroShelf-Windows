# DistroShelf - static validation for distro provider stage contracts

function Test-DistroShelfStageContract {
    param([Parameter(Mandatory)][object]$Stage,[Parameter(Mandatory)][string]$Distro)
    $errors=@()
    $id=[string]$Stage.Id
    if([string]::IsNullOrWhiteSpace($id)){$errors+='Missing stage Id.'}
    if(-not $Stage.Track){$errors+="Stage '$id' has no Track contract."}
    if(-not $Stage.Profile){$errors+="Stage '$id' has no Profile contract."}
    if($Stage.Track -and @($Stage.Track.Tests).Count -eq 0 -and $id -ne 'rootfs'){$errors+="Stage '$id' has no Track tests."}
    if($Stage.Profile -and @($Stage.Profile.Tests).Count -eq 0 -and $id -ne 'rootfs'){$errors+="Stage '$id' has no Profile tests."}
    if($Stage.Track -and @($Stage.Track.Acquire).Count -eq 0 -and $id -ne 'rootfs'){$errors+="Stage '$id' has no Track acquisition commands."}
    if($Stage.Track -and [string]$Stage.Track.ExportType -notin @('none','apt-cache','rpm-cache','pacman-cache','wsl-path','flatpak-sideload') -and $id -ne 'rootfs'){$errors+="Stage '$id' has unsupported Track export type '$($Stage.Track.ExportType)'."}
    if($Stage.Track -and [string]$Stage.Track.ExportType -eq 'wsl-path' -and [string]::IsNullOrWhiteSpace([string]$Stage.Track.ExportValue)){$errors+="Stage '$id' uses wsl-path export without ExportValue."}
    if([string]$Stage.ExecutionModel -notin @('SharedBuilder','IsolatedBuilder')){$errors+="Stage '$id' has invalid ExecutionModel '$($Stage.ExecutionModel)'."}
    [pscustomobject][ordered]@{Distro=$Distro;Stage=$id;Valid=($errors.Count -eq 0);Errors=$errors}
}

function Invoke-DistroShelfDefinitionValidation {
    . (Join-Path $PSScriptRoot '..\Distro\Registry.ps1')
    $all=@()
    foreach($d in @('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')){
        $provider=Get-DistroShelfProvider -Distro $d
        foreach($s in @($provider.Stages)){$all+=Test-DistroShelfStageContract -Stage $s -Distro $d}
        if(-not @($provider.TrackFinalTests).Count){$all+=[pscustomobject]@{Distro=$d;Stage='track-final';Valid=$false;Errors=@('No final Track acceptance tests.')}}
        if(-not @($provider.ProfileFinalTests).Count){$all+=[pscustomobject]@{Distro=$d;Stage='profile-final';Valid=$false;Errors=@('No final Profile acceptance tests.')}}
    }
    return $all
}
