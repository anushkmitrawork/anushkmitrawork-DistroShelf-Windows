$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'src'
function Pass($m){Write-Host "PASS  $m"}
function Fail($m){throw "FAIL  $m"}
. (Join-Path $src 'Engine\TransactionEngine.ps1')
. (Join-Path $src 'Engine\HashEngine.ps1')
. (Join-Path $src 'Engine\AtomicCommit.ps1')
. (Join-Path $src 'DistroTrackManager.ps1')
. (Join-Path $src 'Track\TrackEngine.ps1')

function New-TestBuild {
    param([string]$Name)
    $root=Join-Path ([IO.Path]::GetTempPath()) ("DistroShelf-TrackAtomic-$Name-"+[guid]::NewGuid())
    $track=Join-Path $root 'Track'
    New-Item -ItemType Directory -Path (Join-Path $track 'metadata') -Force|Out-Null
    'stable-track-payload'|Set-Content (Join-Path $track 'payload.txt')
    $hash=Get-DistroShelfTreeHash -Root $track -ExcludeRelativePath @('metadata')
    $candidate=[pscustomobject]@{Id="tx-$Name";Distro='Debian'}
    [pscustomobject]@{Root=$root;Track=$track;Hash=$hash;Build=[pscustomobject]@{Success=$true;Transaction=[pscustomobject]@{Distro='Debian';Root=$root};TrackRoot=$track;FinalHash=$hash}}
}

$scenarios=@()
try {
    $s=New-TestBuild 'success';$scenarios+=$s
    $target=Join-Path $s.Root 'committed'
    $result=Commit-DistroShelfTrackTransaction -BuildResult $s.Build -TargetRoot $target -IntegrityCheck { param($d) $true }
    if($result.Success -and (Test-Path (Join-Path $target 'payload.txt'))){Pass 'successful Track commit promotes exact transaction tree'}else{Fail 'successful Track commit failed'}
    Remove-Item -LiteralPath $target -Recurse -Force

    $s=New-TestBuild 'tamper';$scenarios+=$s
    'tampered'|Set-Content (Join-Path $s.Track 'payload.txt')
    try { Commit-DistroShelfTrackTransaction -BuildResult $s.Build -TargetRoot (Join-Path $s.Root 'committed') -IntegrityCheck { param($d) $true }|Out-Null;Fail 'tampered Track was accepted' } catch { Pass 'Track hash mismatch blocks commit before promotion' }
    if(Test-Path -LiteralPath (Join-Path $s.Root 'Track\payload.txt')){Pass 'tampered transaction remains isolated'}else{Fail 'tampered transaction disappeared'}

    $s=New-TestBuild 'post-check-failure';$scenarios+=$s
    try { Commit-DistroShelfTrackTransaction -BuildResult $s.Build -TargetRoot (Join-Path $s.Root 'committed') -IntegrityCheck { param($d) $false }|Out-Null;Fail 'post-promotion integrity failure was accepted' } catch { Pass 'post-promotion integrity failure aborts commit' }
    $recovered=Join-Path $s.Root 'Track\payload.txt'
    if(Test-Path -LiteralPath $recovered){Pass 'post-promotion failure recovers full Track tree'}else{Fail 'post-promotion failure lost Track tree'}
    $tr=@(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'DistroShelf\Troubleshoot') -Directory -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1)
    if($tr.Count){Pass 'post-promotion failure is routed to Troubleshoot'}else{Fail 'post-promotion failure did not reach Troubleshoot'}

    Write-Host "`nAll Track atomicity failure-injection tests passed."
}
finally {
    foreach($s in $scenarios){if(Test-Path -LiteralPath $s.Root){Remove-Item -LiteralPath $s.Root -Recurse -Force -ErrorAction SilentlyContinue}}
}
