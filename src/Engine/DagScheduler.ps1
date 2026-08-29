# DistroShelf - dependency graph scheduler
# Scheduling is derived from declared prerequisites and runtime locks.

function Test-DistroShelfGraph {
    param([Parameter(Mandatory)][object[]]$Stages)
    $ids=@($Stages|ForEach-Object {[string]$_.Id})
    if(($ids|Select-Object -Unique).Count -ne $ids.Count){throw 'Duplicate stage IDs detected.'}
    foreach($s in @($Stages)){foreach($r in @($s.Requires)){if($r -notin $ids){throw "Stage '$($s.Id)' requires unknown stage '$r'."}}}
    # Kahn cycle check
    $remaining=@{};foreach($s in @($Stages)){$remaining[[string]$s.Id]=@($s.Requires).Count}
    $queue=New-Object System.Collections.Generic.Queue[string];foreach($s in @($Stages)){if($remaining[[string]$s.Id]-eq 0){$queue.Enqueue([string]$s.Id)}}
    $seen=0
    while($queue.Count){$id=$queue.Dequeue();$seen++;foreach($s in @($Stages)){if($id -in @($s.Requires)){ $remaining[[string]$s.Id]--;if($remaining[[string]$s.Id]-eq 0){$queue.Enqueue([string]$s.Id)}}}}
    if($seen -ne $ids.Count){throw 'Dependency graph contains a cycle.'}
    return $true
}

function Get-DistroShelfEligibleStages {
    param([Parameter(Mandatory)][object[]]$Stages,[Parameter(Mandatory)][hashtable]$Completed,[hashtable]$Running=@{},[hashtable]$Locks=@{})
    $eligible=@()
    foreach($s in @($Stages)){
        $id=[string]$s.Id
        if($Completed.ContainsKey($id) -or $Running.ContainsKey($id)){continue}
        $ready=$true
        foreach($r in @($s.Requires)){if(-not $Completed.ContainsKey([string]$r)){$ready=$false;break}}
        if(!$ready){continue}
        if($s.ExclusiveGroup -and $Locks.ContainsKey([string]$s.ExclusiveGroup)){continue}
        $eligible+=$s
    }
    return @($eligible)
}

function Invoke-DistroShelfGraphPlan {
    param([Parameter(Mandatory)][object[]]$Stages,[scriptblock]$OnBatch)
    Test-DistroShelfGraph -Stages $Stages | Out-Null
    $completed=@{};$running=@{};$locks=@{};$batches=@()
    while($completed.Count -lt @($Stages).Count){
        $batch=@(Get-DistroShelfEligibleStages -Stages $Stages -Completed $completed -Running $running -Locks $locks)
        if(!$batch.Count){if($running.Count){break};throw 'Dependency graph is blocked: no eligible stage remains.'}
        $batches+=,@($batch)
        foreach($s in $batch){$completed[[string]$s.Id]=$true}
        if($OnBatch){& $OnBatch @($batch)}
    }
    return @($batches)
}
