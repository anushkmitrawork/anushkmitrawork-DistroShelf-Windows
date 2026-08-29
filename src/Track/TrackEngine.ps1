# DistroShelf - transactional Track builder
. (Join-Path $PSScriptRoot '..\Engine\TransactionEngine.ps1')
. (Join-Path $PSScriptRoot '..\Engine\DagScheduler.ps1')
. (Join-Path $PSScriptRoot '..\Engine\HashEngine.ps1')
. (Join-Path $PSScriptRoot '..\Engine\AcceptanceEngine.ps1')
. (Join-Path $PSScriptRoot '..\Distro\DistroDefinitions.ps1')
. (Join-Path $PSScriptRoot 'RootfsAcquisition.ps1')
. (Join-Path $PSScriptRoot '..\WslImporter.ps1')
. (Join-Path $PSScriptRoot '..\Engine\AtomicCommit.ps1')

function Invoke-DistroShelfTrackBuilder {
    param([Parameter(Mandatory)][string]$Distro,[scriptblock]$OnProgress)
    $definition=Get-DistroShelfDistroDefinition -Distro $Distro
    $tx=New-DistroShelfTransaction -Kind Track -Distro $Distro
    $trackRoot=Join-Path $tx.Root 'Track';$distroRoot=Join-Path $trackRoot 'Distro'
    New-Item -ItemType Directory -Path $trackRoot,$distroRoot,(Join-Path $trackRoot 'metadata'),(Join-Path $trackRoot 'Terminals') -Force|Out-Null
    $emit={param($pct,$msg)if($OnProgress){&$OnProgress $pct $msg}}
    try {
        & $emit 5 "Acquiring $Distro root filesystem..."
        $rootfs=Save-DistroShelfAttemptRootfs -Distro $Distro -DestinationDirectory $distroRoot
        if(-not $rootfs.Verified){throw 'Root filesystem acquisition was not verified.'}
        $builderName="DistroShelf-TrackBuild-$($tx.Id)"
        & $emit 15 "Importing isolated $Distro Track builder..."
        $candidate=[pscustomobject]@{Id=$tx.Id;WslName=$builderName;Distro=$Distro;Name="$Distro-TrackBuilder"}
        Invoke-DistroShelfWslImport -Profile $candidate -RootfsPath $rootfs.Path -ExpectedSha256 $rootfs.Sha256 -StorageRoot (Join-Path $tx.Root 'Wsl')|Out-Null

        & $emit 20 'Testing root filesystem...'
        $rootTests=Invoke-DistroShelfTrackAcceptance -WslName $builderName -Tests @(
            @{Name='os-release';Command='test -s /etc/os-release'}
            @{Name='shell';Command='bash -lc "printf DISTROSHELF_ROOTFS_OK"';ExpectedOutput='DISTROSHELF_ROOTFS_OK'}
        )
        $rootHash=Get-DistroShelfTreeHash -Root $distroRoot
        $verified=@{rootfs=$rootHash}
        Write-DistroShelfHashRecord -Path (Join-Path (Join-Path $trackRoot 'metadata') 'rootfs.hash.json') -Stage 'rootfs' -Hash $rootHash -TestResult $rootTests|Out-Null
        $stageResults=@([pscustomobject]@{Id='rootfs';Hash=$rootHash;Tests=$rootTests})

        $stages=@($definition.Stages|Where-Object{[string]$_.Id-ne 'rootfs'})
        Test-DistroShelfDag -Stages @($definition.Stages)|Out-Null
        $remaining=$stages
        while($remaining.Count){
            $ready=@($remaining|Where-Object{@($_.Depends|Where-Object{-not $verified.ContainsKey([string]$_)}).Count-eq 0})
            if(!$ready.Count){throw 'Track DAG is blocked: a required prerequisite hash is missing.'}
            foreach($stage in $ready){
                $id=[string]$stage.Id;$stageRoot=Join-Path $trackRoot ($id -replace ':','-');New-Item -ItemType Directory -Path $stageRoot -Force|Out-Null
                & $emit 20 "Acquiring and testing Track stage '$id'..."
                if(-not $stage.Track){throw "Track stage '$id' has no Track implementation for '$Distro'."}
                foreach($cmd in @($stage.Track.Acquire)){
                    if([string]::IsNullOrWhiteSpace([string]$cmd)){continue}
                    $r=Invoke-DistroShelfCommand -WslName $builderName -Command ([string]$cmd) -CaptureOutput
                    if($r.ExitCode-ne 0){throw "Track stage '$id' acquisition failed: $cmd`n$($r.Output)"}
                }
                foreach($cmd in @($stage.Track.Install)){
                    if([string]::IsNullOrWhiteSpace([string]$cmd)){continue}
                    $r=Invoke-DistroShelfCommand -WslName $builderName -Command ([string]$cmd) -CaptureOutput
                    if($r.ExitCode-ne 0){throw "Track stage '$id' installation failed: $cmd`n$($r.Output)"}
                }
                $tests=@($stage.Track.Tests);if(!$tests.Count){throw "Track stage '$id' has no functional tests for '$Distro'."}
                $testResult=Invoke-DistroShelfStageTests -WslName $builderName -Tests $tests
                if(-not $testResult.Passed){throw "Track stage '$id' failed verification."}
                if([string]$stage.Track.ExportCommand){$r=Invoke-DistroShelfCommand -WslName $builderName -Command ([string]$stage.Track.ExportCommand) -CaptureOutput;if($r.ExitCode-ne 0){throw "Track stage '$id' artifact export failed.`n$($r.Output)"}}
                if(@(Get-ChildItem -LiteralPath $stageRoot -Recurse -File -ErrorAction SilentlyContinue).Count-eq 0){throw "Track stage '$id' passed tests but produced no Track artifact."}
                $hash=Get-DistroShelfTreeHash -Root $stageRoot
                Write-DistroShelfHashRecord -Path (Join-Path (Join-Path $trackRoot 'metadata') "$($id -replace ':','-').hash.json") -Stage $id -Hash $hash -TestResult $testResult|Out-Null
                $verified[$id]=$hash;$stageResults+=[pscustomobject]@{Id=$id;Hash=$hash;Tests=$testResult}
                $remaining=@($remaining|Where-Object{[string]$_.Id-ne $id})
            }
        }

        & $emit 85 'Running final Track acceptance tests...'
        $finalTests=@($definition.TrackFinalTests);if(!$finalTests.Count){throw "No final Track acceptance tests are defined for '$Distro'."}
        $final=Invoke-DistroShelfTrackAcceptance -WslName $builderName -Tests $finalTests
        $finalHash=Get-DistroShelfTreeHash -Root $trackRoot -ExcludeRelativePath @('metadata/track.hash.json','metadata/track.json')
        Write-DistroShelfHashRecord -Path (Join-Path (Join-Path $trackRoot 'metadata') 'track.hash.json') -Stage 'track' -Hash $finalHash -TestResult $final|Out-Null
        $manifest=[ordered]@{SchemaVersion=3;Distro=$Distro;Track=$definition.Track;FinalHash=$finalHash;Stages=$stageResults;CreatedAt=[DateTime]::UtcNow.ToString('o')}
        $manifest|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $trackRoot 'metadata\track.json') -Encoding UTF8
        try{& wsl.exe --terminate $builderName 2>$null|Out-Null}catch{}
        try{& wsl.exe --unregister $builderName 2>$null|Out-Null}catch{}
        & $emit 100 "Track $Distro verified; ready for atomic commit."
        return [pscustomobject][ordered]@{Success=$true;Transaction=$tx;TrackRoot=$trackRoot;FinalHash=$finalHash;Stages=$stageResults}
    } catch {
        $tr=Move-DistroShelfTransactionToTroubleshoot -Transaction $tx -ErrorRecord $_
        return [pscustomobject][ordered]@{Success=$false;Transaction=$tx;TroubleshootPath=$tr;Error=$_.Exception.Message}
    }
}

function Commit-DistroShelfTrackTransaction {
    param([Parameter(Mandatory)]$BuildResult)
    if(-not $BuildResult.Success){throw 'Cannot commit a failed Track transaction.'}
    $target=(Get-DistroShelfTrackDefinition $BuildResult.Transaction.Distro).Root
    Move-DistroShelfDirectoryAtomic -Source $BuildResult.TrackRoot -Destination $target
    return [pscustomobject][ordered]@{Success=$true;Distro=$BuildResult.Transaction.Distro;Track=(Split-Path -Leaf $target);Root=$target;FinalHash=$BuildResult.FinalHash}
}
