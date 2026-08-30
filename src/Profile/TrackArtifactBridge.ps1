# DistroShelf - bridge verified Track resources into an isolated Profile

function Mount-DistroShelfTrackStageIntoProfile {
    param(
        [Parameter(Mandatory)][string]$WslName,
        [Parameter(Mandatory)][string]$TrackRoot,
        [Parameter(Mandatory)][string]$StageId
    )
    $source=Join-Path $TrackRoot ($StageId -replace ':','-')
    if(-not(Test-Path -LiteralPath $source -PathType Container)){throw "Verified Track stage '$StageId' is missing from '$TrackRoot'."}
    $destination="/track/$($StageId -replace ':','-')"
    Invoke-DistroShelfCommand -WslName $WslName -Command "rm -rf '$destination'; mkdir -p '$destination'"|Out-Null
    $share="\\wsl$\$WslName$destination"
    if(-not(Test-Path -LiteralPath $share -PathType Container)){throw "Unable to create Profile Track bridge for stage '$StageId'."}
    Copy-Item -LiteralPath (Join-Path $source '*') -Destination $share -Recurse -Force -ErrorAction Stop
    if(@(Get-ChildItem -LiteralPath $share -Recurse -File -ErrorAction SilentlyContinue).Count -eq 0){throw "Track stage '$StageId' bridged into Profile but contains no artifacts."}
    return $destination
}

function Test-DistroShelfRequiredTrackStages {
    param([Parameter(Mandatory)][string]$TrackRoot,[Parameter(Mandatory)][object[]]$Stages)
    foreach($stage in @($Stages)){
        $id=[string]$stage.Id
        if($id -eq 'rootfs'){continue}
        if(-not(Test-DistroShelfHashRecord -Path (Join-Path (Join-Path $TrackRoot 'metadata') "$($id -replace ':','-').hash.json") -Root (Join-Path $TrackRoot ($id -replace ':','-')) -Stage $id)){
            throw "Required verified Track stage '$id' is unavailable or invalid."
        }
    }
    $true
}
