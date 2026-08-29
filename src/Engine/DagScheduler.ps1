# DistroShelf - dependency DAG scheduler

function Get-DistroShelfReadyStages {
    param(
        [Parameter(Mandatory)][object[]]$Stages,
        [Parameter(Mandatory)][hashtable]$VerifiedHashes
    )
    $ready = @()
    foreach ($stage in @($Stages)) {
        if ($VerifiedHashes.ContainsKey([string]$stage.Id)) { continue }
        $deps = @($stage.Depends)
        if (@($deps | Where-Object { -not $VerifiedHashes.ContainsKey([string]$_) }).Count -eq 0) { $ready += $stage }
    }
    return $ready
}

function Test-DistroShelfDag {
    param([Parameter(Mandatory)][object[]]$Stages)
    $ids = @{}
    foreach($s in $Stages){
        $id=[string]$s.Id
        if([string]::IsNullOrWhiteSpace($id)){throw 'Every stage requires an Id.'}
        if($ids.ContainsKey($id)){throw "Duplicate stage Id: $id"}
        $ids[$id]=$true
    }
    foreach($s in $Stages){ foreach($d in @($s.Depends)){if(-not $ids.ContainsKey([string]$d)){throw "Stage '$($s.Id)' depends on unknown stage '$d'."};if([string]$d -eq [string]$s.Id){throw "Stage '$($s.Id)' cannot depend on itself."}} }
    # Kahn cycle check
    $remaining=@{}; foreach($s in $Stages){$remaining[[string]$s.Id]=@($s.Depends).Count}
    $queue=[System.Collections.Generic.Queue[string]]::new(); foreach($k in $remaining.Keys){if($remaining[$k]-eq 0){$queue.Enqueue($k)}}
    $count=0
    while($queue.Count){$n=$queue.Dequeue();$count++;foreach($s in $Stages){if(@($s.Depends)-contains $n){$remaining[[string]$s.Id]--;if($remaining[[string]$s.Id]-eq 0){$queue.Enqueue([string]$s.Id)}}}}
    if($count-ne $Stages.Count){throw 'Distro dependency graph contains a cycle.'}
    return $true
}

function Get-DistroShelfExecutionPlan {
    param([Parameter(Mandatory)][object]$Definition)
    $stages=@($Definition.Stages); Test-DistroShelfDag -Stages $stages | Out-Null
    $verified=@{}; $plan=@()
    while($verified.Count -lt $stages.Count){
        $ready=@(Get-DistroShelfReadyStages -Stages $stages -VerifiedHashes $verified)
        if(!$ready.Count){throw 'DAG is blocked; required stage hashes are missing or the graph is cyclic.'}
        foreach($s in $ready){$plan += ,([pscustomobject]@{Id=$s.Id;Depends=@($s.Depends);ParallelGroup=[string]$s.ParallelGroup;Kind=[string]$s.Kind});$verified[[string]$s.Id]=$true}
    }
    return $plan
}
