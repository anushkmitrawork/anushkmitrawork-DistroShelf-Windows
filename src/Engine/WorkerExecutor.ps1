# DistroShelf - bounded worker executor
# Runs an already-selected batch concurrently. Dependency eligibility is owned by DagScheduler.
# A concurrent worker must be explicitly marked IsolatedBuilder; shared mutable builders stay serial.

function Invoke-DistroShelfWorkerBatch {
    param(
        [Parameter(Mandatory)][object[]]$Stages,
        [Parameter(Mandatory)][scriptblock]$Worker,
        [int]$MaxConcurrency=3,
        [switch]$AllowSharedBuilder
    )
    if($MaxConcurrency -lt 1){throw 'MaxConcurrency must be at least 1.'}
    if(-not $AllowSharedBuilder){
        $unsafe=@($Stages|Where-Object{[string]$_.ExecutionModel -ne 'IsolatedBuilder'})
        if($unsafe.Count){throw "Worker concurrency refused for shared-builder stage(s): $(@($unsafe|ForEach-Object{[string]$_.Id}) -join ', '). Declare IsolatedBuilder only when the stage owns an independent execution environment."}
    }
    $active=@();$results=@();$queue=[System.Collections.Generic.Queue[object]]::new();$firstError=$null
    foreach($s in @($Stages)){$queue.Enqueue($s)}
    try {
        while($queue.Count -or $active.Count){
            while($queue.Count -and $active.Count -lt $MaxConcurrency){
                $stage=$queue.Dequeue()
                $ps=[powershell]::Create()
                [void]$ps.AddScript({param($worker,$stage)& $worker $stage}).AddArgument($Worker).AddArgument($stage)
                $active+=[pscustomobject]@{PowerShell=$ps;AsyncResult=$ps.BeginInvoke();Stage=$stage}
            }
            $completed=@($active|Where-Object{$_.AsyncResult.IsCompleted})
            if(!$completed.Count){Start-Sleep -Milliseconds 75;continue}
            foreach($job in $completed){
                try{$value=$job.PowerShell.EndInvoke($job.AsyncResult);$results+=[pscustomobject]@{Stage=$job.Stage;Success=$true;Result=@($value)}}
                catch{$results+=[pscustomobject]@{Stage=$job.Stage;Success=$false;Error=$_.Exception.Message};if(-not $firstError){$firstError=$_.Exception}}
                finally{$job.PowerShell.Dispose();$active=@($active|Where-Object{$_ -ne $job})}
            }
            if($firstError){
                foreach($job in @($active)){try{$job.PowerShell.Stop()}catch{};try{$job.PowerShell.Dispose()}catch{}}
                $active=@()
                while($queue.Count){$unstarted=$queue.Dequeue();$results+=[pscustomobject]@{Stage=$unstarted;Success=$false;Skipped=$true;Error='Skipped because another stage failed in the same batch.'}}
            }
        }
    } finally {foreach($job in @($active)){try{$job.PowerShell.Stop()}catch{};try{$job.PowerShell.Dispose()}catch{}}}
    if($firstError){throw $firstError}
    return $results
}
