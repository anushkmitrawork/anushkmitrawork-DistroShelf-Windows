# DistroShelf - transaction coordinator
. (Join-Path $PSScriptRoot 'Engine\TransactionEngine.ps1')
. (Join-Path $PSScriptRoot 'Engine\AcceptanceEngine.ps1')
. (Join-Path $PSScriptRoot 'Engine\HashEngine.ps1')
. (Join-Path $PSScriptRoot 'Engine\DagScheduler.ps1')
. (Join-Path $PSScriptRoot 'Distro\Registry.ps1')
. (Join-Path $PSScriptRoot 'DistroTrackManager.ps1')
. (Join-Path $PSScriptRoot 'Track\TrackEngine.ps1')
. (Join-Path $PSScriptRoot 'ProfileManager.ps1')
. (Join-Path $PSScriptRoot 'Profile\ProfileReservation.ps1')
. (Join-Path $PSScriptRoot 'Profile\ProfileEngine.ps1')
. (Join-Path $PSScriptRoot 'Profile\ProfileCommit.ps1')

function Invoke-DistroShelfInstall {
    param(
        [Parameter(Mandatory)][ValidateSet('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')][string]$Distro,
        [string]$Terminal='GNOME Console',
        [string]$ProfileId,
        [scriptblock]$OnProgress,
        [scriptblock]$OnStatus
    )
    function Report([int]$Percent,[string]$Message){if($OnProgress){&$OnProgress $Percent $Message};if($OnStatus){&$OnStatus $Message}}
    $reservation=$null;$profileTx=$null;$trackBuild=$null;$candidate=$null;$commitTroubleshoot=$null
    try {
        $provider=Get-DistroShelfProvider -Distro $Distro
        $existing=$null
        if($ProfileId){
            $existing=Get-DistroShelfProfileById -Id $ProfileId
            if(!$existing){throw "Profile not found: $ProfileId"}
            if([string]$existing.Distro -ne $Distro){throw 'Selected profile belongs to another distro.'}
            if([string]$existing.Status -ne 'Ready'){throw 'Only committed profiles may be reused.'}
        }
        if($existing){throw 'Reinstallation of an existing committed Profile is not implemented in the atomic engine yet.'}
        $reservation=Reserve-DistroShelfProfileNumber -Distro $Distro
        $candidate=[pscustomobject]@{Id=$reservation.Id;Name=$reservation.Name;Distro=$Distro;WslName="DistroShelf-$($reservation.Name)";PackageManager=$provider.PackageManager;Status='Candidate';Terminal=$Terminal}
        Report 2 "Preparing $($candidate.Name)..."

        if(-not(Test-DistroShelfTrackIntegrity -Distro $Distro)){
            Report 5 "Building verified $Distro Track..."
            $trackBuild=Invoke-DistroShelfTrackBuilder -Distro $Distro -OnProgress {param($p,$m)Report ([Math]::Min(24,[Math]::Max(5,$p*0.20))) $m}
            if(-not $trackBuild.Success){throw "Track construction failed: $($trackBuild.Error)`nTroubleshoot: $($trackBuild.TroubleshootPath)"}
            if(-not $trackBuild.FinalHash){throw 'Track builder returned success without a final Track hash.'}
            Commit-DistroShelfTrackTransaction -BuildResult $trackBuild|Out-Null
        }
        $trackDefinition=Get-DistroShelfTrackDefinition -Distro $Distro
        $trackMeta=Get-DistroShelfTrackManifest -Distro $Distro
        if(-not $trackMeta -or [string]::IsNullOrWhiteSpace([string]$trackMeta.FinalHash)){throw "Verified Track metadata is missing for '$Distro'."}
        $trackHash=[string]$trackMeta.FinalHash
        if(-not (Test-DistroShelfTrackIntegrity -Distro $Distro)){throw "Track integrity verification failed for '$Distro'."}
        Report 28 "Verified $Distro Track found."

        $profileTx=Invoke-DistroShelfProfileBuild -Distro $Distro -Terminal $Terminal -TrackRoot $trackDefinition.Root -TrackHash $trackHash -Candidate $candidate -OnProgress {param($p,$m)Report ([Math]::Min(94,[Math]::Max(28,$p))) $m}
        if(-not $profileTx.Success){throw "Profile construction failed: $($profileTx.Error)`nTroubleshoot: $($profileTx.TroubleshootPath)"}
        if(-not $profileTx.ProfileHash){throw 'Profile builder returned success without a final Profile hash.'}
        Report 96 'Profile verified; committing...'
        $committed=Commit-DistroShelfProfileTransaction -BuildResult $profileTx -Reservation $reservation -Terminal $Terminal
        $reservation=$null
        Report 100 "Installation complete: $($committed.Profile.Name)."
        return [pscustomobject][ordered]@{Success=$true;ProfileId=$committed.Profile.Id;ProfileName=$committed.Profile.Name;WslName=$committed.WslName;Distro=$Distro;Error=$null;TroubleshootPath=$null}
    } catch {
        # ProfileEngine moves build failures to Troubleshoot itself. A commit failure happens
        # after BuildResult.Success and therefore needs the coordinator to preserve that
        # still-live transaction as well.
        if($profileTx -and $profileTx.Success -and $profileTx.Transaction -and (Test-Path -LiteralPath $profileTx.Transaction.Root)){
            try{$commitTroubleshoot=Move-DistroShelfTransactionToTroubleshoot -Transaction $profileTx.Transaction -ErrorRecord $_}catch{}
        }
        $troubleshoot=$commitTroubleshoot
        if(-not $troubleshoot -and $profileTx -and $profileTx.TroubleshootPath){$troubleshoot=$profileTx.TroubleshootPath}
        if(-not $troubleshoot -and $trackBuild -and $trackBuild.TroubleshootPath){$troubleshoot=$trackBuild.TroubleshootPath}
        if($reservation){try{Release-DistroShelfProfileReservation -Reservation $reservation}catch{}}
        Report 100 'Installation failed; no unverified Profile or Track state was committed.'
        return [pscustomobject][ordered]@{Success=$false;ProfileId=$null;ProfileName=$(if($candidate){$candidate.Name}else{$null});WslName=$(if($candidate){$candidate.WslName}else{$null});Distro=$Distro;Error=$_.Exception.Message;TroubleshootPath=$troubleshoot}
    }
}
