# DistroShelf - provider contract
# A provider describes acquisition/install/test behavior. The transaction engine never invents distro commands.

function New-DistroShelfProvider {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$PackageManager,
        [Parameter(Mandatory)][hashtable]$Stages,
        [Parameter(Mandatory)][object[]]$TrackFinalTests,
        [Parameter(Mandatory)][object[]]$ProfileFinalTests
    )
    [pscustomobject][ordered]@{
        SchemaVersion = 1
        Distro = $Distro
        PackageManager = $PackageManager
        Stages = $Stages
        TrackFinalTests = @($TrackFinalTests)
        ProfileFinalTests = @($ProfileFinalTests)
    }
}

function Test-DistroShelfProviderContract {
    param([Parameter(Mandatory)]$Provider)
    $errors = @()
    if([string]::IsNullOrWhiteSpace([string]$Provider.Distro)){ $errors += 'Provider has no distro.' }
    if([string]::IsNullOrWhiteSpace([string]$Provider.PackageManager)){ $errors += "Provider '$($Provider.Distro)' has no package manager." }
    if(!$Provider.Stages -or $Provider.Stages.Count -eq 0){ $errors += "Provider '$($Provider.Distro)' has no stages." }
    foreach($entry in @($Provider.Stages.GetEnumerator())) {
        $id=[string]$entry.Key;$stage=$entry.Value
        if([string]::IsNullOrWhiteSpace($id)){ $errors += 'Provider contains an empty stage id.'; continue }
        if(!$stage.ContainsKey('Track')){ $errors += "Stage '$id' has no Track contract." }
        if(!$stage.ContainsKey('Profile')){ $errors += "Stage '$id' has no Profile contract." }
        if($id -ne 'rootfs' -and @($stage.Track.Tests).Count -eq 0){ $errors += "Stage '$id' has no Track tests." }
        if($id -ne 'rootfs' -and @($stage.Profile.Tests).Count -eq 0){ $errors += "Stage '$id' has no Profile tests." }
    }
    if(@($Provider.TrackFinalTests).Count -eq 0){ $errors += "Provider '$($Provider.Distro)' has no Track final tests." }
    if(@($Provider.ProfileFinalTests).Count -eq 0){ $errors += "Provider '$($Provider.Distro)' has no Profile final tests." }
    [pscustomobject][ordered]@{Valid=($errors.Count -eq 0);Distro=$Provider.Distro;Errors=$errors}
}
