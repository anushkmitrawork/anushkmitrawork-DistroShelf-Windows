# DistroShelf for Windows - profile installation planning
$script:ProfileInstallerRoot=Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:ProfileInstallerRoot 'ProfileManager.ps1')
function New-DistroShelfInstallationProfile {
    param([Parameter(Mandatory)][ValidateSet('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')][string]$Distro,[string]$Terminal='GNOME Console')
    $profile=New-DistroShelfProfileCandidate -Distro $Distro
    $profile|Add-Member -NotePropertyName Terminal -NotePropertyValue $Terminal -Force
    return $profile
}
function Test-DistroShelfProfileNameAvailable {param([Parameter(Mandatory)][string]$WslName) return -not @((Get-DistroShelfProfiles)|?{[string]$_.Status-eq'Ready'}|Select-Object -ExpandProperty WslName|?{$_ -eq $WslName})}
function Get-DistroShelfInstallPlan {
    param([Parameter(Mandatory)][string]$Distro)
    $definition=Get-DistroShelfProfileDefinition $Distro
    return [pscustomobject][ordered]@{Distro=$Distro;PackageManager=$definition.PackageManager;Steps=@('Prepare isolated attempt','Verify WSL 2','Acquire and verify Track 0 rootfs','Install Podman','Install Distrobox','Install Flatpak','Configure Flathub','Install DistroShelf','Configure preferred terminal','Verify complete environment','Commit Track 0 and profile')}
}
