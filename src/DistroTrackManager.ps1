# DistroShelf - committed Track registry
# A Track exists only when its final integrity hash is valid.

$script:DistroShelfTrackRoot = Join-Path $env:LOCALAPPDATA 'DistroShelf\tracks'

function Get-DistroShelfTrackDefinition {
    param([Parameter(Mandatory)][ValidateSet('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')][string]$Distro)
    $safe = switch ($Distro) { 'Ubuntu' {'Ubuntu'} 'Debian' {'Debian'} 'Fedora' {'Fedora'} 'Arch Linux' {'ArchLinux'} 'openSUSE' {'openSUSE'} }
    [pscustomobject][ordered]@{ Distro=$Distro; Name="${safe}0"; Root=(Join-Path $script:DistroShelfTrackRoot "${safe}0") }
}

function Get-DistroShelfTrackManifestPath {
    param([Parameter(Mandatory)][string]$Distro,[string]$RootOverride)
    $root=if($RootOverride){$RootOverride}else{(Get-DistroShelfTrackDefinition $Distro).Root}
    Join-Path $root 'metadata\track.json'
}

function Get-DistroShelfTrackManifest {
    param([Parameter(Mandatory)][string]$Distro,[string]$RootOverride)
    $p=Get-DistroShelfTrackManifestPath $Distro $RootOverride
    if(!(Test-Path $p -PathType Leaf)){return $null}
    try{Get-Content $p -Raw|ConvertFrom-Json}catch{return $null}
}

function Test-DistroShelfTrackIntegrity {
    param([Parameter(Mandatory)][string]$Distro)
    $t=Get-DistroShelfTrackDefinition $Distro
    $m=Get-DistroShelfTrackManifest $Distro
    if(!$m -or [string]::IsNullOrWhiteSpace([string]$m.FinalHash)){return $false}
    try{
        $hash=Get-DistroShelfTreeHash -Root $t.Root -ExcludeRelativePath @('metadata/track.hash.json','metadata/track.json')
        return $hash -eq ([string]$m.FinalHash).ToLowerInvariant()
    }catch{return $false}
}

function Test-DistroShelfTrackDependencyReady {
    param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][string]$Component)
    $definition=Get-DistroShelfTrackDefinition $Distro
    $manifest=Get-DistroShelfTrackManifest $Distro
    if(!$manifest -or !$manifest.Stages){return $false}
    $stage=@($manifest.Stages)|Where-Object{[string]$_.Id -eq $Component}|Select-Object -First 1
    if(!$stage -or [string]::IsNullOrWhiteSpace([string]$stage.Hash)){return $false}
    $safe=$Component -replace ':','-'
    $stageRoot=Join-Path $definition.Root $safe
    if($Component -eq 'rootfs'){$stageRoot=Join-Path $definition.Root 'Distro'}
    $record=Join-Path (Join-Path $definition.Root 'metadata') "$safe.hash.json"
    if(!(Test-Path -LiteralPath $stageRoot -PathType Container) -or !(Test-Path -LiteralPath $record -PathType Leaf)){return $false}
    try{return [bool](Test-DistroShelfHashRecord -Path $record -Root $stageRoot -Stage $Component)}catch{return $false}
}

function New-DistroShelfTrackAttemptRoot {
    param([Parameter(Mandatory)][string]$AttemptId)
    $root=Join-Path (Join-Path $env:LOCALAPPDATA 'DistroShelf\Attempts') $AttemptId
    $track=Join-Path $root 'Track'
    New-Item -ItemType Directory -Path $track -Force|Out-Null
    return $track
}
