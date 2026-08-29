# DistroShelf - transactional Track builder
. (Join-Path $PSScriptRoot '..\Engine\TransactionEngine.ps1')
. (Join-Path $PSScriptRoot '..\Engine\DagScheduler.ps1')
. (Join-Path $PSScriptRoot '..\Engine\HashEngine.ps1')
. (Join-Path $PSScriptRoot '..\Distro\DistroDefinitions.ps1')
. (Join-Path $PSScriptRoot '..\RootfsProvider.ps1')
. (Join-Path $PSScriptRoot '..\WslImporter.ps1')

function Invoke-DistroShelfTrackBuilder {
    param([Parameter(Mandatory)][string]$Distro,[scriptblock]$OnProgress)
    $tx=New-DistroShelfTransaction -Kind Track -Distro $Distro -Name ("$Distro`0")
    $trackRoot=Join-Path $tx.Root 'Track'
    New-Item -ItemType Directory -Path $trackRoot,(Join-Path $trackRoot 'Distro'),(Join-Path $trackRoot 'metadata'),(Join-Path $trackRoot 'Terminals') -Force|Out-Null
    $builderName="DistroShelf-TrackBuild-$($tx.Id)";$builderStorage=Join-Path (Join-Path $tx.Root 'Wsl') $builderName
    $builderImported=$false
    try {
        $emit={param($pct,$msg)if($OnProgress){&$OnProgress $pct $msg}}
        & $emit 5 "Acquiring $Distro root filesystem..."
        $rootfs=Save-DistroShelfRootfs -Distro $Distro -DestinationDirectory (Join-Path $trackRoot 'Distro')
        & $emit 20 "Importing isolated $Distro Track builder..."
        $candidate=[pscustomobject]@{Id=$tx.Id;WslName=$builderName;Distro=$Distro;Name="$Distro-TrackBuilder"}
        $imp=Invoke-DistroShelfWslImport -Profile $candidate -RootfsPath $rootfs.Path -ExpectedSha256 $rootfs.Sha256 -StorageRoot (Join-Path $tx.Root 'Wsl')
        $builderImported=$true
        & $emit 25 'Validating Track dependency graph...'
        $stages=@(Get-DistroShelfDistroStages $Distro)
        foreach($s in $stages){if($s.Id -like 'terminal:*'){continue}}
        $graph=@(@{Id='distro';Requires=@()} + ($stages | ForEach-Object {[pscustomobject]$_}))
        Test-DistroShelfGraph -Stages $graph|Out-Null
        $completed=@{distro=$true}
        $stageResults=@()
        while($completed.Count -lt $graph.Count){
            $eligible=@(Get-DistroShelfEligibleStages -Stages $graph -Completed $completed)
            if(!$eligible.Count){throw 'Track dependency graph is blocked.'}
            foreach($stage in $eligible){
                if($stage.Id -eq 'distro'){ $completed.distro=$true; continue }
                & $emit (25 + [int](50*$completed.Count/$graph.Count)) "Acquiring and testing Track stage '$($stage.Id)'..."
                $stageRoot=Join-Path $trackRoot ($stage.Id -replace ':','-');New-Item -ItemType Directory -Path $stageRoot -Force|Out-Null
                foreach($cmd in @($stage.TrackAcquire)){
                    if([string]::IsNullOrWhiteSpace([string]$cmd)){continue}
                    & wsl.exe --distribution $builderName -- bash -lc $cmd 2>&1 | Out-Null
                    if($LASTEXITCODE-ne 0){throw "Track stage '$($stage.Id)' acquisition failed: $cmd"}
                }
                $tests=Invoke-DistroShelfStageTests -WslName $builderName -Tests @($stage.TrackTests)
                if(-not $tests.Passed){throw "Track stage '$($stage.Id)' failed verification."}
                # Snapshot the package-manager cache for package stages. Repository/config stages retain their test report as the artifact.
                $source=(switch((Get-DistroShelfDistroDefinition $Distro).PackageManager){'apt'{'/var/cache/apt/archives'}'dnf'{'/var/cache/dnf'}'pacman'{'/track-cache'}'zypper'{'/var/cache/zypp/packages'}default{$null}})
                if($source){$share="\\wsl$\$builderName$source";if(Test-Path -LiteralPath $share){Copy-Item -LiteralPath $share -Destination (Join-Path $stageRoot 'packages') -Recurse -Force -ErrorAction SilentlyContinue}}
                $hash=Get-DistroShelfTreeHash -Root $stageRoot
                $hashPath=Join-Path (Join-Path $trackRoot 'metadata') "$($stage.Id -replace ':','-').hash.json"
                Write-DistroShelfHashRecord -Path $hashPath -Stage $stage.Id -Hash $hash -TestResult $tests|Out-Null
                $stageResults+=[pscustomobject]@{Id=$stage.Id;Hash=$hash;Tests=$tests}
                $completed[[string]$stage.Id]=$true
            }
        }
        & $emit 82 'Running final Track acceptance checks...'
        $finalTests=@(
            (New-DistroShelfCommandTest 'wsl-boot' 'printf "DISTROSHELF_TRACK_OK\\n"'),
            (New-DistroShelfCommandTest 'podman-command' 'command -v podman'),
            (New-DistroShelfCommandTest 'distrobox-command' 'command -v distrobox'),
            (New-DistroShelfCommandTest 'flatpak-command' 'command -v flatpak')
        )
        $final=Invoke-DistroShelfStageTests -WslName $builderName -Tests $finalTests
        if(-not $final.Passed){throw 'Final Track acceptance tests failed.'}
        $finalHash=Get-DistroShelfTreeHash -Root $trackRoot
        Write-DistroShelfHashRecord -Path (Join-Path (Join-Path $trackRoot 'metadata') 'track.hash.json') -Stage 'track' -Hash $finalHash -TestResult $final|Out-Null
        $manifest=[ordered]@{SchemaVersion=2;Distro=$Distro;Track=$Distro+'0';FinalHash=$finalHash;Stages=$stageResults;CreatedAt=[DateTime]::UtcNow.ToString('o')}
        $manifest|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $trackRoot 'metadata\track.json') -Encoding UTF8
        if($builderImported){& wsl.exe --terminate $builderName 2>$null|Out-Null}
        & $emit 100 "Track $Distro is verified and ready to commit."
        return [pscustomobject][ordered]@{Success=$true;Transaction=$tx;TrackRoot=$trackRoot;FinalHash=$finalHash;Stages=$stageResults}
    } catch {
        try{if($builderImported){& wsl.exe --terminate $builderName 2>$null|Out-Null}}catch{}
        $tr=Move-DistroShelfTransactionToTroubleshoot -Transaction $tx -ErrorRecord $_
        return [pscustomobject][ordered]@{Success=$false;Transaction=$tx;TroubleshootPath=$tr;Error=$_.Exception.Message}
    }
}
