# DistroShelf for Windows - profile provisioning pipeline
#
# Orchestrates: create profile -> download/verify rootfs -> WSL2 import.
# Dependency installation remains a separate stage.

. (Join-Path $PSScriptRoot 'ProfileManager.ps1')
. (Join-Path $PSScriptRoot 'RootfsProvider.ps1')
. (Join-Path $PSScriptRoot 'WslImporter.ps1')

function Invoke-DistroShelfProfileProvisioning {
    param(
        [Parameter(Mandatory)][ValidateSet('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')][string]$Distro,
        [string]$Terminal = 'GNOME Console',
        [string]$CacheDirectory = (Join-Path $env:LOCALAPPDATA 'DistroShelf\cache')
    )

    $profile = New-DistroShelfProfile -Distro $Distro
    $profiles = @(Get-DistroShelfProfiles)
    foreach ($item in $profiles) {
        if ($item.Id -eq $profile.Id) {
            $item.Status = 'Preparing rootfs'
            $item | Add-Member -NotePropertyName Terminal -NotePropertyValue $Terminal -Force
            break
        }
    }
    Save-DistroShelfProfiles $profiles

    try {
        $artifact = Save-DistroShelfRootfs -Distro $Distro -DestinationDirectory $CacheDirectory
        Set-DistroShelfProfileStatus -Id $profile.Id -Status 'Importing WSL 2'

        $result = Invoke-DistroShelfWslImport `
            -Profile $profile `
            -RootfsPath $artifact.Path `
            -ExpectedSha256 $artifact.Sha256

        Set-DistroShelfProfileStatus -Id $profile.Id -Status 'WSL 2 profile ready for dependencies'
        return [pscustomobject][ordered]@{
            ProfileId = $profile.Id
            ProfileName = $profile.Name
            Distro = $profile.Distro
            WslName = $profile.WslName
            Terminal = $Terminal
            RootfsVerified = $artifact.Verified
            Imported = $result.Imported
            Status = 'WSL 2 profile ready for dependencies'
        }
    } catch {
        Set-DistroShelfProfileStatus -Id $profile.Id -Status 'Provisioning failed'
        throw
    }
}
