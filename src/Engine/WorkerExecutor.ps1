# DistroShelf - bounded worker executor
# Runs an already-selected batch concurrently. Dependency eligibility is owned by DagScheduler.

function Invoke-DistroShelfWorkerBatch {
    param(
        [Parameter(Mandatory)][object[]]$Stages,
        [Parameter(Mandatory)][scriptblock]$Worker,
        [int]$MaxConcurrency=3
    )
    if($MaxConcurrency -lt 1){throw 'MaxConcurrency must be at least 1.'}
    $active=@();$results=@();$queue=[System.Collections.Generic.Queue[object]]::new()
    foreach($s in @($Stages)){$queue.Enqueue($s)}
    while($queue.Count -or $active.Count){
        while($queue.Count -and $active.Count -lt $MaxConcurrency){
            $stage=$queue.Dequeue()
            $ps=[powershell]::Create()
            [void]$ps.AddScript({param($worker,$stage)& $worker $stage}).AddArgument($Worker).AddArgument($stage)
            $active+=[pscustomobject]@{PowerShell=$ps;AsyncResult=$ps.BeginInvoke();Stage=$stage}
        }
        $completed=@($active|Where-Object{$_.AsyncResult.IsCompleted})
        if(!$completed.Count){Start-Sleep -Milliseconds 100;continue}
        foreach($job in $completed){
            try{$value=$job.PowerShell.EndInvoke($job.AsyncResult);$results+=[pscustomobject]@{Stage=$job.Stage;Success=$true;Result=@($value)}}catch{$results+=[pscustomobject]@{Stage=$job.Stage;Success=$false;Error=$_.Exception.Message};throw}finally{$job.PowerShell.Dispose()}
            $active=@($active|Where-Object{$_ -ne $job})
        }
    }
    return $results
}
