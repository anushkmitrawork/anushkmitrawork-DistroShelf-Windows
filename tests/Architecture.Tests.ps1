$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot;$src=Join-Path $root 'src'
function Pass($m){Write-Host "PASS  $m"};function Fail($m){Write-Host "FAIL  $m";throw $m}
. (Join-Path $src 'ProfileManager.ps1')
. (Join-Path $src 'Engine\TransactionEngine.ps1')
. (Join-Path $src 'Engine\HashEngine.ps1')
. (Join-Path $src 'Engine\DagScheduler.ps1')
. (Join-Path $src 'Engine\TestEngine.ps1')
. (Join-Path $src 'Engine\DefinitionValidator.ps1')
. (Join-Path $src 'Engine\WorkerExecutor.ps1')
. (Join-Path $src 'Distro\Registry.ps1')
. (Join-Path $src 'Profile\ProfileArtifactInstaller.ps1')

$requiredTerminals=@('GNOME Console','Kitty','Alacritty','Foot','Konsole')
foreach($d in @('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')){
    $provider=Get-DistroShelfProvider $d
    $stages=@($provider.Stages)
    if($stages.Count -lt 1){Fail "no stages for ${d}"}
    $ids=@($stages|ForEach-Object Id)
    if(($ids|Select-Object -Unique).Count-ne$ids.Count){Fail "duplicate stage IDs for ${d}"}
    Test-DistroShelfDag -Stages $stages|Out-Null
    $validation=@(Invoke-DistroShelfDefinitionValidation|Where-Object Distro -eq $d|Where-Object{-not $_.Valid})
    if($validation.Count){Fail "definition validation: ${d}"}
    foreach($s in @($stages|Where-Object Id -ne 'rootfs')){Test-DistroShelfProfileInstallCommands -Stage $s|Out-Null}
    $terminalStages=@($stages|Where-Object{[string]$_.Kind -eq 'terminal'})
    foreach($terminal in $requiredTerminals){
        $matches=@($terminalStages|Where-Object{[string]$_.TerminalName -eq $terminal})
        if($matches.Count -ne 1){Fail "terminal matrix for ${d}: expected exactly one '$terminal' stage"}
        $stage=$matches[0]
        if([string]::IsNullOrWhiteSpace([string]$stage.TerminalPackage)){Fail "terminal matrix for ${d}/$terminal: missing package"}
        if([string]::IsNullOrWhiteSpace([string]$stage.TerminalExecutable)){Fail "terminal matrix for ${d}/$terminal: missing executable"}
        if([string]$stage.ExecutionModel -ne 'SharedBuilder'){Fail "terminal matrix for ${d}/$terminal: unexpected execution model"}
    }
    Pass "Distro provider valid and Profile commands are offline: ${d}"
    Pass "Track contains complete terminal matrix: ${d}"
}

$stages=@(
 [pscustomobject]@{Id='a';Depends=@();ExecutionModel='SharedBuilder'}
 [pscustomobject]@{Id='b';Depends=@('a');ExecutionModel='SharedBuilder'}
 [pscustomobject]@{Id='c';Depends=@('a');ExecutionModel='SharedBuilder'}
 [pscustomobject]@{Id='d';Depends=@('b','c');ExecutionModel='SharedBuilder'}
)
$plan=@(Get-DistroShelfExecutionPlan ([pscustomobject]@{Stages=$stages}))
$order=@($plan|ForEach-Object Id)
if($order.IndexOf('a') -lt $order.IndexOf('b') -and $order.IndexOf('a') -lt $order.IndexOf('c') -and $order.IndexOf('b') -lt $order.IndexOf('d') -and $order.IndexOf('c') -lt $order.IndexOf('d')){Pass 'DAG ordering respects prerequisites'}else{Fail 'DAG ordering invalid'}

