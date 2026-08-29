$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot;$src=Join-Path $root 'src'
function Pass($m){Write-Host "PASS  $m"};function Fail($m){Write-Host "FAIL  $m";throw $m}

. (Join-Path $src 'ProfileManager.ps1')
. (Join-Path $src 'Engine\TransactionEngine.ps1')
. (Join-Path $src 'Engine\HashEngine.ps1')
. (Join-Path $src 'Engine\DagScheduler.ps1')
. (Join-Path $src 'Engine\TestEngine.ps1')
. (Join-Path $src 'Distro\DistroDefinitions.ps1')

foreach($d in @('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')){
    $def=Get-DistroShelfDistroDefinition $d
    if($def.Track.Stages.Count -lt 1){Fail "no Track stages for $d"}
    $ids=@($def.Track.Stages|ForEach-Object Id)
    if(($ids|Select-Object -Unique).Count-ne$ids.Count){Fail "duplicate Track stage IDs for $d"}
    Resolve-DistroShelfStageOrder @($def.Track.Stages)|Out-Null
    Pass "Track graph valid: $d"
}

$stages=@(
 [pscustomobject]@{Id='a';Requires=@();Acquire=@();ProfileInstall=@();Tests=@()}
 [pscustomobject]@{Id='b';Requires=@('a');Acquire=@();ProfileInstall=@();Tests=@()}
 [pscustomobject]@{Id='c';Requires=@('a');Acquire=@();ProfileInstall=@();Tests=@()}
 [pscustomobject]@{Id='d';Requires=@('b','c');Acquire=@();ProfileInstall=@();Tests=@()}
)
$order=@(Resolve-DistroShelfStageOrder $stages)
if($order.IndexOf('a') -lt $order.IndexOf('b') -and $order.IndexOf('a') -lt $order.IndexOf('c') -and $order.IndexOf('b') -lt $order.IndexOf('d') -and $order.IndexOf('c') -lt $order.IndexOf('d')){Pass 'DAG ordering respects prerequisites'}else{Fail 'DAG ordering invalid'}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('DistroShelf-AtomicTest-'+[guid]::NewGuid());New-Item -ItemType Directory -Path $temp -Force|Out-Null
try{
  $f=Join-Path $temp 'artifact.txt';'hello'|Set-Content $f
  $h=Get-DistroShelfTreeHash $temp
  if([string]::IsNullOrWhiteSpace($h) -or $h.Length -ne 64){Fail 'tree hash was not SHA-256'}else{Pass 'deterministic tree hash produced'}
  $record=Join-Path $temp 'metadata\stage.hash.json';Write-DistroShelfHashRecord -Path $record -Stage 'stage' -Hash $h -TestResult ([pscustomobject]@{Passed=$true})|Out-Null
  if(Test-DistroShelfHashRecord -Path $record -Root $temp -Stage 'stage'){Pass 'hash record verifies'}else{Fail 'hash record did not verify'}
  'tamper'|Set-Content $f
  if(-not(Test-DistroShelfHashRecord -Path $record -Root $temp -Stage 'stage')){Pass 'tampering invalidates hash'}else{Fail 'tampering did not invalidate hash'}
}
finally{Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue}

$tx=New-DistroShelfTransaction -Kind Track -Distro Debian
if(Test-Path $tx.Root){Pass 'transaction creates isolated attempt root'}else{Fail 'transaction root missing'}
$err=[System.Management.Automation.ErrorRecord]::new([Exception]::new('synthetic failure'),'synthetic',[System.Management.Automation.ErrorCategory]::NotSpecified,$null)
$path=Move-DistroShelfTransactionToTroubleshoot -Transaction $tx -ErrorRecord $err
if($path -and (Test-Path $path)){Pass 'failed transaction preserved in Troubleshoot'}else{Fail 'failed transaction not preserved'}

Write-Host "`nAll atomic architecture tests passed."
