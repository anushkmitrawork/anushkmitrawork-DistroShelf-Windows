# DistroShelf - committed Track registry
# A Track exists only when its final integrity hash is valid.

$script:DistroShelfTrackRoot = Join-Path $env:LOCALAPPDATA 'DistroShelf\tracks'

function Get-DistroShelfTrackDefinition {
    param([Parameter(Mandatory)][ValidateSet('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')][string]$Distro)
    $safe = switch ($Distro) { 'Ubuntu' {'Ubuntu'} 'Debian' {'Debian'} 'Fedora' {'Fedora'} 'Arch Linux' {'ArchLinux'} 'openSUSE' {'openSUSE'} }
    [pscustomobject][ordered]@{ Distro=$Distro; Name="${safe}0"; Root=(Join-Path $script:DistroShelfTrackRoot "${safe}0") }
}
function Get-DistroShelfTrackManifestPath {param([Parameter(Mandatory)][string]$Distro,[string]$RootOverride) $root=if($RootOverride){$RootOverride}else{(Get-DistroShelfTrackDefinition $Distro).Root};Join-Path $root 'metadata\track.json'}
function Get-DistroShelfTrackManifest {param([Parameter(Mandatory)][string]$Distro,[string]$RootOverride)$p=Get-DistroShelfTrackManifestPath $Distro $RootOverride;if(!(Test-Path $p -PathType Leaf)){return $null};try{Get-Content $p -Raw|ConvertFrom-Json}catch{return $null}}
function Test-DistroShelfTrackIntegrity {param([Parameter(Mandatory)][string]$Distro)$t=Get-DistroShelfTrackDefinition $Distro;$m=Get-DistroShelfTrackManifest $Distro;if(!$m -or [string]::IsNullOrWhiteSpace([string]$m.FinalHash)){return $false};try{return (Get-DistroShelfStageHash -Root $t.Root) -eq ([string]$m.FinalHash).ToLowerInvariant()}catch{return $false}}
function Test-DistroShelfTrackDependencyReady {param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][string]$Component)$m=Get-DistroShelfTrackManifest $Distro;if(!$m -or !$m.Stages){return $false};$stage=@($m.Stages)|?{[string]$_.Id -eq $Component}|Select-Object -First 1;if(!$stage -or [string]::IsNullOrWhiteSpace([string]$stage.Hash)){return $false};Test-DistroShelfHashRecord -Path (Join-Path (Join-Path (Get-DistroShelfTrackDefinition $Distro).Root 'metadata') "$Component.hash.json") -Root (Get-DistroShelfTrackDefinition $Distro).Root -ExpectedStage $Component}
function New-DistroShelfTrackAttemptRoot {param([Parameter(Mandatory)][string]$AttemptId)$root=Join-Path (Join-Path $env:LOCALAPPDATA 'DistroShelf\Attempts') $AttemptId;$track=Join-Path $root 'Track';New-Item -ItemType Directory -Path $track -Force|Out-Null;return $track}
