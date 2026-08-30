$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'src'
. (Join-Path $src 'Engine\DagScheduler.ps1')

function Pass($m){Write-Host "PASS  $m"}
function Fail($m){throw "FAIL  $m"}

$a=[pscustomobject]@{Id='a';Depends=@();ExecutionModel='SharedBuilder';Kind='dependency';PackageManager='apt';Track=[pscustomobject]@{ExportType='apt-cache'}}
$b=[pscustomobject]@{Id='b';Depends=@('a');ExecutionModel='SharedBuilder';Kind='dependency';PackageManager='apt';Track=[pscustomobject]@{ExportType='apt-cache'}}
$c=[pscustomobject]@{Id='c';Depends=@('b');ExecutionModel='SharedBuilder';Kind='dependency';PackageManager='apt';Track=[pscustomobject]@{ExportType='apt-cache'}}
$stages=@($a,$b,$c)

# Runtime readiness must follow verified hashes, not planned stages.
$verified=@{}
$ready=@(Get-DistroShelfReadyStages -Stages $stages -VerifiedHashes $verified)
if($ready.Count -eq 1 -and $ready[0].Id -eq 'a'){Pass 'runtime starts only at hash-free root stage'}else{Fail 'runtime readiness incorrectly bypassed missing predecessor hash'}

$verified['a']='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$ready=@(Get-DistroShelfReadyStages -Stages $stages -VerifiedHashes $verified)
if($ready.Count -eq 1 -and $ready[0].Id -eq 'b'){Pass 'next stage unlocks only after predecessor verification'}else{Fail 'next stage did not require verified predecessor hash'}

$plan=@(Get-DistroShelfExecutionPlan -Definition ([pscustomobject]@{Stages=$stages}))
if(@($plan|ForEach-Object Id) -join ',' -eq 'a,b,c'){Pass 'planning order remains independent from runtime verification'}else{Fail 'planning order changed unexpectedly'}

# With a real transaction root, a dependency hash record is mandatory.
$temp=Join-Path ([IO.Path]::GetTempPath()) ('DistroShelf-UbuntuExec-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path (Join-Path $temp 'metadata'),(Join-Path $temp 'a') -Force|Out-Null
try {
    'artifact'|Set-Content (Join-Path $temp 'a\payload.txt')
    $hash=Get-DistroShelfTreeHash -Root (Join-Path $temp 'a')
    . (Join-Path $src 'Engine\HashEngine.ps1')
    Write-DistroShelfHashRecord -Path (Join-Path $temp 'metadata\a.hash.json') -Stage 'a' -Hash $hash -TestResult ([pscustomobject]@{Passed=$true})|Out-Null
    $verified=@{'a'=$hash}
    $ready=@(Get-DistroShelfReadyStages -Stages @($b) -VerifiedHashes $verified -HashRoot $temp)
    if($ready.Count -eq 1 -and $ready[0].Id -eq 'b'){Pass 'runtime accepts predecessor only with persisted valid hash'}else{Fail 'persisted valid hash did not unlock next stage'}
    'tampered'|Set-Content (Join-Path $temp 'a\payload.txt')
    $ready=@(Get-DistroShelfReadyStages -Stages @($b) -VerifiedHashes $verified -HashRoot $temp)
    if($ready.Count -eq 0){Pass 'tampering immediately re-locks dependent stage'}else{Fail 'tampered predecessor hash still unlocked dependent stage'}
} finally {Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue}

Write-Host "`nUbuntu execution-boundary tests passed."
