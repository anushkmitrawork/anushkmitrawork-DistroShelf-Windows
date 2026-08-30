# DistroShelf - dependency DAG scheduler
# Dependency eligibility is derived from hashes; resource locks prevent unsafe races.
# The scheduler NEVER marks work verified; only a successful executor may do that.

. (Join-Path $PSScriptRoot 'HashEngine.ps1')

function Test-DistroShelfDag {
    param([Parameter(Mandatory)][object[]]$Stages)
    $ids=@{}
    foreach($s in @($Stages)){
        $id=[string]$s.Id
        if([string]::IsNullOrWhiteSpace($id)){throw 'Every stage requires an Id.'}
        if($ids.ContainsKey($id)){throw "Duplicate stage Id: $id"}
        $ids[$id]=$true
    }
    foreach($s in @($Stages)){
        foreach($d in @($s.Depends)){
            if(-not $ids.ContainsKey([string]$d)){throw "Stage '$($s.Id)' depends on unknown stage '$d'."}
            if([string]$d -eq [string]$s.Id){throw "Stage '$($s.Id)' cannot depend on itself."}
        }
    }
    $remaining=@{};foreach($s in @($Stages)){$remaining[[string]$s.Id]=@($s.Depends).Count}
    $q=[System.Collections.Generic.Queue[string]]::new();foreach($k in @($remaining.Keys)){if($remaining[$k]-eq 0){$q.Enqueue($k)}}
    $count=0
    while($q.Count){$n=$q.Dequeue();$count++;foreach($s in @($Stages)){if(@($s.Depends)-contains $n){$remaining[[string]$s.Id]--;if($remaining[[string]$s.Id]-eq 0){$q.Enqueue([string]$s.Id)}}}}
    if($count-ne @($Stages).Count){throw 'Distro dependency graph contains a cycle.'}
    $true
}

function Get-DistroShelfStageResourceLock {
    param([Parameter(Mandatory)]$Stage)
    $explicit=[string]$Stage.ResourceLock;if($explicit){return $explicit}
    $id=[string]$Stage.Id;$kind=[string]$Stage.Kind;$manager=[string]$Stage.PackageManager
    if($kind -eq 'rootfs'){return 'wsl-rootfs'}
    if($id -eq 'flathub' -or [string]$Stage.Track.ExportType -eq 'flatpak-sideload'){return 'flatpak'}
    if($manager){return "package-manager:$manager"}
    $null
}

function Test-DistroShelfPersistedStageHash {
    param([Parameter(Mandatory)][object]$Stage,[Parameter(Mandatory)][string]$HashRoot)
    $id=[string]$Stage.Id
    $safe=$id -replace ':','-'
    $stageRoot=if($id -eq 'rootfs'){Join-Path $HashRoot 'Distro'}else{Join-Path $HashRoot $safe}
    $record=Join-Path (Join-Path $HashRoot 'metadata') "$safe.hash.json"
    if(-not(Test-Path -LiteralPath $stageRoot -PathType Container)){return $false}
    if(-not(Test-Path -LiteralPath $record -PathType Leaf)){return $false}
    try{return [bool](Test-DistroShelfHashRecord -Path $record -Root $stageRoot -Stage $id)}catch{return $false}
}

function Get-DistroShelfReadyStages {
    param([Parameter(Mandatory)][object[]]$Stages,[Parameter(Mandatory)][hashtable]$VerifiedHashes,[string]$HashRoot)
    @($Stages|Where-Object{
        $deps=@($_.Depends)
        $depsReady=($deps|Where-Object{
            $depId=[string]$_
            if(-not $VerifiedHashes.ContainsKey($depId)){return $false}
            if($HashRoot){
                $depStage=@($Stages|Where-Object{[string]$_.Id -eq $depId}|Select-Object -First 1)
                if($depStage -and -not(Test-DistroShelfPersistedStageHash -Stage $depStage -HashRoot $HashRoot)){return $false}
            }
            return $true
        }).Count -eq 0
        (-not $VerifiedHashes.ContainsKey([string]$_.Id)) -and $depsReady
    })
}

function Select-DistroShelfParallelBatch {
    param([Parameter(Mandatory)][object[]]$ReadyStages,[int]$MaxConcurrency=3)
    if($MaxConcurrency-lt 1){throw 'MaxConcurrency must be at least 1.'}
    $batch=@();$locks=@{}
    foreach($stage in @($ReadyStages)){
        if($batch.Count-ge $MaxConcurrency){break}
        if([string]$stage.ExecutionModel -eq 'SharedBuilder' -and $batch.Count){continue}
        $lock=Get-DistroShelfStageResourceLock -Stage $stage
        if($lock -and $locks.ContainsKey($lock)){continue}
        $batch+=,$stage;if($lock){$locks[$lock]=$true}
    }
    if(!$batch.Count){$batch=@($ReadyStages|Select-Object -First 1)}
    $batch
}

function Get-DistroShelfExecutionBatches {
    param([Parameter(Mandatory)][object]$Definition,[int]$MaxConcurrency=3)
    $stages=@($Definition.Stages);Test-DistroShelfDag $stages|Out-Null
    $completed=@{};$remaining=@($stages);$batches=@()
    while($remaining.Count){
        $ready=@(Get-DistroShelfReadyStages -Stages $remaining -VerifiedHashes $completed)
        if(!$ready.Count){throw 'DAG is blocked because required prerequisite hashes cannot be satisfied.'}
        $batch=@(Select-DistroShelfParallelBatch $ready $MaxConcurrency);$batches+=,[object[]]$batch
        foreach($stage in $batch){$completed[[string]$stage.Id]='PLANNED'}
        $remaining=@($remaining|Where-Object{[string]$batch.Id -notcontains [string]$_.Id})
    }
    $batches
}

function Get-DistroShelfExecutionPlan {
    param([Parameter(Mandatory)][object]$Definition,[int]$MaxConcurrency=3)
    $batches=Get-DistroShelfExecutionBatches -Definition $Definition -MaxConcurrency $MaxConcurrency
    $plan=@();foreach($batch in $batches){foreach($stage in @($batch)){$plan+=$stage}};return $plan
}
