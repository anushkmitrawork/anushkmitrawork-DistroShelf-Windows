# DistroShelf - Profile transaction engine
. (Join-Path $PSScriptRoot '..\Engine\TransactionEngine.ps1')
. (Join-Path $PSScriptRoot '..\Engine\HashEngine.ps1')
. (Join-Path $PSScriptRoot '..\Engine\AcceptanceEngine.ps1')
. (Join-Path $PSScriptRoot '..\Distro\DistroDefinitions.ps1')
. (Join-Path $PSScriptRoot '..\ProfileManager.ps1')
. (Join-Path $PSScriptRoot '..\WslImporter.ps1')

function Invoke-DistroShelfProfileBuild {
    param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][string]$Terminal,[Parameter(Mandatory)][string]$TrackRoot,[Parameter(Mandatory)][string]$TrackHash,[Parameter(Mandatory)][psobject]$Candidate,[scriptblock]$OnProgress)
    $tx=New-DistroShelfTransaction -Kind Profile -Distro $Distro
    $profileRoot=Join-Path $tx.Root 'Profile'
    $wslStorage=Join-Path $tx.Root 'Wsl'
    New-Item -ItemType Directory -Path $profileRoot,$wslStorage -Force|Out-Null
    $emit={param($pct,$msg)if($OnProgress){&$OnProgress $pct $msg}}
    try {
        $trackMeta=Join-Path $TrackRoot 'metadata'
        if(-not(Test-DistroShelfHashRecord -Path (Join-Path $trackMeta 'track.hash.json') -Root $TrackRoot -Stage 'track' -ExcludeRelativePath @('metadata/track.hash.json','metadata/track.json'))){throw "Verified Track hash is missing or invalid for '$Distro'."}
        $actualTrack=Get-DistroShelfTreeHash -Root $TrackRoot -ExcludeRelativePath @('metadata/track.hash.json','metadata/track.json')
        if($TrackHash.ToLowerInvariant() -ne $actualTrack.ToLowerInvariant()){throw "Supplied Track hash does not match '$Distro'."}

        & $emit 10 "Creating isolated $($Candidate.Name) attempt..."
        $rootfs=Get-ChildItem -LiteralPath (Join-Path $TrackRoot 'Distro') -File -ErrorAction SilentlyContinue|Select-Object -First 1
        if(!$rootfs){throw "Verified Track has no root filesystem artifact for '$Distro'."}
        $rootfsHash=(Get-FileHash -LiteralPath $rootfs.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $profileForImport=[pscustomobject]@{Id=$Candidate.Id;WslName=$Candidate.WslName;Distro=$Distro;Name=$Candidate.Name}
        Invoke-DistroShelfWslImport -Profile $profileForImport -RootfsPath $rootfs.FullName -ExpectedSha256 $rootfsHash -StorageRoot $wslStorage|Out-Null

        $definition=Get-DistroShelfDistroDefinition -Distro $Distro
        $stages=@($definition.Stages|Where-Object{[string]$_.Id-ne 'rootfs'})
        if(!$stages.Count){throw "No Profile stages are defined for '$Distro'."}
        $installed=@();$tests=@();$done=0
        foreach($stage in $stages){
            $id=[string]$stage.Id;$done++
            if(-not $stage.Profile){throw "Profile implementation for stage '$id' is not defined for '$Distro'."}
            & $emit (15+[int](55*($done-1)/$stages.Count)) "Installing Profile stage '$id'..."
            foreach($cmd in @($stage.Profile.Install)){
                $r=Invoke-DistroShelfCommand -WslName $Candidate.WslName -Command ([string]$cmd) -CaptureOutput
                if($r.ExitCode-ne 0){throw "Profile stage '$id' installation failed: $cmd`n$($r.Output)"}
            }
            $installed+=[pscustomobject]@{Stage=$id;Installed=$true}
            foreach($t in @($stage.Profile.Tests)){$tests+=$t}
        }
        if($definition.ProfileFinalTests){$tests+=@($definition.ProfileFinalTests)}
        if(!$tests.Count){throw "No complete Profile acceptance tests are defined for '$Distro'."}
        & $emit 82 'Running complete Profile acceptance suite...'
        $acceptance=Invoke-DistroShelfProfileAcceptance -WslName $Candidate.WslName -Tests $tests
        [ordered]@{SchemaVersion=1;Distro=$Distro;Profile=$Candidate.Name;Terminal=$Terminal;TrackHash=$TrackHash;InstalledStages=$installed;Acceptance=$acceptance;CompletedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $profileRoot 'acceptance.json') -Encoding UTF8
        $profileHash=Get-DistroShelfTreeHash -Root $profileRoot -ExcludeRelativePath @('profile.hash.json')
        Write-DistroShelfHashRecord -Path (Join-Path $profileRoot 'profile.hash.json') -Stage 'profile' -Hash $profileHash -TestResult $acceptance|Out-Null
        Complete-DistroShelfTransaction -Transaction $tx|Out-Null
        & $emit 100 "Profile $($Candidate.Name) verified and ready to commit."
        return [pscustomobject]@{Success=$true;Transaction=$tx;Candidate=$Candidate;ProfileRoot=$profileRoot;WslStorage=$wslStorage;ProfileHash=$profileHash;Acceptance=$acceptance}
    } catch {
        $tr=Move-DistroShelfTransactionToTroubleshoot -Transaction $tx -ErrorRecord $_
        return [pscustomobject]@{Success=$false;Transaction=$tx;Candidate=$Candidate;TroubleshootPath=$tr;Error=$_.Exception.Message}
    }
}
