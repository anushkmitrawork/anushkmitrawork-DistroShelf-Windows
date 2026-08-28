# DistroShelf for Windows - beginner-friendly installation orchestrator

. (Join-Path $PSScriptRoot 'ProvisionProfile.ps1')
. (Join-Path $PSScriptRoot 'DependencyEngine.ps1')

function Invoke-DistroShelfInstall {
    param(
        [Parameter(Mandatory)][ValidateSet('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')][string]$Distro,
        [string]$Terminal = 'GNOME Console',
        [scriptblock]$OnProgress,
        [scriptblock]$OnStatus
    )

    function Report-Progress([int]$Percent, [string]$Message) {
        if ($OnProgress) { & $OnProgress $Percent $Message }
        if ($OnStatus) { & $OnStatus $Message }
    }

    Report-Progress 5 "Creating $Distro profile..."
    $profile = New-DistroShelfProfile -Distro $Distro

    try {
        $profiles = @(Get-DistroShelfProfiles)
        foreach ($item in $profiles) {
            if ($item.Id -eq $profile.Id) {
                $item | Add-Member -NotePropertyName Terminal -NotePropertyValue $Terminal -Force
                $item.Status = 'Preparing rootfs'
                break
            }
        }
        Save-DistroShelfProfiles $profiles

        Report-Progress 15 'Downloading and verifying Linux rootfs...'
        $artifact = Save-DistroShelfRootfs -Distro $Distro -DestinationDirectory (Join-Path $env:LOCALAPPDATA 'DistroShelf\cache')

        Report-Progress 35 "Creating $($profile.Name) as an isolated WSL 2 profile..."
        $import = Invoke-DistroShelfWslImport -Profile $profile -RootfsPath $artifact.Path -ExpectedSha256 $artifact.Sha256

        Set-DistroShelfProfileStatus -Id $profile.Id -Status 'Installing dependencies'
        Report-Progress 50 'Installing Podman, Distrobox and Flatpak...'
        $deps = Invoke-DistroShelfDependencyInstall -Profile $profile

        Set-DistroShelfProfileStatus -Id $profile.Id -Status 'Ready'
        Report-Progress 100 "Installation complete: $($profile.Name)"

        return [pscustomobject][ordered]@{
            Success = $true
            ProfileId = $profile.Id
            ProfileName = $profile.Name
            WslName = $profile.WslName
            Distro = $Distro
            Terminal = $Terminal
            Dependencies = $deps
        }
    } catch {
        try { Set-DistroShelfProfileStatus -Id $profile.Id -Status 'Installation failed' } catch {}
        Report-Progress 100 "Installation failed: $($_.Exception.Message)"
        return [pscustomobject][ordered]@{
            Success = $false
            ProfileId = $profile.Id
            ProfileName = $profile.Name
            WslName = $profile.WslName
            Distro = $Distro
            Error = $_.Exception.Message
        }
    }
}
