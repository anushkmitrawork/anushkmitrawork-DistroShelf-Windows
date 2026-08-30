$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'src'
function Pass([string]$m){Write-Host "PASS  $m"}
function Fail([string]$m){throw "FAIL  $m"}

. (Join-Path $src 'Engine\HashEngine.ps1')

$trackText=Get-Content -LiteralPath (Join-Path $src 'Track\TrackEngine.ps1') -Raw
$acceptanceText=Get-Content -LiteralPath (Join-Path $src 'Engine\AcceptanceEngine.ps1') -Raw
$managerText=Get-Content -LiteralPath (Join-Path $src 'DistroTrackManager.ps1') -Raw

if($trackText -notmatch 'Invoke-DistroShelfTrackStage'){Fail 'Track builder has no dependency-stage verification boundary'}
if($trackText -notmatch 'Write-DistroShelfHashRecord'){Fail 'Track builder does not persist dependency-level hashes'}
if($trackText -notmatch 'Test-DistroShelfHashRecord'){Fail 'Track builder does not immediately re-verify dependency hashes'}
Pass 'Track dependency-level verification and hashing are enforced'

$stageHashIndex=$trackText.IndexOf('Write-DistroShelfHashRecord')
$finalAcceptanceIndex=$trackText.IndexOf('Invoke-DistroShelfTrackAcceptance -WslName $builderName -Tests @($provider.TrackFinalTests)')
$finalHashIndex=$trackText.IndexOf('$finalHash=Get-DistroShelfTreeHash')
if($stageHashIndex -lt 0 -or $finalAcceptanceIndex -lt 0 -or $finalHashIndex -lt 0){Fail 'Track verification stages are not discoverable'}
if($stageHashIndex -ge $finalAcceptanceIndex -or $finalAcceptanceIndex -ge $finalHashIndex){Fail 'Track final acceptance/hash order is incorrect'}
Pass 'Track performs dependency verification before aggregate acceptance and final hash'

if($acceptanceText -notmatch 'function Invoke-DistroShelfTrackAcceptance'){Fail 'Track aggregate acceptance API is missing'}
if($trackText -notmatch 'provider\.TrackFinalTests'){Fail 'Track builder does not consume provider final acceptance tests'}
Pass 'Track has a distinct aggregate acceptance gate'

if($trackText -notmatch "-Stage 'track'"){Fail 'Track final hash is not persisted as a Track hash record'}
if($managerText -notmatch 'FinalHash'){Fail 'Committed Track source-of-truth has no final hash'}
if($managerText -notmatch 'Get-DistroShelfTreeHash'){Fail 'Committed Track integrity does not recompute the whole-Track hash'}
Pass 'Committed Track integrity is bound to the final whole-Track hash'

$temp=Join-Path ([IO.Path]::GetTempPath()) ('DistroShelf-TrackVerification-'+[guid]::NewGuid())
try {
    $track=Join-Path $temp 'Track'
    New-Item -ItemType Directory -Path (Join-Path $track 'metadata'),(Join-Path $track 'podman'),(Join-Path $track 'flatpak') -Force|Out-Null
    'podman-artifact'|Set-Content (Join-Path $track 'podman\artifact.txt')
    'flatpak-artifact'|Set-Content (Join-Path $track 'flatpak\artifact.txt')

    $podmanHash=Get-DistroShelfTreeHash -Root (Join-Path $track 'podman')
    $flatpakHash=Get-DistroShelfTreeHash -Root (Join-Path $track 'flatpak')
    Write-DistroShelfHashRecord -Path (Join-Path $track 'metadata\podman.hash.json') -Stage 'podman' -Hash $podmanHash -TestResult ([pscustomobject]@{Passed=$true})|Out-Null
    Write-DistroShelfHashRecord -Path (Join-Path $track 'metadata\flatpak.hash.json') -Stage 'flatpak' -Hash $flatpakHash -TestResult ([pscustomobject]@{Passed=$true})|Out-Null

    if(-not(Test-DistroShelfHashRecord -Path (Join-Path $track 'metadata\podman.hash.json') -Root (Join-Path $track 'podman') -Stage 'podman')){Fail 'podman dependency hash did not verify'}
    if(-not(Test-DistroShelfHashRecord -Path (Join-Path $track 'metadata\flatpak.hash.json') -Root (Join-Path $track 'flatpak') -Stage 'flatpak')){Fail 'flatpak dependency hash did not verify'}
    Pass 'multiple dependency hashes verify independently'

    foreach($stageId in @('podman','flatpak')){
        $record=Get-Content (Join-Path $track "metadata\$stageId.hash.json") -Raw|ConvertFrom-Json
        if([string]$record.Algorithm -ne 'SHA256'){Fail "dependency '$stageId' does not record SHA-256"}
        if(-not [bool]$record.Tests.Passed){Fail "dependency '$stageId' hash record does not attest a passing verification"}
    }
    Pass 'dependency hash records carry explicit SHA-256 and passing-test attestations'

    $wholeHash=Get-DistroShelfTreeHash -Root $track -ExcludeRelativePath @('metadata/track.hash.json','metadata/track.json')
    if([string]::IsNullOrWhiteSpace($wholeHash) -or $wholeHash.Length -ne 64){Fail 'whole-Track hash is not SHA-256'}
    Write-DistroShelfHashRecord -Path (Join-Path $track 'metadata\track.hash.json') -Stage 'track' -Hash $wholeHash -TestResult ([pscustomobject]@{Passed=$true})|Out-Null
    $record=Get-Content (Join-Path $track 'metadata\track.hash.json') -Raw|ConvertFrom-Json
    if([string]$record.Hash -ne $wholeHash){Fail 'whole-Track hash record does not match aggregate hash'}
    Pass 'whole Track receives an aggregate hash after dependency hashes'

    'tampered'|Set-Content (Join-Path $track 'podman\artifact.txt')
    $tamperedWhole=Get-DistroShelfTreeHash -Root $track -ExcludeRelativePath @('metadata/track.hash.json','metadata/track.json')
    if($tamperedWhole -eq $wholeHash){Fail 'dependency tampering did not change whole-Track hash'}
    if(Test-DistroShelfHashRecord -Path (Join-Path $track 'metadata\podman.hash.json') -Root (Join-Path $track 'podman') -Stage 'podman'){Fail 'tampered dependency still passed its hash record'}
    Pass 'dependency tampering invalidates both dependency and aggregate verification'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`nI.4 Track two-level verification contract tests passed."
