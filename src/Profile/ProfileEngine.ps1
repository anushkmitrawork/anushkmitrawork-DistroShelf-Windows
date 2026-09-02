# DistroShelf - Profile transaction engine
. (Join-Path $PSScriptRoot '..\Engine\TransactionEngine.ps1')
. (Join-Path $PSScriptRoot '..\Engine\HashEngine.ps1')
. (Join-Path $PSScriptRoot '..\Engine\StageExecutor.ps1')
. (Join-Path $PSScriptRoot '..\Engine\AcceptanceEngine.ps1')
. (Join-Path $PSScriptRoot '..\Distro\Registry.ps1')
. (Join-Path $PSScriptRoot '..\DistroTrackManager.ps1')
. (Join-Path $PSScriptRoot '..\ProfileManager.ps1')
. (Join-Path $PSScriptRoot '..\WslImporter.ps1')
. (Join-Path $PSScriptRoot 'TrackArtifactBridge.ps1')
. (Join-Path $PSScriptRoot 'ProfileArtifactInstaller.ps1')

function Invoke-DistroShelfProfileBuild {
    param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][string]$Terminal,[Parameter(Mandatory)][string]$TrackRoot,[Parameter(Mandatory)][string]$TrackHash,[Parameter(Mandatory)][psobject]$Candidate,[scriptblock]$OnProgress)
    $tx=New-DistroShelfTransaction -Kind Profile -Distro $Distro
    $profileRoot=Join-Path $tx.Root 'Profile';$wslStorage=Join-Path $tx.Root 'Wsl';New-Item -ItemType Directory -Path $profileRoot,$wslStorage -Force|Out-Null
    $emit={param($pct,$msg)if($OnProgress){&$OnProgress $pct $msg}}
    try {
        if(-not(Test-DistroShelfTrackIntegrity -Distro $Distro)){throw "Committed Track for '$Distro' is missing or invalid."}
        $actualTrack=Get-DistroShelfTreeHash -Root $TrackRoot -ExcludeRelativePath @('metadata/track.hash.json','metadata/track.json')
        if($TrackHash.ToLowerInvariant() -ne $actualTrack.ToLowerInvariant()){throw "Supplied Track hash does not match '$Distro'."}
        $provider=Get-DistroShelfProvider -Distro $Distro
        $allStages=@($provider.Stages)
        $terminalStages=@($allStages|Where-Object{[string]$_.Kind -eq 'terminal'})
        if(!$terminalStages.Count){throw "No terminal preferences are defined for '$Distro'."}
        $selectedTerminal=@($terminalStages|Where-Object{[string]$_.TerminalName -eq $Terminal})|Select-Object -First 1
        if(!$selectedTerminal){throw "Terminal '$Terminal' is not available for '$Distro'."}
        $stages=@($allStages|Where-Object{[string]$_.Kind -ne 'terminal'})+$selectedTerminal
        $stages=@($stages|Where-Object{[string]$_.Id -ne 'rootfs'})
        if(!$stages.Count){throw "No Profile stages are defined for '$Distro'."}
        Test-DistroShelfDag -Stages @($stages)|Out-Null
        Test-DistroShelfRequiredTrackStages -TrackRoot $TrackRoot -Stages $stages|Out-Null
        $rootfs=Get-ChildItem -LiteralPath (Join-Path $TrackRoot 'Distro') -File -ErrorAction SilentlyContinue|Select-Object -First 1
        if(!$rootfs){throw "Verified Track has no root filesystem artifact for '$Distro'."}
        $rootfsHash=(Get-FileHash -LiteralPath $rootfs.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        & $emit 10 "Creating isolated $($Candidate.Name) attempt..."
        Invoke-DistroShelfWslImport -Profile ([pscustomobject]@{Id=$Candidate.Id;WslName=$Candidate.WslName;Distro=$Distro;Name=$Candidate.Name}) -RootfsPath $rootfs.FullName -ExpectedSha256 $rootfsHash -StorageRoot $wslStorage|Out-Null

        $done=0;$installed=@();$tests=@()
        foreach($stage in $stages){
            $id=[string]$stage.Id;$done++
            if(!$stage.Profile){throw "Profile implementation for stage '$id' is missing for '$Distro'."}
            if(-not(Test-DistroShelfHashRecord -Path (Join-Path (Join-Path $TrackRoot 'metadata') "$($id -replace ':','-').hash.json") -Root (Join-Path $TrackRoot ($id -replace ':','-')) -Stage $id)){
                throw "Required verified Track stage '$id' is unavailable or invalid."
            }
            Mount-DistroShelfTrackStageIntoProfile -WslName $Candidate.WslName -TrackRoot $TrackRoot -StageId $id|Out-Null
            & $emit (15+[int](50*($done-1)/$stages.Count)) "Installing Profile stage '$id' from verified Track artifacts..."
            $r=Install-DistroShelfProfileStageFromTrack -WslName $Candidate.WslName -Distro $Distro -Stage $stage -TrackRoot $TrackRoot
            if($r.ExitCode-ne 0){throw "Profile stage '$id' installation failed using verified Track artifacts.`n$($r.Output)"}
            $installed+=[pscustomobject]@{Stage=$id;Installed=$true;Source='Track';Terminal=$(if($stage.TerminalName){$stage.TerminalName}else{$null})}
            $tests+=@($stage.Profile.Tests)
        }
        if($provider.ProfileFinalTests){$tests+=@($provider.ProfileFinalTests)}
        if(!$tests.Count){throw "No complete Profile acceptance tests are defined for '$Distro'."}
        & $emit 82 'Running complete Profile acceptance suite...'
        $acceptance=Invoke-DistroShelfProfileAcceptance -WslName $Candidate.WslName -Tests $tests
        if(-not $acceptance.Passed){throw "Complete Profile acceptance failed for '$Distro'."}

        $manifest=[ordered]@{SchemaVersion=6;Distro=$Distro;Profile=$Candidate.Name;WslName=$Candidate.WslName;Terminal=$Terminal;TrackHash=$TrackHash;SelectedTerminal=$selectedTerminal.TerminalName;InstalledStages=$installed;Acceptance=$acceptance;CompletedAt=[DateTime]::UtcNow.ToString('o')}
        Write-DistroShelfJsonAtomically -Path (Join-Path $profileRoot 'profile.json') -Value $manifest
        & $emit 90 'Exporting the accepted Profile exactly once...'
        $export=Join-Path $tx.Root 'Export\profile.vhdx'
        New-Item -ItemType Directory -Path (Split-Path -Parent $export) -Force|Out-Null
        # Run under local 'Continue' so native stderr under $ErrorActionPreference='Stop'
        # does not become a terminating RemoteException in PowerShell 5.1.
        $savedEAP=$ErrorActionPreference
        try {
            $ErrorActionPreference='Continue'
            & wsl.exe --export $Candidate.WslName $export --format vhd 2>&1|ForEach-Object { "$_" }|Out-Null
        } finally {
            $ErrorActionPreference=$savedEAP
        }
        if($LASTEXITCODE-ne 0 -or -not(Test-Path -LiteralPath $export -PathType Leaf)){throw "Failed to export accepted Profile '$($Candidate.WslName)'."}
        $exportHash=(Get-FileHash -LiteralPath $export -Algorithm SHA256).Hash.ToLowerInvariant()
        if([string]::IsNullOrWhiteSpace($exportHash)){throw "Failed to hash exported Profile '$($Candidate.WslName)'."}
        $payload=[ordered]@{SchemaVersion=2;Kind='profile-artifact';ProfileId=$Candidate.Id;Name=$Candidate.Name;Distro=$Distro;WslName=$Candidate.WslName;Algorithm='SHA256';Hash=$exportHash;AcceptancePassed=$true;Artifact='Export/profile.vhdx';SelectedTerminal=$selectedTerminal.TerminalName;CreatedAt=[DateTime]::UtcNow.ToString('o')}
        $payloadRecordPath=Join-Path $profileRoot 'profile-artifact.hash.json'
        Write-DistroShelfJsonAtomically -Path $payloadRecordPath -Value $payload
        $payloadVerification=(Get-FileHash -LiteralPath $export -Algorithm SHA256).Hash.ToLowerInvariant()
        if($payloadVerification-ne $exportHash){throw 'Exported Profile artifact changed during verification.'}

        Write-DistroShelfHashRecord -Path (Join-Path $profileRoot 'profile.hash.json') -Stage 'profile' -Hash $exportHash -TestResult $acceptance|Out-Null
        Complete-DistroShelfTransaction -Transaction $tx|Out-Null
        & $emit 100 "Profile $($Candidate.Name) passed acceptance and has one verified commit artifact."
        return [pscustomobject][ordered]@{Success=$true;Transaction=$tx;Candidate=$Candidate;ProfileRoot=$profileRoot;WslStorage=$wslStorage;ExportPath=$export;ProfileHash=$exportHash;Acceptance=$acceptance;SelectedTerminal=$selectedTerminal.TerminalName}
    } catch {
        $tr=Move-DistroShelfTransactionToTroubleshoot -Transaction $tx -ErrorRecord $_
        return [pscustomobject][ordered]@{Success=$false;Transaction=$tx;Candidate=$Candidate;TroubleshootPath=$tr;Error=$_.Exception.Message}
    }
}
