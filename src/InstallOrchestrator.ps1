# DistroShelf - transaction coordinator
# This file contains no distro-specific package-manager logic.

. (Join-Path $PSScriptRoot 'Engine\TransactionEngine.ps1')
. (Join-Path $PSScriptRoot 'Engine\AtomicCommit.ps1')
. (Join-Path $PSScriptRoot 'Engine\AcceptanceEngine.ps1')
. (Join-Path $PSScriptRoot 'Engine\HashEngine.ps1')
. (Join-Path $PSScriptRoot 'Engine\DagScheduler.ps1')
. (Join-Path $PSScriptRoot 'Engine\TestEngine.ps1')
. (Join-Path $PSScriptRoot 'Distro\DistroDefinitions.ps1')
. (Join-Path $PSScriptRoot 'ProfileManager.ps1')
. (Join-Path $PSScriptRoot 'Profile\ProfileReservation.ps1')

function Invoke-DistroShelfInstall {
    param(
        [Parameter(Mandatory)][ValidateSet('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')][string]$Distro,
        [string]$Terminal='GNOME Console',
        [string]$ProfileId,
        [scriptblock]$OnProgress,
        [scriptblock]$OnStatus
    )
    function Report([int]$Percent,[string]$Message){if($OnProgress){&$OnProgress $Percent $Message};if($OnStatus){&$OnStatus $Message}}
    $definition=Get-DistroShelfDistroDefinition $Distro
    $reservation=$null;$tx=$null
    try {
        Report 2 "Preparing $Distro transaction..."
        $existing=$null
        if($ProfileId){$existing=Get-DistroShelfProfileById $ProfileId;if(!$existing){throw "Profile not found: $ProfileId"};if($existing.Distro-ne$Distro){throw 'Selected profile belongs to another distro.'};if($existing.Status-ne'Ready'){throw 'Only committed profiles may be reused.'}}
        $reservation=if($existing){$null}else{Reserve-DistroShelfProfileNumber $Distro}
        $profileName=if($existing){$existing.Name}else{"$((Get-DistroShelfProfileDefinition $Distro).WslBaseName)$($reservation.Number)"}
        $wslName=if($existing){$existing.WslName}else{"DistroShelf-$((Get-DistroShelfProfileDefinition $Distro).WslBaseName)$($reservation.Number)"}
        $tx=New-DistroShelfTransaction -Kind Profile -Distro $Distro
        Write-DistroShelfTransactionRecord -Transaction $tx -State Running -Data @{ProfileName=$profileName;WslName=$wslName;Terminal=$Terminal;DefinitionVersion=1}
        Report 5 "Profile $profileName reserved."

        # Track construction is intentionally delegated to a future TrackEngine. The coordinator
        # may only proceed once the Track final hash is valid.
        if(-not (Test-DistroShelfTrackIntegrity -Distro $Distro)){
            throw "No verified $Distro Track 0 is available. Track construction must complete before Profile installation."
        }
        Report 25 "Verified $Distro Track found."

        $profileCandidate=[pscustomobject][ordered]@{Id=[guid]::NewGuid().ToString();Name=$profileName;Distro=$Distro;WslName=$wslName;PackageManager=(Get-DistroShelfProfileDefinition $Distro).PackageManager;Terminal=$Terminal;AttemptRoot=$tx.Root;Status='Candidate'}
        $trackResult=[pscustomobject]@{Verified=$true}

        # Profile execution is deliberately explicit: a later ProfileEngine will install from
        # Track resources, run the complete acceptance suite, generate the final Profile hash,
        # and return a commit-ready candidate. No persistent profile record is created here.
        throw 'ProfileEngine is not wired yet; refusing to perform a partial legacy installation.'
    } catch {
        if($tx){$result=Move-DistroShelfTransactionToTroubleshoot -Transaction $tx -ErrorRecord $_}else{$result=$null}
        if($reservation){Release-DistroShelfProfileReservation $reservation}
        Report 100 'Installation failed; no committed Profile or Track was modified.'
        return [pscustomobject][ordered]@{Success=$false;ProfileId=$null;ProfileName=$null;WslName=$null;Distro=$Distro;Error=$_.Exception.Message;TroubleshootPath=$(if($result){$result}else{$null})}
    }
}
