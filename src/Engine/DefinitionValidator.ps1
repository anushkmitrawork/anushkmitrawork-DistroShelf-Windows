# DistroShelf - static validation for distro stage contracts

function Test-DistroShelfStageContract {
    param([Parameter(Mandatory)][object]$Stage,[Parameter(Mandatory)][string]$Distro)
    $errors=@()
    if([string]::IsNullOrWhiteSpace([string]$Stage.Id)){$errors+='Missing stage Id.'}
    if([string]$Stage.Id -ne 'rootfs' -and -not $Stage.Track){$errors+="Stage '$($Stage.Id)' has no Track contract."}
    if([string]$Stage.Id -ne 'rootfs' -and -not $Stage.Profile){$errors+="Stage '$($Stage.Id)' has no Profile contract."}
    if($Stage.Track -and @($Stage.Track.Tests).Count -eq 0 -and [string]$Stage.Id -ne 'rootfs'){$errors+="Stage '$($Stage.Id)' has no Track tests."}
    if($Stage.Profile -and @($Stage.Profile.Tests).Count -eq 0 -and [string]$Stage.Id -ne 'rootfs'){$errors+="Stage '$($Stage.Id)' has no Profile tests."}
    [pscustomobject][ordered]@{Distro=$Distro;Stage=[string]$Stage.Id;Valid=($errors.Count -eq 0);Errors=$errors}
}

function Invoke-DistroShelfDefinitionValidation {
    $all=@()
    foreach($d in @('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')){
        $def=Get-DistroShelfDistroDefinition $d
        foreach($s in @($def.Stages)){$all+=Test-DistroShelfStageContract -Stage $s -Distro $d}
        if(-not @($def.TrackFinalTests).Count){$all+=[pscustomobject]@{Distro=$d;Stage='track-final';Valid=$false;Errors=@('No final Track acceptance tests.')}}
        if(-not @($def.ProfileFinalTests).Count){$all+=[pscustomobject]@{Distro=$d;Stage='profile-final';Valid=$false;Errors=@('No final Profile acceptance tests.')}}
    }
    return $all
}
