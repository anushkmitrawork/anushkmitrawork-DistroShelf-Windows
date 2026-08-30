# Explicit opt-in live integration test for the Ubuntu Track.
# This test performs real WSL imports, package downloads, installs, and artifact creation.
# It never writes to committed Track 0 directly; failures remain in Troubleshoot.
# Run from repository root in an elevated PowerShell where WSL 2 is available:
#   $env:DISTROSHELF_RUN_LIVE_TESTS='1'
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\UbuntuLive.Tests.ps1

$ErrorActionPreference='Stop'
if($env:DISTROSHELF_RUN_LIVE_TESTS -ne '1'){
    Write-Host 'SKIP  Ubuntu live integration test is opt-in. Set DISTROSHELF_RUN_LIVE_TESTS=1 to run it.'
    exit 0
}

$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'src'
. (Join-Path $src 'Track\TrackEngine.ps1')
. (Join-Path $src 'DistroTrackManager.ps1')

function Pass([string]$m){Write-Host "PASS  $m"}
function Fail([string]$m){Write-Host "FAIL  $m";throw $m}

if(-not(Get-Command wsl.exe -ErrorAction SilentlyContinue)){Fail 'wsl.exe is not available.'}

$wslVersion=& wsl.exe --status 2>&1
if($LASTEXITCODE -ne 0){Fail "WSL status check failed: $($wslVersion -join "`n")"}

$provider=Get-DistroShelfProvider -Distro 'Ubuntu'
$txRoot=$null
$result=$null
try {
    Pass 'WSL is available'
    Pass "Ubuntu provider loaded with $(@($provider.Stages).Count) stages"

    $result=Invoke-DistroShelfTrackBuilder -Distro 'Ubuntu' -MaxConcurrency 1 -OnProgress {param($p,$m) Write-Host ("[{0,3}%] {1}" -f [int]$p,$m)}
    if(-not $result.Success){Fail "Ubuntu Track build failed: $($result.Error)"}
    if([string]::IsNullOrWhiteSpace([string]$result.FinalHash)){Fail 'Ubuntu Track build returned no final hash.'}
    if($result.FinalHash.Length -ne 64){Fail 'Ubuntu Track final hash is not SHA-256.'}
    if(-not(Test-Path -LiteralPath $result.TrackRoot -PathType Container)){Fail 'Ubuntu Track transaction tree was not produced.'}

    $stageCount=@($result.Stages).Count
    $expectedStageCount=@($provider.Stages).Count
    if($stageCount -ne $expectedStageCount){Fail "Ubuntu verified stage count mismatch: $stageCount/$expectedStageCount"}
    Pass "Ubuntu Track completed with $stageCount verified stages"

    $manifest=Join-Path $result.TrackRoot 'metadata\track.json'
    $hashRecord=Join-Path $result.TrackRoot 'metadata\track.hash.json'
    if(-not(Test-Path $manifest -PathType Leaf)){Fail 'Track manifest was not created.'}
    if(-not(Test-Path $hashRecord -PathType Leaf)){Fail 'Track final hash record was not created.'}
    Pass 'Ubuntu Track manifest and final hash record exist'

    $definition=Get-DistroShelfTrackDefinition -Distro 'Ubuntu'
    if(Test-Path -LiteralPath $definition.Root){Fail 'Live test unexpectedly wrote directly to committed Ubuntu Track.'}
    Pass 'Ubuntu live build remained isolated from committed Track 0'

    $meta=Get-Content $hashRecord -Raw|ConvertFrom-Json
    if([string]$meta.Hash -ne [string]$result.FinalHash){Fail 'Final Track hash record does not match builder result.'}
    Pass 'Ubuntu final Track hash is self-consistent'

    # Verify every non-rootfs stage produced a durable artifact tree before commit.
    foreach($stage in @($provider.Stages|Where-Object Id -ne 'rootfs')){
        $id=([string]$stage.Id -replace ':','-')
        $stageRoot=Join-Path $result.TrackRoot $id
        $stageHash=Join-Path $result.TrackRoot "metadata\$id.hash.json"
        if(-not(Test-Path $stageRoot -PathType Container)){Fail "Stage artifact tree missing: $id"}
        if(-not(Test-Path $stageHash -PathType Leaf)){Fail "Stage hash record missing: $id"}
        if(-not(Test-DistroShelfHashRecord -Path $stageHash -Root $stageRoot -Stage ([string]$stage.Id))){Fail "Stage hash does not verify: $id"}
    }
    Pass 'Every Ubuntu non-rootfs stage has a valid persisted artifact hash'

    $committed=Commit-DistroShelfTrackTransaction -BuildResult $result
    if(-not($committed.Success)){Fail 'Ubuntu Track commit did not report success.'}
    if(-not(Test-Path -LiteralPath $committed.Root -PathType Container)){Fail 'Committed Ubuntu Track directory is missing.'}
    Pass 'Ubuntu Track committed atomically after live verification'
}
catch {
    if($result -and $result.TroubleshootPath){Write-Host "Troubleshoot: $($result.TroubleshootPath)"}
    throw
}

Write-Host "`nUbuntu live Track integration test passed."
