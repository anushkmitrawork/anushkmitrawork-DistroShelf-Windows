# DistroShelf - transactional Track builder
. (Join-Path $PSScriptRoot '..\Engine\TransactionEngine.ps1')
. (Join-Path $PSScriptRoot '..\Engine\DagScheduler.ps1')
. (Join-Path $PSScriptRoot '..\Engine\HashEngine.ps1')
. (Join-Path $PSScriptRoot '..\Engine\StageExecutor.ps1')
. (Join-Path $PSScriptRoot '..\Engine\AcceptanceEngine.ps1')
. (Join-Path $PSScriptRoot '..\Engine\ArtifactExporter.ps1')
. (Join-Path $PSScriptRoot '..\Distro\Registry.ps1')
. (Join-Path $PSScriptRoot 'RootfsAcquisition.ps1')
. (Join-Path $PSScriptRoot '..\WslImporter.ps1')
. (Join-Path $PSScriptRoot '..\Engine\AtomicCommit.ps1')

function Export-DistroShelfTrackStageArtifact {
    param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)]$Stage,[Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$Destination)
    $type=[string]$Stage.Track.ExportType;$value=[string]$Stage.Track.ExportValue;$provider=Get-DistroShelfProvider -Distro $Distro;$manager=[string]$provider.PackageManager;$id=[string]$Stage.Id
    switch($type){
        'apt-cache' { Export-DistroShelfAptCache -WslName $WslName -Destination $Destination -StageId $id|Out-Null }
        'rpm-cache' {
            switch($manager){
                'dnf' { Export-DistroShelfDnfCache -WslName $WslName -Destination $Destination -StageId $id|Out-Null }
                'zypper' { Export-DistroShelfZypperCache -WslName $WslName -Destination $Destination -StageId $id|Out-Null }
                default { throw "RPM exporter unavailable for '$manager'." }
            }
        }
        'pacman-cache' { Export-DistroShelfPacmanCache -WslName $WslName -Destination $Destination -StageId $id|Out-Null }
        'wsl-path' { Export-DistroShelfWslPath -WslName $WslName -WslPath $value -Destination $Destination|Out-Null }
        'flatpak-sideload' { Export-DistroShelfFlatpakSideload -WslName $WslName -AppId $value -Destination $Destination|Out-Null }
        default { throw "No Track artifact exporter declared for stage '$id' on '$Distro'." }
    }
    if(@(Get-ChildItem -LiteralPath $Destination -Recurse -File -ErrorAction SilentlyContinue).Count -eq 0){throw "Track stage '$id' produced no reusable artifacts."}
}

function Invoke-DistroShelfTrackStage {
    param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)]$Stage,[Parameter(Mandatory)][string]$BuilderName,[Parameter(Mandatory)][string]$TrackRoot,[Parameter(Mandatory)][string]$DistroRoot)
    $id=[string]$Stage.Id;$stageRoot=Join-Path $TrackRoot ($id -replace ':','-');New-Item -ItemType Directory -Path $stageRoot -Force|Out-Null
    if($id -eq 'rootfs'){
        $testResult=Invoke-DistroShelfTrackAcceptance -WslName $BuilderName -Tests @($Stage.Track.Tests)
        if(-not $testResult.Passed){throw "Track stage '$id' failed verification."}
        $hash=Get-DistroShelfTreeHash -Root $DistroRoot;$hashRoot=$DistroRoot
    } else {
        Invoke-DistroShelfCommands -WslName $BuilderName -Commands @($Stage.Track.Acquire)
        Invoke-DistroShelfCommands -WslName $BuilderName -Commands @($Stage.Track.Install)
        $testResult=Invoke-DistroShelfStageTests -WslName $BuilderName -Tests @($Stage.Track.Tests)
        if(-not $testResult.Passed){throw "Track stage '$id' failed verification."}
        Export-DistroShelfTrackStageArtifact -Distro $Distro -Stage $Stage -WslName $BuilderName -Destination $stageRoot
        $hash=Get-DistroShelfTreeHash -Root $stageRoot;$hashRoot=$stageRoot
    }
    $hashRecordPath=Join-Path (Join-Path $TrackRoot 'metadata') "$($id -replace ':','-').hash.json"
    Write-DistroShelfHashRecord -Path $hashRecordPath -Stage $id -Hash $hash -TestResult $testResult|Out-Null
    if(-not(Test-DistroShelfHashRecord -Path $hashRecordPath -Root $hashRoot -Stage $id)){throw "Track stage '$id' hash record failed immediate verification."}
    [pscustomobject]@{Id=$id;Hash=$hash;Tests=$testResult;Stage=$Stage}
}

