# DistroShelf - transactional Track builder
. (Join-Path $PSScriptRoot '..\Engine\TransactionEngine.ps1')
. (Join-Path $PSScriptRoot '..\Engine\DagScheduler.ps1')
. (Join-Path $PSScriptRoot '..\Engine\HashEngine.ps1')
. (Join-Path $PSScriptRoot '..\Engine\AcceptanceEngine.ps1')
. (Join-Path $PSScriptRoot '..\Distro\DistroDefinitions.ps1')
. (Join-Path $PSScriptRoot '..\RootfsProvider.ps1')
. (Join-Path $PSScriptRoot '..\WslImporter.ps1')

function Invoke-DistroShelfTrackBuilder {
    param([Parameter(Mandatory)][string]$Distro,[scriptblock]$OnProgress)
    $definition=Get-DistroShelfDistroDefinition -Distro $Distro
    $tx=New-DistroShelfTransaction -Kind Track -Distro $Distro
    $trackRoot=Join-Path $tx.Root 'Track'
    New-Item -ItemType Directory -Path $trackRoot,(Join-Path $trackRoot 'Distro'),(Join-Path $trackRoot 'metadata'),(Join-Path $trackRoot 'Terminals') -Force|Out-Null
    $emit={param($pct,$msg)if($OnProgress){&$OnProgress $pct $msg}}
    try {
        & $emit 5 "Acquiring $Distro root filesystem..."
        # RootfsProvider MUST honor the explicit destination so this transaction cannot touch committed Track 0.
        $rootfs=Save-DistroShelfRootfs -Distro $Distro -DestinationDirectory (Join-Path $trackRoot 'Distro')
        $rootfsTests=Invoke-DistroShelfTrackAcceptance -WslName '' -Tests @() 2>$null
        # The WSL rootfs is validated by the importer/functional stages below. Do not create a rootfs hash until that validation succeeds.
        $builderName="DistroShelf-TrackBuild-$($tx.Id)"
        & $emit 15 "Preparing isolated $Distro Track builder..."
        $candidate=[pscustomobject]@{Id=$tx.Id;WslName=$builderName;Distro=$Distro;Name="$Distro-TrackBuilder"}
        $imp=Invoke-DistroShelfWslImport -Profile $candidate -RootfsPath $rootfs.Path -ExpectedSha256 $rootfs.Sha256 -StorageRoot (Join-Path $tx.Root 'Wsl')

        $stages=@($definition.Stages)
        Test-DistroShelfDag -Stages $stages|Out-Null
        $verified=@{}
        $stageResults=@()
        $total=$stages.Count
        while($verified.Count -lt $total){
            $ready=@(Get-DistroShelfReadyStages -Stages $stages -VerifiedHashes $verified)
            if(!$ready.Count){throw 'Track DAG is blocked: a required prerequisite hash is missing.'}
            foreach($stage in $ready){
                $id=[string]$stage.Id
                $stageRoot=Join-Path $trackRoot ($id -replace ':','-')
                New-Item -ItemType Directory -Path $stageRoot -Force|Out-Null
                & $emit (20 + [int](60*$verified.Count/$total)) "Running Track stage '$id'..."

                $acquire=@()
                $tests=@()
                if($stage.Track){$acquire=@($stage.Track.Acquire);$tests=@($stage.Track.Tests)}
                if([string]$stage.Kind -ne 'rootfs' -and $acquire.Count -eq 0 -and $tests.Count -eq 0){throw "Track stage '$id' has no implementation contract. Add Track.Acquire and Track.Tests for '$Distro'."}

                foreach($cmd in $acquire){
                    if([string]::IsNullOrWhiteSpace([string]$cmd)){continue}
                    $r=Invoke-DistroShelfCommand -WslName $builderName -Command ([string]$cmd) -CaptureOutput
                    if($r.ExitCode-ne 0){throw "Track stage '$id' acquisition failed: $cmd`n$($r.Output)"}
                }

                if($tests.Count -gt 0){$testResult=Invoke-DistroShelfStageTests -WslName $builderName -Tests $tests}else{$testResult=[pscustomobject]@{Passed=$true;Total=0;PassedCount=0;FailedCount=0;Results=@()}}
                if(-not $testResult.Passed){throw "Track stage '$id' failed verification."}

                $hash=Get-DistroShelfTreeHash -Root $stageRoot
                $hashPath=Join-Path (Join-Path $trackRoot 'metadata') "$($id -replace ':','-').hash.json"
                Write-DistroShelfHashRecord -Path $hashPath -Stage $id -Hash $hash -TestResult $testResult|Out-Null
                $verified[$id]=$hash
                $stageResults+=[pscustomobject]@{Id=$id;Hash=$hash;Tests=$testResult}
            }
        }

        & $emit 85 'Running final Track acceptance checks...'
        $finalTests=@()
        if($definition.TrackFinalTests){$finalTests=@($definition.TrackFinalTests)}
        if($finalTests.Count -eq 0){throw "No final Track acceptance test suite is defined for '$Distro'."}
        $final=Invoke-DistroShelfTrackAcceptance -WslName $builderName -Tests $finalTests
        $finalHash=Get-DistroShelfTreeHash -Root $trackRoot -ExcludeRelativePath @('metadata/track.hash.json','metadata/track.json')
        Write-DistroShelfHashRecord -Path (Join-Path (Join-Path $trackRoot 'metadata') 'track.hash.json') -Stage 'track' -Hash $finalHash -TestResult $final|Out-Null
        $manifest=[ordered]@{SchemaVersion=3;Distro=$Distro;Track=$definition.Track;FinalHash=$finalHash;Stages=$stageResults;CreatedAt=[DateTime]::UtcNow.ToString('o')}
        $manifest|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $trackRoot 'metadata\track.json') -Encoding UTF8
        & $emit 100 "Track $Distro verified; ready for atomic commit."
        return [pscustomobject][ordered]@{Success=$true;Transaction=$tx;TrackRoot=$trackRoot;FinalHash=$finalHash;Stages=$stageResults}
    } catch {
        $tr=Move-DistroShelfTransactionToTroubleshoot -Transaction $tx -ErrorRecord $_
        return [pscustomobject][ordered]@{Success=$false;Transaction=$tx;TroubleshootPath=$tr;Error=$_.Exception.Message}
    }
}
