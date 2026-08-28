# DistroShelf for Windows - rootfs provider definitions
#
# This module defines how supported distributions will be provisioned. It does
# not download or import anything by itself. URLs/checksums must be verified
# against official distribution release metadata before enabling downloads.

$script:DistroShelfRootfsProviders = [ordered]@{
    'Ubuntu' = [ordered]@{
        Architecture = 'amd64'
        Provisioning = 'wsl-import'
        SourcePolicy = 'official-release-artifact-required'
    }
    'Debian' = [ordered]@{
        Architecture = 'amd64'
        Provisioning = 'wsl-import'
        SourcePolicy = 'official-release-artifact-required'
    }
    'Fedora' = [ordered]@{
        Architecture = 'amd64'
        Provisioning = 'wsl-import'
        SourcePolicy = 'official-release-artifact-required'
    }
    'Arch Linux' = [ordered]@{
        Architecture = 'amd64'
        Provisioning = 'wsl-import'
        SourcePolicy = 'official-release-artifact-required'
    }
    'openSUSE' = [ordered]@{
        Architecture = 'amd64'
        Provisioning = 'wsl-import'
        SourcePolicy = 'official-release-artifact-required'
    }
}

function Get-DistroShelfRootfsProvider {
    param([Parameter(Mandatory)][string]$Distro)

    if (-not $script:DistroShelfRootfsProviders.Contains($Distro)) {
        throw "No rootfs provider is registered for '$Distro'."
    }

    return [pscustomobject]$script:DistroShelfRootfsProviders[$Distro]
}

function Test-DistroShelfRootfsProvider {
    param([Parameter(Mandatory)][string]$Distro)

    try {
        $provider = Get-DistroShelfRootfsProvider $Distro
        return [pscustomobject]@{
            Distro = $Distro
            Ready = $false
            Reason = "Official release artifact URL and checksum still need to be verified before downloads are enabled."
            Architecture = $provider.Architecture
        }
    } catch {
        return [pscustomobject]@{
            Distro = $Distro
            Ready = $false
            Reason = $_.Exception.Message
            Architecture = $null
        }
    }
}