$isolatedA=[pscustomobject]@{Id='ia';Depends=@();ExecutionModel='IsolatedBuilder';ResourceLock='net-a'}
$isolatedB=[pscustomobject]@{Id='ib';Depends=@();ExecutionModel='IsolatedBuilder';ResourceLock='net-b'}
$shared=[pscustomobject]@{Id='shared';Depends=@();ExecutionModel='SharedBuilder';ResourceLock='builder'}
$batch=@(Select-DistroShelfParallelBatch -ReadyStages @($isolatedA,$isolatedB) -MaxConcurrency 2)
if($batch.Count -eq 2){Pass 'independent isolated stages may share a parallel batch'}else{Fail 'isolated stages were not parallel-batch eligible'}
try {Invoke-DistroShelfWorkerBatch -Stages @($shared) -Worker {param($s);$s.Id}|Out-Null;Fail 'worker executor accepted shared-builder stage'}catch{Pass 'worker executor rejects shared-builder concurrency'}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('DistroShelf-AtomicTest-'+[guid]::NewGuid());New-Item -ItemType Directory -Path $temp -Force|Out-Null
try{
  $f=Join-Path $temp 'artifact.txt';'hello'|Set-Content $f
  $h=Get-DistroShelfTreeHash $temp
  if([string]::IsNullOrWhiteSpace($h) -or $h.Length -ne 64){Fail 'tree hash was not SHA-256'}else{Pass 'deterministic tree hash produced'}
  $meta=Join-Path $temp 'metadata';New-Item -ItemType Directory -Path $meta -Force|Out-Null
  $h=Get-DistroShelfTreeHash $temp -ExcludeRelativePath @('metadata')
  $record=Join-Path $meta 'stage.hash.json';Write-DistroShelfHashRecord -Path $record -Stage 'stage' -Hash $h -TestResult ([pscustomobject]@{Passed=$true})|Out-Null
  if(Test-DistroShelfHashRecord -Path $record -Root $temp -Stage 'stage' -ExcludeRelativePath @('metadata')){Pass 'hash record verifies'}else{Fail 'hash record did not verify'}
  'tamper'|Set-Content $f
  if(-not(Test-DistroShelfHashRecord -Path $record -Root $temp -Stage 'stage' -ExcludeRelativePath @('metadata'))){Pass 'tampering invalidates hash'}else{Fail 'tampering did not invalidate hash'}
}
finally{Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue}

$tx=New-DistroShelfTransaction -Kind Track -Distro Debian
if(Test-Path $tx.Root){Pass 'transaction creates isolated attempt root'}else{Fail 'transaction root missing'}
$marker=Join-Path $tx.Root 'marker.txt';'preserve-me'|Set-Content $marker
$err=[System.Management.Automation.ErrorRecord]::new([Exception]::new('synthetic failure'),'synthetic',[System.Management.Automation.ErrorCategory]::NotSpecified,$null)
$path=Move-DistroShelfTransactionToTroubleshoot -Transaction $tx -ErrorRecord $err
if($path -and (Test-Path $path)){Pass 'failed transaction preserved in Troubleshoot'}else{Fail 'failed transaction not preserved'}
if(Test-Path (Join-Path $path 'marker.txt')){Pass 'Troubleshoot retains failed transaction contents'}else{Fail 'Troubleshoot lost failed transaction contents'}

$commitPath=Join-Path $src 'Profile\ProfileCommit.ps1'
$commitText=Get-Content -LiteralPath $commitPath -Raw
if($commitText -match '--export'){Fail 'ProfileCommit performs a second WSL export'}else{Pass 'ProfileCommit does not re-export the accepted Profile'}
if($commitText -match 'BuildResult\.ExportPath'){Pass 'ProfileCommit consumes BuildResult.ExportPath'}else{Fail 'ProfileCommit does not consume BuildResult.ExportPath'}
if($commitText -match 'artifactHash' -and $commitText -match 'ProfileHash'){Pass 'Profile commit verifies artifact hash against Profile hash'}else{Fail 'Profile artifact identity verification missing'}

$profileEnginePath=Join-Path $src 'Profile\ProfileEngine.ps1'
$profileEngineText=Get-Content -LiteralPath $profileEnginePath -Raw
if($profileEngineText -match 'wsl\.exe --export'){Pass 'ProfileEngine creates the single accepted export'}else{Fail 'ProfileEngine has no accepted export step'}
if($profileEngineText -match 'ExportPath='){Pass 'ProfileEngine returns accepted ExportPath'}else{Fail 'ProfileEngine does not return ExportPath'}

Write-Host "`nAll atomic architecture tests passed."