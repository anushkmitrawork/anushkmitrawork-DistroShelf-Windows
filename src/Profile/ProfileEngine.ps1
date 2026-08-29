# DistroShelf - Profile build engine
. (Join-Path $PSScriptRoot '..\Engine\TransactionEngine.ps1')
. (Join-Path $PSScriptRoot '..\Engine\HashEngine.ps1')
. (Join-Path $PSScriptRoot '..\Distro\DistroDefinitions.ps1')
. (Join-Path $PSScriptRoot '..\ProfileManager.ps1')
. (Join-Path $PSScriptRoot '..\WslImporter.ps1')

function Invoke-DistroShelfProfileBuild {
    param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][string]$Terminal,[Parameter(Mandatory)][string]$TrackRoot,[Parameter(Mandatory)][string]$TrackHash,[scriptblock]$OnProgress)
    $candidate=New-DistroShelfProfileCandidate -Distro $Distro
    $tx=New-DistroShelfTransaction -Kind Profile -Distro $Distro -Name $candidate.Name
    $profileRoot=Join-Path $tx.Root 'Profile';New-Item -ItemType Directory -Path $profileRoot -Force|Out-Null
    $wslStorage=Join-Path $tx.Root 'Wsl';New-Item -ItemType Directory -Path $wslStorage -Force|Out-Null
    $emit={param($p,$m)if($OnProgress){&$OnProgress $p $m}}
    $imported=$false
    try {
        if(-not (Test-DistroShelfHashRecord -Path (Join-Path (Join-Path $TrackRoot 'metadata') 'track.hash.json') -Root $TrackRoot -Stage 'track' -ExcludeRelativePath @('metadata'))){throw "Verified Track hash is missing or invalid for '$Distro'."}
        if($TrackHash -ne (Get-DistroShelfTreeHash -Root $TrackRoot -ExcludeRelativePath @('metadata'))){throw "Supplied Track hash does not match '$Distro'."}
        & $emit 10 "Creating isolated $($candidate.Name)..."
        $rootfs=Get-ChildItem -LiteralPath (Join-Path $TrackRoot 'Distro') -File|Select-Object -First 1;if(!$rootfs){throw "Verified Track has no root filesystem artifact for '$Distro'."}
        $imp=Invoke-DistroShelfWslImport -Profile ([pscustomobject]@{Id=$candidate.Id;WslName=$candidate.WslName}) -RootfsPath $rootfs.FullName -ExpectedSha256 (Get-FileHash $rootfs.FullName -Algorithm SHA256).Hash -StorageRoot $wslStorage;$imported=$true
        $definition=Get-DistroShelfDistroDefinition $Distro;$stages=@($definition.TrackStages)
        $mandatory=@('podman','distrobox','flatpak','flathub','distroshelf')
        $completed=0;$installResults=@()
        foreach($id in $mandatory){$stage=$stages|?{$_.Id-eq$id}|Select-Object -First 1;if(!$stage){throw "No Profile implementation exists for stage '$id' on '$Distro'."};foreach($cmd in @($stage.ProfileInstall)){& $emit (15+[int](65*$completed/$mandatory.Count)) "Installing $id...";& wsl.exe --distribution $candidate.WslName -- bash -lc $cmd 2>&1|Out-Null;if($LASTEXITCODE-ne 0){throw "Profile stage '$id' installation failed."}};$completed++;$installResults+=[pscustomobject]@{Stage=$id;Installed=$true}}
        & $emit 85 'Running complete Profile acceptance tests...'
        $tests=@()
        foreach($id in $mandatory){$s=$stages|?{$_.Id-eq$id}|Select-Object -First 1;$tests+=@($s.ProfileTests)}
        $final=Invoke-DistroShelfStageTests -WslName $candidate.WslName -Tests $tests
        if(-not $final.Passed -or $final.Results.Count -ne $tests.Count){throw 'Profile acceptance suite failed.'}
        $resultFile=Join-Path $profileRoot 'acceptance.json';[ordered]@{Distro=$Distro;Profile=$candidate.Name;Terminal=$Terminal;TrackHash=$TrackHash;Install=$installResults;Acceptance=$final;CompletedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 20|Set-Content $resultFile -Encoding UTF8
        $profileHash=Get-DistroShelfTreeHash -Root $profileRoot
        Write-DistroShelfHashRecord -Path (Join-Path $profileRoot 'profile.hash.json') -Stage 'profile' -Hash $profileHash -TestResult $final|Out-Null
        & $emit 100 "Profile $($candidate.Name) verified and ready to commit."
        return [pscustomobject]@{Success=$true;Transaction=$tx;Candidate=$candidate;ProfileRoot=$profileRoot;ProfileHash=$profileHash;Acceptance=$final}
    } catch {
        try{if($imported){& wsl.exe --terminate $candidate.WslName 2>$null|Out-Null}}catch{}
        $tr=Move-DistroShelfTransactionToTroubleshoot -Transaction $tx -ErrorRecord $_
        return [pscustomobject]@{Success=$false;Transaction=$tx;TroubleshootPath=$tr;Candidate=$candidate;Error=$_.Exception.Message}
    }
}
