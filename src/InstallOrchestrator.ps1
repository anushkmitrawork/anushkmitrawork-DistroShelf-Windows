# DistroShelf for Windows - transactional installation orchestrator
. (Join-Path $PSScriptRoot 'ProvisionProfile.ps1')
. (Join-Path $PSScriptRoot 'DependencyEngine.ps1')
function Invoke-DistroShelfInstall {
    param([Parameter(Mandatory)][ValidateSet('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')][string]$Distro,[string]$Terminal='GNOME Console',[string]$ProfileId,[scriptblock]$OnProgress,[scriptblock]$OnStatus)
    function Report-Progress([int]$Percent,[string]$Message){if($OnProgress){& $OnProgress $Percent $Message};if($OnStatus){& $OnStatus $Message}}
    $profile=$null;$attemptRoot=$null;$trackRoot=$null;$wslStorage=Join-Path $env:LOCALAPPDATA 'DistroShelf\wsl';$wslImported=$false
    try {
        Report-Progress 5 "Preparing $Distro installation attempt..."
        if($ProfileId){$profile=Get-DistroShelfProfileById -Id $ProfileId;if(!$profile){throw "Selected DistroShelf profile was not found: $ProfileId"};if([string]$profile.Distro-ne$Distro){throw "Selected profile belongs to $($profile.Distro), not $Distro."};if([string]$profile.Status-ne'Ready'){throw "Only a verified Ready profile can be selected for reuse: $($profile.Name)."}}
        else{$profile=New-DistroShelfProfileCandidate -Distro $Distro}
        $attemptId=[guid]::NewGuid().ToString();$attemptRoot=Join-Path (Join-Path $env:LOCALAPPDATA 'DistroShelf\Attempts') $attemptId;$trackRoot=Join-Path $attemptRoot 'Track';New-Item -ItemType Directory -Path $trackRoot -Force|Out-Null
        $committedRoot=(Get-DistroShelfTrackDefinition $Distro).Root
        if(Test-Path -LiteralPath $committedRoot -PathType Container){Copy-Item -LiteralPath $committedRoot -Destination $trackRoot -Recurse -Force}
        $oldOverride=$env:DISTROSHELF_TRACK_ROOT_OVERRIDE;$env:DISTROSHELF_TRACK_ROOT_OVERRIDE=$trackRoot
        try {
            Report-Progress 15 'Preparing and verifying Track 0 in an isolated staging area...'
            $artifact=Save-DistroShelfRootfs -Distro $Distro
            Report-Progress 35 "Creating $($profile.Name) as an isolated WSL 2 profile..."
            $import=Invoke-DistroShelfWslImport -Profile $profile -RootfsPath $artifact.Path -ExpectedSha256 $artifact.Sha256 -StorageRoot $wslStorage;$wslImported=$true
            Report-Progress 50 'Installing Podman, Distrobox and Flatpak...'
            $deps=Invoke-DistroShelfDependencyInstall -Profile $profile
            if(-not(Test-DistroShelfTrackComplete -Distro $Distro)){throw "Track 0 verification failed for '$Distro'. The reusable track was not promoted."}
        } finally {$env:DISTROSHELF_TRACK_ROOT_OVERRIDE=$oldOverride}
        Report-Progress 85 'Promoting the verified Track 0 and finalizing the profile...'
        $finalTrack=(Get-DistroShelfTrackDefinition $Distro).Root
        if(Test-Path -LiteralPath $finalTrack -PathType Container){
            $trackParent=Split-Path $finalTrack -Parent;$oldOverride=$env:DISTROSHELF_TRACK_ROOT_OVERRIDE;$env:DISTROSHELF_TRACK_ROOT_OVERRIDE=$trackParent
            try{$existingComplete=Test-DistroShelfTrackComplete -Distro $Distro}finally{$env:DISTROSHELF_TRACK_ROOT_OVERRIDE=$oldOverride}
            if($existingComplete){Remove-Item -LiteralPath (Join-Path $trackRoot (Split-Path $finalTrack -Leaf)) -Recurse -Force -ErrorAction SilentlyContinue}
            else{$quarantine=Join-Path (Join-Path $env:LOCALAPPDATA 'DistroShelf\Troubleshoot') ("PreviousTrack-{0}-{1}" -f $Distro,(Get-Date -Format 'yyyyMMdd-HHmmss'));New-Item -ItemType Directory -Path $quarantine -Force|Out-Null;Move-Item -LiteralPath $finalTrack -Destination (Join-Path $quarantine (Split-Path $finalTrack -Leaf)) -Force}
        }
        if(-not(Test-Path -LiteralPath $finalTrack)){$parent=Split-Path $finalTrack -Parent;New-Item -ItemType Directory -Path $parent -Force|Out-Null;Move-Item -LiteralPath (Join-Path $trackRoot (Split-Path $finalTrack -Leaf)) -Destination $finalTrack -Force}
        $committed=Commit-DistroShelfProfile -Candidate $profile -Terminal $Terminal
        Remove-Item -LiteralPath $attemptRoot -Recurse -Force -ErrorAction SilentlyContinue
        Report-Progress 100 "Installation complete: $($committed.Name)"
        return [pscustomobject][ordered]@{Success=$true;ProfileId=$committed.Id;ProfileName=$committed.Name;WslName=$committed.WslName;Distro=$Distro;Terminal=$Terminal;Dependencies=$deps;TroubleshootPath=$null}
    } catch {
        $message=$_.Exception.Message;$trouble=Join-Path (Join-Path $env:LOCALAPPDATA 'DistroShelf\Troubleshoot') ("{0}-{1}-{2}" -f $Distro,(Get-Date -Format 'yyyyMMdd-HHmmss'),([guid]::NewGuid().ToString().Substring(0,8)));New-Item -ItemType Directory -Path $trouble -Force|Out-Null
        try{if($wslImported -and $profile){& wsl.exe --terminate $profile.WslName 2>$null|Out-Null}}catch{}
        try{if($attemptRoot-and(Test-Path -LiteralPath $attemptRoot)){Copy-Item -LiteralPath $attemptRoot -Destination (Join-Path $trouble 'Attempt') -Recurse -Force}}catch{}
        try{if($wslImported -and $profile){$wslPath=Join-Path $wslStorage $profile.WslName;if(Test-Path -LiteralPath $wslPath -PathType Container){Copy-Item -LiteralPath $wslPath -Destination (Join-Path $trouble 'Wsl') -Recurse -Force}}}catch{}
        try{if($attemptRoot-and(Test-Path -LiteralPath $attemptRoot)){Remove-Item -LiteralPath $attemptRoot -Recurse -Force -ErrorAction SilentlyContinue}}catch{}
        @("Distro: $Distro","Profile candidate: $($profile.Name)","Wsl name: $($profile.WslName)","Error: $message","Created: $([DateTime]::UtcNow.ToString('o'))")|Set-Content -LiteralPath (Join-Path $trouble 'failure.txt') -Encoding UTF8
        Report-Progress 100 'Installation failed. Attempt preserved in Troubleshoot; no profile was committed.'
        return [pscustomobject][ordered]@{Success=$false;ProfileId=$null;ProfileName=$null;WslName=$null;Distro=$Distro;Error=$message;TroubleshootPath=$trouble}
    }
}
