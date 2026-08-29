# DistroShelf for Windows - profile provisioning pipeline
. (Join-Path $PSScriptRoot 'ProfileManager.ps1')
. (Join-Path $PSScriptRoot 'RootfsProvider.ps1')
. (Join-Path $PSScriptRoot 'WslImporter.ps1')
function Invoke-DistroShelfProfileProvisioning {
    param([Parameter(Mandatory)][ValidateSet('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')][string]$Distro,[string]$Terminal='GNOME Console',[string]$CacheDirectory=(Join-Path $env:LOCALAPPDATA 'DistroShelf\cache'))
    $profile=New-DistroShelfProfileCandidate -Distro $Distro
    $artifact=$null
    try{$artifact=Save-DistroShelfRootfs -Distro $Distro -DestinationDirectory $CacheDirectory;$result=Invoke-DistroShelfWslImport -Profile $profile -RootfsPath $artifact.Path -ExpectedSha256 $artifact.Sha256;return [pscustomobject][ordered]@{ProfileId=$profile.Id;ProfileName=$profile.Name;Distro=$profile.Distro;WslName=$profile.WslName;Terminal=$Terminal;RootfsVerified=$artifact.Verified;Imported=$result.Imported;Status='WSL 2 profile ready for dependencies';Committed=$false}}catch{throw}
}
