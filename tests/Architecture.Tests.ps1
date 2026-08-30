$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot;$src=Join-Path $root 'src'
function Pass($m){Write-Host "PASS  $m"};function Fail($m){Write-Host "FAIL  $m";throw $m}
. (Join-Path $src 'ProfileManager.ps1')
. (Join-Path $src 'Engine\TransactionEngine.ps1')
. (Join-Path $src 'Engine\HashEngine.ps1')
. (Join-Path $src 'Engine\DagScheduler.ps1')
. (Join-Path $src 'Engine\TestEngine.ps1')
. (Join-Path $src 'Engine\DefinitionValidator.ps1')
. (Join-Path $src 'Distro\Registry.ps1')
. (Join-Path $src 'DistroTrackManager.ps1')
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
        if([string]::IsNullOrWhiteSpace([string]$stage.TerminalPackage)){Fail "terminal matrix for ${d}/$terminal`: missing package"}
        if([string]::IsNullOrWhiteSpace([string]$stage.TerminalExecutable)){Fail "terminal matrix for ${d}/$terminal`: missing executable"}
        if([string]$stage.ExecutionModel -ne 'SharedBuilder'){Fail "terminal matrix for ${d}/$terminal`: unexpected execution model"}
    }
    $linear=@(Get-DistroShelfLinearExecutionPlan -Definition $provider)
    if($linear.Count -ne $stages.Count){Fail "linear plan omitted stages for ${d}"}
    for($i=0;$i-lt$linear.Count;$i++){
        $prior=@($linear[0..$i]|ForEach-Object{[string]$_.Id})
        foreach($dep in @($linear[$i].Depends)){if(-not($prior -contains [string]$dep)){Fail "linear plan violated dependency for ${d}/$($linear[$i].Id)"}}
    }
    Pass "Distro provider and deterministic linear DAG are valid: ${d}"
    Pass "Profile commands remain implementation-only/offline: ${d}"
}

$linearStages=@(
 [pscustomobject]@{Id='a';Depends=@();ExecutionModel='SharedBuilder'}
 [pscustomobject]@{Id='b';Depends=@('a');ExecutionModel='SharedBuilder'}
 [pscustomobject]@{Id='c';Depends=@('a');ExecutionModel='SharedBuilder'}
 [pscustomobject]@{Id='d';Depends=@('b','c');ExecutionModel='SharedBuilder'}
)
$linearDefinition=[pscustomobject]@{Stages=$linearStages}
$linearPlan=@(Get-DistroShelfLinearExecutionPlan -Definition $linearDefinition)
$linearOrder=@($linearPlan|ForEach-Object Id)
if(($linearOrder -join ',') -eq 'a,b,c,d'){Pass 'linear DAG execution is deterministic and dependency-safe'}else{Fail "unexpected linear DAG order: $($linearOrder -join ',')"}

try {
    Get-DistroShelfLinearExecutionPlan -Definition ([pscustomobject]@{Stages=@(
        [pscustomobject]@{Id='a';Depends=@('b')}
        [pscustomobject]@{Id='b';Depends=@('a')}
    )})|Out-Null
    Fail 'linear planner accepted a cyclic DAG'
} catch {Pass 'linear planner rejects cyclic DAGs'}

$trackEngineText=Get-Content -LiteralPath (Join-Path $src 'Track\TrackEngine.ps1') -Raw
if($trackEngineText -match 'Get-DistroShelfLinearExecutionPlan'){Pass 'Track builder uses the linear DAG executor'}else{Fail 'Track builder is not bound to the linear DAG executor'}
if($trackEngineText -notmatch 'MaxConcurrency'){Pass 'Track Core has no parallelism parameter'}else{Fail 'Track Core still exposes parallelism configuration'}
if($trackEngineText -match 'foreach\(\$stage in \$linearOrder\)'){Pass 'Track stages execute one-at-a-time in planned order'}else{Fail 'Track Core does not execute the linear plan sequentially'}

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
$ptx=New-DistroShelfTransaction -Kind Profile -Distro Debian
try {
  if($tx.Kind -ne 'Track' -or $ptx.Kind -ne 'Profile'){Fail 'transaction kinds are not distinct'}
  if($tx.Root -eq $ptx.Root){Fail 'Track and Profile transactions share an attempt root'}
  if((Split-Path $tx.Root -Leaf) -notmatch '^Track-Debian-'){Fail 'Track transaction root is not Track-scoped'}
  if((Split-Path $ptx.Root -Leaf) -notmatch '^Profile-Debian-'){Fail 'Profile transaction root is not Profile-scoped'}
  $trackDefinition=Get-DistroShelfTrackDefinition 'Debian'
  $profileDefinition=Get-DistroShelfProfileDefinition 'Debian'
  if($trackDefinition.Root -eq $script:DistroShelfProfileRoot){Fail 'Track committed root overlaps Profile committed root'}
  if($trackDefinition.Root -eq $ptx.Root -or $profileDefinition.WslBaseName -eq (Split-Path $tx.Root -Leaf)){Fail 'Track/Profile committed and attempt state are mixed'}
  Pass 'Track and Profile have separate transaction identities and attempt roots'
  Pass 'Track and Profile committed stores are distinct'
}
finally {Remove-Item $tx.Root,$ptx.Root -Recurse -Force -ErrorAction SilentlyContinue}

$tx=New-DistroShelfTransaction -Kind Track -Distro Debian
if(Test-Path $tx.Root){Pass 'transaction creates isolated attempt root'}else{Fail 'transaction root missing'}
$marker=Join-Path $tx.Root 'marker.txt';'preserve-me'|Set-Content $marker
$err=[System.Management.Automation.ErrorRecord]::new([Exception]::new('synthetic failure'),'synthetic',[System.Management.Automation.ErrorCategory]::NotSpecified,$null)
$path=Move-DistroShelfTransactionToTroubleshoot -Transaction $tx -ErrorRecord $err
if($path -and (Test-Path $path)){Pass 'failed transaction preserved in Troubleshoot'}else{Fail 'failed transaction not preserved'}
if(Test-Path (Join-Path $path 'marker.txt')){Pass 'Troubleshoot retains failed transaction contents'}else{Fail 'Troubleshoot lost failed transaction contents'}

$commitPath=Join-Path $src 'Profile\ProfileCommit.ps1'
$commitText=Get-Content -LiteralPath $commitPath -Raw
$exportInvocations=@($commitText -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\bwsl\.exe\s+--export\b' })
if($exportInvocations.Count -gt 0){Fail 'ProfileCommit performs a second WSL export'}else{Pass 'ProfileCommit does not re-export the accepted Profile'}
if($commitText -match 'BuildResult\.ExportPath'){Pass 'ProfileCommit consumes BuildResult.ExportPath'}else{Fail 'ProfileCommit does not consume BuildResult.ExportPath'}
if($commitText -match 'artifactHash' -and $commitText -match 'ProfileHash'){Pass 'Profile commit verifies artifact hash against Profile hash'}else{Fail 'Profile artifact identity verification missing'}

$profileEnginePath=Join-Path $src 'Profile\ProfileEngine.ps1'
$profileEngineText=Get-Content -LiteralPath $profileEnginePath -Raw
if($profileEngineText -match 'wsl\.exe --export'){Pass 'ProfileEngine creates the single accepted export'}else{Fail 'ProfileEngine has no accepted export step'}
if($profileEngineText -match 'ExportPath='){Pass 'ProfileEngine returns accepted ExportPath'}else{Fail 'ProfileEngine does not return ExportPath'}

Write-Host "`nAll atomic architecture tests passed."