# DistroShelf - transactional Track builder
. (Join-Path $PSScriptRoot '..\Engine\TransactionEngine.ps1')
. (Join-Path $PSScriptRoot '..\Engine\DagScheduler.ps1')
. (Join-Path $PSScriptRoot '..\Engine\HashEngine.ps1')
. (Join-Path $PSScriptRoot '..\Engine\AcceptanceEngine.ps1')
. (Join-Path $PSScriptRoot '..\Distro\DistroDefinitions.ps1')
. (Join-Path $PSScriptRoot 'RootfsAcquisition.ps1')
. (Join-Path $PSScriptRoot '..\WslImporter.ps1')

function Invoke-DistroShelfTrackBuilder {
    param([Parameter(Mandatory)][string]$Distro,[scriptblock]$OnProgress)
    $definition=Get-DistroShelfDistroDefinition -Distro $Distro
    $tx=New-DistroShelfTransaction -Kind Track -Distro $Distro
    $trackRoot=Join-Path $tx.Root 'Track'
    $distroRoot=Join-Path $trackRoot 'Distro'
    New-Item -ItemType Directory -Path $trackRoot,$distroRoot,(Join-Path $trackRoot 'metadata'),(Join-Path $trackRoot 'Terminals') -Force|Out-Null
    $emit={param($pct,$msg)if($OnProgress){&$OnProgress $pct $msg}}
    try {
        & $emit 5 "Acquiring $Distro root filesystem..."
        $rootfs=Save-DistroShelfAttemptRootfs -Distro $Distro -DestinationDirectory $distroRoot
        if(-not $rootfs.Verified){throw "Root filesystem acquisition did not produce a verified artifact."}

        & $emit 15 "Importing isolated $Distro Track builder..."
        $builderName="DistroShelf-TrackBuild-$($tx.Id)"
        $candidate=[pscustomobject]@{Id=$tx.Id;WslName=$builderName;Distro=$Distro;Name="$Distro-TrackBuilder"}
        Invoke-DistroShelfWslImport -Profile $candidate -RootfsPath $rootfs.Path -ExpectedSha256 $rootfs.Sha256 -StorageRoot (Join-Path $tx.Root 'Wsl') | Out-Null

        $stages=@($definition.Stages)
        Test-DistroShelfDag -Stages $stages|Out-Null
        $verified=@{rootfs=$rootfs.Sha256}
        $stageResults=@([pscustomobject]@{Id='rootfs';Hash=$rootfs.Sha256;Tests=[pscustomobject]@{Passed=$true;Total=1;PassedCount=1;FailedCount=0;Results=@([pscustomobject]@{Name='rootfs-artifact';Passed=$true})}})
        $remaining=@($stages|Where-Object{[string]$_.Id-ne 'rootfs'})

        while($remaining.Count){
            $ready=@($remaining|Where-Object{ @($_.Depends|Where-Object{ -not $verified.ContainsKey([string]$_) }).Count -eq 0 })
            if(!$ready.Count){throw 'Track DAG is blocked: a required prerequisite hash is missing.'}
            foreach($stage in $ready){
                $id=[string]$stage.Id
                $stageRoot=Join-Path $trackRoot ($id -replace ':','-')
                New-Item -ItemType Directory -Path $stageRoot -Force|Out-Null
                & $emit (20 + [int](55*(($stages.Count-$remaining.Count)+1)/$stages.Count)) "Acquiring and testing Track stage '$id'..."
                if(-not $stage.Track){throw "Track stage '$id' has no implementation definition for '$Distro'."}
                $acquire=@($stage.Track.Acquire)
                $tests=@($stage.Track.Tests)
                if(!$tests.Count){throw "Track stage '$id' has no functional tests defined for '$Distro'."}
                foreach($cmd in $acquire){
                    if([string]::IsNullOrWhiteSpace([string]$cmd)){continue}
                    $r=Invoke-DistroShelfCommand -WslName $builderName -Command ([string]$cmd) -CaptureOutput
                    if($r.ExitCode-ne 0){throw "Track stage '$id' acquisition failed: $cmd`n$($r.Output)"}
                }
                $testResult=Invoke-DistroShelfStageTests -WslName $builderName -Tests $tests
                if(-not $testResult.Passed){throw "Track stage '$id' failed verification."}

                # The stage implementation is responsible for placing reproducible artifacts in its stage root.
                # Empty stage roots are rejected so a successful test cannot accidentally create a meaningless hash.
                if(@(Get-ChildItem -LiteralPath $stageRoot -Recurse -File -ErrorAction SilentlyContinue).Count -eq 0){throw "Track stage '$id' passed tests but produced no Track artifact."}
                $hash=Get-DistroShelfTreeHash -Root $stageRoot
                $hashPath=Join-Path (Join-Path $trackRoot 'metadata') "$($id -replace ':','-').hash.json"
                Write-DistroShelfHashRecord -Path $hashPath -Stage $id -Hash $hash -TestResult $testResult|Out-Null
                $verified[$id]=$hash
                $stageResults+=[pscustomobject]@{Id=$id;Hash=$hash;Tests=$testResult}
                $remaining=@($remaining|Where-Object{[string]$_.Id-ne $id})
            }
        }

        & $emit 85 'Running final Track acceptance tests...'
        $finalTests=@($definition.TrackFinalTests)
        if(!$finalTests.Count){throw "No final Track acceptance test suite is defined for '$Distro'."}
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
