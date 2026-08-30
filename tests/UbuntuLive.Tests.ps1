# Explicit opt-in live integration test for Ubuntu Track and Profile.
# This performs real WSL imports, downloads, package installs and artifact creation.
# It never writes an unverified Track or Profile directly into the committed stores.
# Run from repository root in an elevated PowerShell with WSL 2 available:
#   $env:DISTROSHELF_RUN_LIVE_TESTS='1'
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\UbuntuLive.Tests.ps1

$ErrorActionPreference='Stop'
if($env:DISTROSHELF_RUN_LIVE_TESTS -ne '1'){
    Write-Host 'SKIP  Ubuntu live integration test is opt-in. Set DISTROSHELF_RUN_LIVE_TESTS=1 to run it.'
    exit 0
}

$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'src'
. (Join-Path $src 'Engine\TransactionEngine.ps1')
. (Join-Path $src 'Engine\HashEngine.ps1')
. (Join-Path $src 'Engine\AcceptanceEngine.ps1')
. (Join-Path $src 'Engine\DagScheduler.ps1')
. (Join-Path $src 'Engine\StageExecutor.ps1')
. (Join-Path $src 'Engine\ArtifactExporter.ps1')
. (Join-Path $src 'Distro\Registry.ps1')
. (Join-Path $src 'DistroTrackManager.ps1')
. (Join-Path $src 'Track\RootfsAcquisition.ps1')
. (Join-Path $src 'Track\TrackEngine.ps1')
. (Join-Path $src 'ProfileManager.ps1')
. (Join-Path $src 'Profile\ProfileReservation.ps1')
. (Join-Path $src 'Profile\TrackArtifactBridge.ps1')
. (Join-Path $src 'Profile\ProfileArtifactInstaller.ps1')
. (Join-Path $src 'Profile\ProfileEngine.ps1')
. (Join-Path $src 'Profile\ProfileCommit.ps1')

function Pass([string]$m){Write-Host "PASS  $m"}
function Fail([string]$m){Write-Host "FAIL  $m";throw $m}

if(-not(Get-Command wsl.exe -ErrorAction SilentlyContinue)){Fail 'wsl.exe is not available.'}
$status=& wsl.exe --status 2>&1
if($LASTEXITCODE-ne 0){Fail "WSL status check failed: $($status -join "`n")"}

$provider=Get-DistroShelfProvider -Distro 'Ubuntu'
$trackDef=Get-DistroShelfTrackDefinition -Distro 'Ubuntu'
if(Test-Path -LiteralPath $trackDef.Root){Fail 'Refusing live run because committed Ubuntu Track 0 already exists; remove it only through a deliberate test reset.'}
Pass 'Ubuntu Track 0 is absent before live build'

$trackBuild=Invoke-DistroShelfTrackBuilder -Distro 'Ubuntu' -MaxConcurrency 1 -OnProgress {param($p,$m)Write-Host ("[TRACK {0,3}%] {1}" -f [int]$p,$m)}
if(-not $trackBuild.Success){Fail "Ubuntu Track build failed: $($trackBuild.Error)`nTroubleshoot: $($trackBuild.TroubleshootPath)"}
if(@($trackBuild.Stages).Count -ne @($provider.Stages).Count){Fail "Verified stage count mismatch: $(@($trackBuild.Stages).Count)/$(@($provider.Stages).Count)"}
if([string]$trackBuild.FinalHash -notmatch '^[0-9a-f]{64}$'){Fail 'Ubuntu Track final hash is not SHA-256.'}
Pass 'Ubuntu Track completed with every provider stage verified'

$trackCommit=Commit-DistroShelfTrackTransaction -BuildResult $trackBuild
if(-not $trackCommit.Success){Fail 'Ubuntu Track commit failed.'}
if(-not(Test-DistroShelfTrackIntegrity -Distro 'Ubuntu')){Fail 'Committed Ubuntu Track failed final integrity verification.'}
Pass 'Ubuntu Track 0 committed and integrity-verified'

$trackMeta=Get-DistroShelfTrackManifest -Distro 'Ubuntu'
if([string]$trackMeta.FinalHash -ne [string]$trackCommit.FinalHash){Fail 'Committed Track final hash differs from build result.'}
Pass 'Committed Ubuntu Track hash matches verified build result'

$reservation=Reserve-DistroShelfProfileNumber -Distro 'Ubuntu'
$candidate=[pscustomobject]@{Id=$reservation.Id;Name=$reservation.Name;Distro='Ubuntu';WslName="DistroShelf-$($reservation.Name)";PackageManager='apt';Status='Candidate';Terminal='GNOME Console'}
try {
    $profile=Invoke-DistroShelfProfileBuild -Distro 'Ubuntu' -Terminal 'GNOME Console' -TrackRoot $trackDef.Root -TrackHash ([string]$trackMeta.FinalHash) -Candidate $candidate -OnProgress {param($p,$m)Write-Host ("[PROFILE {0,3}%] {1}" -f [int]$p,$m)}
    if(-not $profile.Success){Fail "Ubuntu Profile build failed: $($profile.Error)`nTroubleshoot: $($profile.TroubleshootPath)"}
    if([string]$profile.ProfileHash -notmatch '^[0-9a-f]{64}$'){Fail 'Ubuntu Profile hash is not SHA-256.'}
    if(-not(Test-Path -LiteralPath $profile.ExportPath -PathType Leaf)){Fail 'Accepted Profile export is missing.'}
    $profileHash=(Get-FileHash -LiteralPath $profile.ExportPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($profileHash -ne [string]$profile.ProfileHash){Fail 'Accepted Profile export hash is inconsistent.'}
    Pass 'Ubuntu Profile passed full acceptance and produced its single accepted export'

    $profileCommit=Commit-DistroShelfProfileTransaction -BuildResult $profile -Reservation $reservation -Terminal 'GNOME Console'
    if(-not $profileCommit.Success){Fail 'Ubuntu Profile commit failed.'}
    $reservation=$null
    if(-not(Test-Path -LiteralPath $profileCommit.Root -PathType Container)){Fail 'Committed Profile root is missing.'}
    $record=Get-DistroShelfProfileById -Id $candidate.Id
    if(-not $record -or [string]$record.Status -ne 'Ready'){Fail 'Committed Profile registry record is missing or not Ready.'}
    if([string]$record.ProfileHash -ne [string]$profile.ProfileHash){Fail 'Committed Profile registry hash differs from accepted export.'}
    Pass "Ubuntu Profile $($candidate.Name) committed from the exact accepted export"
}
finally {
    if($reservation){try{Release-DistroShelfProfileReservation -Reservation $reservation}catch{}}
}

Write-Host "`nUbuntu live Track + Profile integration test passed."
