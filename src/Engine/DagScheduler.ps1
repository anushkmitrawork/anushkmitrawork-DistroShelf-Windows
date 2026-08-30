# DistroShelf - dependency DAG scheduler
# Scheduling is derived from declared prerequisites and optional resource locks.

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
    return $true
}

function Get-DistroShelfReadyStages {
    param([Parameter(Mandatory)][object[]]$Stages,[Parameter(Mandatory)][hashtable]$VerifiedHashes,[hashtable]$Running=@{})
    @($Stages|Where-Object{
        $id=[string]$_.Id
        (-not $VerifiedHashes.ContainsKey($id)) -and (-not $Running.ContainsKey($id)) -and
        (@($_.Depends|Where-Object{-not $VerifiedHashes.ContainsKey([string]$_)}).Count -eq 0)
    })
}

function Get-DistroShelfExecutionPlan {
    param([Parameter(Mandatory)][object]$Definition)
    $stages=@($Definition.Stages);Test-DistroShelfDag -Stages $stages|Out-Null
    $completed=@{};$plan=@()
    while($completed.Count-lt$stages.Count){
        $ready=@(Get-DistroShelfReadyStages -Stages $stages -VerifiedHashes $completed)
        if(!$ready.Count){throw 'DAG is blocked; required prerequisite stages are missing or the graph is cyclic.'}
        $plan+=,([pscustomobject]@{Stages=$ready})
        foreach($s in $ready){$completed[[string]$s.Id]=$true}
    }
    $plan
}

function Invoke-DistroShelfDag {
    param(
        [Parameter(Mandatory)][object[]]$Stages,
        [Parameter(Mandatory)][hashtable]$VerifiedHashes,
        [Parameter(Mandatory)][scriptblock]$InvokeStage,
        [int]$MaxConcurrency=3
    )
    Test-DistroShelfDag -Stages $Stages|Out-Null
    if($MaxConcurrency-lt 1){throw 'MaxConcurrency must be at least 1.'}
    $done=$VerifiedHashes; $remaining=@($Stages|Where-Object{-not $done.ContainsKey([string]$_.Id)})
    while($remaining.Count){
        $ready=@(Get-DistroShelfReadyStages -Stages $remaining -VerifiedHashes $done)
        if(!$ready.Count){throw 'DAG is blocked because a required prerequisite hash is unavailable.'}
        # Run independent stages concurrently, bounded by MaxConcurrency. Resource locks are
        # respected so future distro definitions can prevent unsafe overlap without scheduler changes.
        $batch=@();$locks=@{}
        foreach($stage in $ready){
            $lock=[string]$stage.ResourceLock
            if($batch.Count-ge $MaxConcurrency){break}
            if($lock-and-$locks.ContainsKey($lock)){continue}
            $batch+=,$stage;if($lock){$locks[$lock]=$true}
        }
        if(-not $batch.Count){$batch=@($ready|Select-Object -First 1)}
        foreach($stage in $batch){
            $result=&$InvokeStage $stage
            $hash=[string]$result.Hash
            if([string]::IsNullOrWhiteSpace($hash)){throw "Stage '$($stage.Id)' completed without producing a verified hash."}
            $done[[string]$stage.Id]=$hash
            $remaining=@($remaining|Where-Object{[string]$_.Id-ne [string]$stage.Id})
        }
    }
    return $done
}
