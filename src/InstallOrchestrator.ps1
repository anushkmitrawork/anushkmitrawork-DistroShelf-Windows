# DistroShelf for Windows - beginner-friendly installation orchestrator
. (Join-Path $PSScriptRoot 'ProvisionProfile.ps1')
. (Join-Path $PSScriptRoot 'DependencyEngine.ps1')

function Invoke-DistroShelfInstall {
    param(
        [Parameter(Mandatory)][ValidateSet('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')][string]$Distro,
        [string]$Terminal = 'GNOME Console',
        [string]$ProfileId,
        [scriptblock]$OnProgress,
        [scriptblock]$OnStatus
    )
    function Report-Progress([int]$Percent,[string]$Message){if($OnProgress){& $OnProgress $Percent $Message};if($OnStatus){& $OnStatus $Message}}
    Report-Progress 5 "Preparing $Distro profile..."
    $profile=$null
    if($ProfileId){$profile=Get-DistroShelfProfileById -Id $ProfileId;if(!$profile){throw "Selected DistroShelf profile was not found: $ProfileId"};if([string]$profile.Distro -ne $Distro){throw "Selected profile belongs to $($profile.Distro), not $Distro."}}
    else{$profile=New-DistroShelfProfile -Distro $Distro}
    try{
        Set-DistroShelfProfileTerminal -Id $profile.Id -Terminal $Terminal
        Set-DistroShelfProfileStatus -Id $profile.Id -Status 'Preparing rootfs'
        Report-Progress 15 'Preparing and verifying Track 0 rootfs...'
        $artifact=Save-DistroShelfRootfs -Distro $Distro
        Report-Progress 35 "Creating $($profile.Name) as an isolated WSL 2 profile..."
        $profile=Get-DistroShelfProfileById -Id $profile.Id
        $import=Invoke-DistroShelfWslImport -Profile $profile -RootfsPath $artifact.Path -ExpectedSha256 $artifact.Sha256
        Set-DistroShelfProfileStatus -Id $profile.Id -Status 'Installing dependencies'
        Report-Progress 50 'Installing Podman, Distrobox and Flatpak...'
        $deps=Invoke-DistroShelfDependencyInstall -Profile $profile
        Set-DistroShelfProfileStatus -Id $profile.Id -Status 'Ready'
        Report-Progress 100 "Installation complete: $($profile.Name)"
        [pscustomobject][ordered]@{Success=$true;ProfileId=$profile.Id;ProfileName=$profile.Name;WslName=$profile.WslName;Distro=$Distro;Terminal=$Terminal;Dependencies=$deps}
    }catch{
        try{Set-DistroShelfProfileStatus -Id $profile.Id -Status 'Installation failed'}catch{}
        Report-Progress 100 "Installation failed: $($_.Exception.Message)"
        [pscustomobject][ordered]@{Success=$false;ProfileId=$profile.Id;ProfileName=$profile.Name;WslName=$profile.WslName;Distro=$Distro;Error=$_.Exception.Message}
    }
}
