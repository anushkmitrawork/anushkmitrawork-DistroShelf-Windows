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
        'rpm-cache' { switch($manager){'dnf'{Export-DistroShelfDnfCache -WslName $WslName -Destination $Destination -StageId $id|Out-Null}' 'zypper'{Export-DistroShelfZypperCache -WslName $WslName -Destination $Destination -StageId $id|Out-Null} default{throw "RPM exporter unavailable for '$manager'."}} }
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
        $hash=Get-DistroShelfTreeHash -Root $DistroRoot
    } else {
        Invoke-DistroShelfCommands -WslName $BuilderName -Commands @($Stage.Track.Acquire)
        Invoke-DistroShelfCommands -WslName $BuilderName -Commands @($Stage.Track.Install)
        $testResult=Invoke-DistroShelfStageTests -WslName $BuilderName -Tests @($Stage.Track.Tests)
        if(-not $testResult.Passed){throw "Track stage '$id' failed verification."}
        Export-DistroShelfTrackStageArtifact -Distro $Distro -Stage $Stage -WslName $BuilderName -Destination $stageRoot
        $hash=Get-DistroShelfTreeHash -Root $stageRoot
    }
    Write-DistroShelfHashRecord -Path (Join-Path (Join-Path $TrackRoot 'metadata') "$($id -replace ':','-').hash.json") -Stage $id -Hash $hash -TestResult $testResult|Out-Null
    [pscustomobject]@{Id=$id;Hash=$hash;Tests=$testResult;Stage=$Stage}
}

function Invoke-DistroShelfTrackBuilder {
    param([Parameter(Mandatory)][string]$Distro,[int]$MaxConcurrency=3,[scriptblock]$OnProgress)
    $provider=Get-DistroShelfProvider -Distro $Distro
    $tx=New-DistroShelfTransaction -Kind Track -Distro $Distro
    $trackRoot=Join-Path $tx.Root 'Track';$distroRoot=Join-Path $trackRoot 'Distro'
    New-Item -ItemType Directory -Path $trackRoot,$distroRoot,(Join-Path $trackRoot 'metadata'),(Join-Path $trackRoot 'Terminals') -Force|Out-Null
    $builderName=$null
    try {
        if($OnProgress){&$OnProgress 5 "Acquiring $Distro root filesystem..."}
        $rootfs=Save-DistroShelfAttemptRootfs -Distro $Distro -DestinationDirectory $distroRoot
        if(-not $rootfs.Verified){throw 'Root filesystem acquisition was not verified.'}
        $builderName="DistroShelf-TrackBuild-$($tx.Id)"
        if($OnProgress){&$OnProgress 15 "Importing isolated $Distro Track builder..."}
        $candidate=[pscustomobject]@{Id=$tx.Id;WslName=$builderName;Distro=$Distro;Name="$Distro-TrackBuilder"}
        Invoke-DistroShelfWslImport -Profile $candidate -RootfsPath $rootfs.Path -ExpectedSha256 $rootfs.Sha256 -StorageRoot (Join-Path $tx.Root 'Wsl')|Out-Null

        $verified=@{};$stageResults=@()
        $batches=Get-DistroShelfExecutionBatches -Definition $provider -MaxConcurrency $MaxConcurrency
        $batchNumber=0
        foreach($batch in @($batches)){
            $batchNumber++;$batch=@($batch);$label=($batch|ForEach-Object{[string]$_.Id}) -join ', '
            if($OnProgress){&$OnProgress ([Math]::Min(82,(20+($batchNumber*8)))) "Executing Track batch $batchNumber: $label"}
            # Batches are scheduler-selected and resource-lock safe. The WSL builder itself
            # is mutable shared state, so actual concurrent mutation is deliberately disabled
            # until a provider stage declares IsolatedExecution=$true. This preserves atomicity.
            foreach($stage in $batch){
                $result=Invoke-DistroShelfTrackStage -Distro $Distro -Stage $stage -BuilderName $builderName -TrackRoot $trackRoot -DistroRoot $distroRoot
                $verified[[string]$result.Id]=$result.Hash;$stageResults+=$result
            }
            $missing=@($batch|Where-Object{-not $verified.ContainsKey([string]$_.Id)})
            if($missing.Count){throw "Track batch completed without verified hashes: $($missing.Id -join ', ')"}
        }

        if($OnProgress){&$OnProgress 85 'Running final Track acceptance tests...'}
        $final=Invoke-DistroShelfTrackAcceptance -WslName $builderName -Tests @($provider.TrackFinalTests)
        if(-not $final.Passed){throw "Final Track acceptance failed for '$Distro'."}
        $finalHash=Get-DistroShelfTreeHash -Root $trackRoot -ExcludeRelativePath @('metadata/track.hash.json','metadata/track.json')
        Write-DistroShelfHashRecord -Path (Join-Path (Join-Path $trackRoot 'metadata') 'track.hash.json') -Stage 'track' -Hash $finalHash -TestResult $final|Out-Null
        $manifest=[ordered]@{SchemaVersion=5;Distro=$Distro;Track=$provider.Track;PackageManager=$provider.PackageManager;FinalHash=$finalHash;Stages=($stageResults|ForEach-Object{[pscustomobject]@{Id=$_.Id;Hash=$_.Hash;Tests=$_.Tests}});CreatedAt=[DateTime]::UtcNow.ToString('o')}
        $manifest|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $trackRoot 'metadata\track.json') -Encoding UTF8
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
    param([Parameter(Mandatory)]$BuildResult)
    if(-not $BuildResult.Success){throw 'Cannot commit a failed Track transaction.'}
    if([string]::IsNullOrWhiteSpace([string]$BuildResult.FinalHash)){throw 'Cannot commit Track without a final hash.'}
    $target=(Get-DistroShelfTrackDefinition $BuildResult.Transaction.Distro).Root
    if(Test-Path -LiteralPath $target){throw "Refusing to overwrite existing Track: $target"}
    Move-DistroShelfDirectoryAtomic -Source $BuildResult.TrackRoot -Destination $target
    [pscustomobject][ordered]@{Success=$true;Distro=$BuildResult.Transaction.Distro;Track=(Split-Path -Leaf $target);Root=$target;FinalHash=$BuildResult.FinalHash}
}