function Invoke-DistroShelfTrackBuilder {
    param([Parameter(Mandatory)][string]$Distro,[scriptblock]$OnProgress)
    $provider=Get-DistroShelfProvider -Distro $Distro
    $stages=@($provider.Stages)
    $linearOrder=@(Get-DistroShelfLinearExecutionPlan -Definition $provider)
    $tx=New-DistroShelfTransaction -Kind Track -Distro $Distro
    $trackRoot=Join-Path $tx.Root 'Track';$distroRoot=Join-Path $trackRoot 'Distro'
    New-Item -ItemType Directory -Path $trackRoot,$distroRoot,(Join-Path $trackRoot 'metadata'),(Join-Path $trackRoot 'Terminals') -Force|Out-Null
    Write-DistroShelfTransactionRecord -Transaction $tx -State 'Running' -Data @{Phase='TrackBuildStarted';Distro=$Distro;StageCount=$stages.Count;ExecutionMode='Linear'}|Out-Null
    $builderName=$null
    try {
        if($OnProgress){&$OnProgress 5 "Acquiring $Distro root filesystem..."}
        $rootfs=Save-DistroShelfAttemptRootfs -Distro $Distro -DestinationDirectory $distroRoot
        if(-not $rootfs.Verified){throw 'Root filesystem acquisition was not verified.'}
        $actualRootfsHash=(Get-FileHash -LiteralPath $rootfs.Path -Algorithm SHA256).Hash.ToLowerInvariant()
        if($actualRootfsHash -ne $rootfs.Sha256.ToLowerInvariant()){throw 'Acquired root filesystem changed before import.'}
        $builderName="DistroShelf-TrackBuild-$($tx.Id)"
        if($OnProgress){&$OnProgress 15 "Importing isolated $Distro Track builder..."}
        $candidate=[pscustomobject]@{Id=$tx.Id;WslName=$builderName;Distro=$Distro;Name="$Distro-TrackBuilder"}
        Invoke-DistroShelfWslImport -Profile $candidate -RootfsPath $rootfs.Path -ExpectedSha256 $rootfs.Sha256 -StorageRoot (Join-Path $tx.Root 'Wsl')|Out-Null

        $verified=@{};$stageResults=@();$stageNumber=0
        foreach($stage in $linearOrder){
            $stageNumber++
            foreach($dependency in @($stage.Depends)){
                $depId=[string]$dependency
                if(-not $verified.ContainsKey($depId)){throw "Linear DAG invariant violated: '$($stage.Id)' ran before verified prerequisite '$depId'."}
            }
            if($OnProgress){&$OnProgress ([Math]::Min(82,(20+($stageNumber*8)))) "Executing stage ${stageNumber}: $([string]$stage.Id)"}
            if([string]$stage.ExecutionModel -eq 'IsolatedBuilder'){
                throw "Stage '$($stage.Id)' declares IsolatedBuilder, but Core execution is linear on the shared Track builder."
            }
            $result=Invoke-DistroShelfTrackStage -Distro $Distro -Stage $stage -BuilderName $builderName -TrackRoot $trackRoot -DistroRoot $distroRoot
            if([string]::IsNullOrWhiteSpace([string]$result.Hash)){throw "Track stage '$($result.Id)' completed without a verified hash."}
            $verified[[string]$result.Id]=$result.Hash
            $stageResults+=$result
            Write-DistroShelfTransactionRecord -Transaction $tx -State 'Running' -Data @{Phase='StageVerified';LastStage=$result.Id;VerifiedStages=@($verified.Keys|Sort-Object);StageResults=@($stageResults|ForEach-Object{[pscustomobject]@{Id=$_.Id;Hash=$_.Hash}})}|Out-Null
        }

        if($OnProgress){&$OnProgress 85 'Running final Track acceptance tests...'}
        $final=Invoke-DistroShelfTrackAcceptance -WslName $builderName -Tests @($provider.TrackFinalTests)
        if(-not $final.Passed){throw "Final Track acceptance failed for '$Distro'."}
        $finalHash=Get-DistroShelfTreeHash -Root $trackRoot -ExcludeRelativePath @('metadata/track.hash.json','metadata/track.json')
        if([string]::IsNullOrWhiteSpace($finalHash) -or $finalHash.Length -ne 64){throw 'Final Track hash generation failed.'}
        Write-DistroShelfHashRecord -Path (Join-Path (Join-Path $trackRoot 'metadata') 'track.hash.json') -Stage 'track' -Hash $finalHash -TestResult $final|Out-Null
        $manifest=[ordered]@{SchemaVersion=8;Distro=$Distro;Track=$provider.Track;PackageManager=$provider.PackageManager;FinalHash=$finalHash;Stages=($stageResults|ForEach-Object{[pscustomobject]@{Id=$_.Id;Hash=$_.Hash;Tests=$_.Tests}});CreatedAt=[DateTime]::UtcNow.ToString('o')}
        $manifest|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $trackRoot 'metadata\track.json') -Encoding UTF8
        Write-DistroShelfTransactionRecord -Transaction $tx -State 'Verified' -Data @{Phase='TrackVerified';FinalHash=$finalHash;VerifiedStages=@($stageResults|ForEach-Object{[pscustomobject]@{Id=$_.Id;Hash=$_.Hash}})}|Out-Null
        $tx.State='Verified'
        try{& wsl.exe --terminate $builderName 2>$null|Out-Null}catch{};try{& wsl.exe --unregister $builderName 2>$null|Out-Null}catch{}
        if($OnProgress){&$OnProgress 100 "Track $Distro verified; ready for atomic commit."}
        [pscustomobject][ordered]@{Success=$true;Transaction=$tx;TrackRoot=$trackRoot;FinalHash=$finalHash;Stages=$stageResults}
    } catch {
        try{if($builderName){& wsl.exe --terminate $builderName 2>$null|Out-Null};if($builderName){& wsl.exe --unregister $builderName 2>$null|Out-Null}}catch{}
        $tr=Move-DistroShelfTransactionToTroubleshoot -Transaction $tx -ErrorRecord $_
        [pscustomobject][ordered]@{Success=$false;Transaction=$tx;TroubleshootPath=$tr;Error=$_.Exception.Message}
    }
}

