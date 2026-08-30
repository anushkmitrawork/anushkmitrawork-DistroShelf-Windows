$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot;$src=Join-Path $root 'src'
function Pass($m){Write-Host "PASS  $m"};function Fail($m){Write-Host "FAIL  $m";throw $m}

. (Join-Path $src 'ProfileManager.ps1')
. (Join-Path $src 'Engine\TransactionEngine.ps1')
. (Join-Path $src 'Engine\HashEngine.ps1')
. (Join-Path $src 'Engine\DagScheduler.ps1')
. (Join-Path $src 'Engine\TestEngine.ps1')
. (Join-Path $src 'Engine\DefinitionValidator.ps1')
. (Join-Path $src 'Distro\DistroDefinitions.ps1')

foreach($d in @('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')){
    $def=Get-DistroShelfDistroDefinition $d;$stages=@($def.Stages)
    if($stages.Count -lt 1){Fail "no stages for $d"}
    $ids=@($stages|ForEach-Object Id)
    if(($ids|Select-Object -Unique).Count-ne$ids.Count){Fail "duplicate stage IDs for $d"}
    Test-DistroShelfDag -Stages $stages|Out-Null
    $validation=@(foreach($s in $stages){Test-DistroShelfStageContract -Stage $s -Distro $d})
    if(@($validation|Where-Object{-not $_.Valid}).Count){Fail "invalid implementation contract for $d"}
    if(!$def.TrackFinalTests.Count){Fail "missing Track final tests for $d"}
    if(!$def.ProfileFinalTests.Count){Fail "missing Profile final tests for $d"}
    Pass "Distro definition valid: $d"
}

$stages=@(
 [pscustomobject]@{Id='a';Depends=@();PackageManager='x';Kind='dependency'}
 [pscustomobject]@{Id='b';Depends=@('a');PackageManager='x';Kind='dependency'}
 [pscustomobject]@{Id='c';Depends=@('a');PackageManager='y';Kind='dependency'}
 [pscustomobject]@{Id='d';Depends=@('b','c');PackageManager='z';Kind='dependency'}
)
$plan=@(Get-DistroShelfExecutionPlan ([pscustomobject]@{Stages=$stages}))
$order=@($plan|ForEach-Object Id)
if($order.IndexOf('a') -lt $order.IndexOf('b') -and $order.IndexOf('a') -lt $order.IndexOf('c') -and $order.IndexOf('b') -lt $order.IndexOf('d') -and $order.IndexOf('c') -lt $order.IndexOf('d')){Pass 'DAG ordering respects prerequisites'}else{Fail 'DAG ordering invalid'}
$batch=@(Select-DistroShelfParallelBatch -ReadyStages @($stages[1],$stages[2]) -MaxConcurrency 3)
if($batch.Count -eq 2){Pass 'independent resource locks permit parallel batch'}else{Fail 'independent resource locks blocked safe parallelism'}
$locked=@(Select-DistroShelfParallelBatch -ReadyStages @([pscustomobject]@{Id='x';PackageManager='apt';Kind='dependency'},[pscustomobject]@{Id='y';PackageManager='apt';Kind='dependency'}) -MaxConcurrency 3)
if($locked.Count -eq 1){Pass 'shared package-manager lock prevents unsafe parallelism'}else{Fail 'shared package-manager lock failed'}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('DistroShelf-AtomicTest-'+[guid]::NewGuid());New-Item -ItemType Directory -Path $temp -Force|Out-Null
try{
  $f=Join-Path $temp 'artifact.txt';'hello'|Set-Content $f;$h=Get-DistroShelfTreeHash $temp
  if([string]::IsNullOrWhiteSpace($h) -or $h.Length -ne 64){Fail 'tree hash was not SHA-256'}else{Pass 'deterministic tree hash produced'}
  $meta=Join-Path $temp 'metadata';New-Item -ItemType Directory -Path $meta -Force|Out-Null;$h=Get-DistroShelfTreeHash $temp -ExcludeRelativePath @('metadata');$record=Join-Path $meta 'stage.hash.json';Write-DistroShelfHashRecord -Path $record -Stage 'stage' -Hash $h -TestResult ([pscustomobject]@{Passed=$true})|Out-Null
  if(Test-DistroShelfHashRecord -Path $record -Root $temp -Stage 'stage' -ExcludeRelativePath @('metadata')){Pass 'hash record verifies'}else{Fail 'hash record did not verify'}
  'tamper'|Set-Content $f
  if(-not(Test-DistroShelfHashRecord -Path $record -Root $temp -Stage 'stage' -ExcludeRelativePath @('metadata'))){Pass 'tampering invalidates hash'}else{Fail 'tampering did not invalidate hash'}
} finally {Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue}

$tx=New-DistroShelfTransaction -Kind Track -Distro Debian
if(Test-Path $tx.Root){Pass 'transaction creates isolated attempt root'}else{Fail 'transaction root missing'}
$err=[System.Management.Automation.ErrorRecord]::new([Exception]::new('synthetic failure'),'synthetic',[System.Management.Automation.ErrorCategory]::NotSpecified,$null)
$path=Move-DistroShelfTransactionToTroubleshoot -Transaction $tx -ErrorRecord $err
if($path -and (Test-Path $path)){Pass 'failed transaction preserved in Troubleshoot'}else{Fail 'failed transaction not preserved'}

Write-Host "`nAll atomic architecture tests passed."