function Commit-DistroShelfTrackTransaction {
    param(
        [Parameter(Mandatory)]$BuildResult,
        [string]$TargetRoot,
        [scriptblock]$TreeHash = { param($Root) Get-DistroShelfTreeHash -Root $Root -ExcludeRelativePath @('metadata/track.hash.json','metadata/track.json') },
        [scriptblock]$IntegrityCheck = { param($Distro) Test-DistroShelfTrackIntegrity -Distro $Distro },
        [scriptblock]$Promote = { param($Source,$Destination) Move-DistroShelfDirectoryAtomic -Source $Source -Destination $Destination },
        [scriptblock]$Troubleshoot = { param($Transaction,$ErrorRecord) Move-DistroShelfTransactionToTroubleshoot -Transaction $Transaction -ErrorRecord $ErrorRecord }
    )
    if(-not $BuildResult.Success){throw 'Cannot commit a failed Track transaction.'}
    if([string]::IsNullOrWhiteSpace([string]$BuildResult.FinalHash)){throw 'Cannot commit Track without a final hash.'}
    if(-not(Test-Path -LiteralPath $BuildResult.TrackRoot -PathType Container)){throw 'Cannot commit Track: transaction Track tree is missing.'}
    $actualHash=& $TreeHash $BuildResult.TrackRoot
    if([string]$actualHash -ne [string]$BuildResult.FinalHash.ToLowerInvariant()){throw 'Cannot commit Track: transaction tree no longer matches its verified final hash.'}
    $target=if($TargetRoot){[IO.Path]::GetFullPath($TargetRoot)}else{[IO.Path]::GetFullPath((Get-DistroShelfTrackDefinition $BuildResult.Transaction.Distro).Root)}
    if(Test-Path -LiteralPath $target){throw "Refusing to overwrite existing Track: $target"}
    try {
        & $Promote $BuildResult.TrackRoot $target
        $committedHash=& $TreeHash $target
        if([string]$committedHash -ne [string]$BuildResult.FinalHash.ToLowerInvariant()){throw "Track integrity hash changed during promotion: $target"}
        [pscustomobject][ordered]@{Success=$true;Distro=$BuildResult.Transaction.Distro;Track=(Split-Path -Leaf $target);Root=$target;FinalHash=$BuildResult.FinalHash}
    } catch {
        if(Test-Path -LiteralPath $target -PathType Container -and -not(Test-Path -LiteralPath $BuildResult.TrackRoot)){
            try { New-Item -ItemType Directory -Path (Split-Path -Parent $BuildResult.TrackRoot) -Force|Out-Null;Move-DistroShelfDirectoryAtomic -Source $target -Destination $BuildResult.TrackRoot } catch {}
        }
        $tr=& $Troubleshoot $BuildResult.Transaction $_
        throw "Track commit failed; failed attempt preserved at '$tr'. $($_.Exception.Message)"
    }
}
