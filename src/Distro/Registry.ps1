# DistroShelf - distro provider registry

. (Join-Path $PSScriptRoot 'ProviderContract.ps1')
. (Join-Path $PSScriptRoot 'Ubuntu\Provider.ps1')
. (Join-Path $PSScriptRoot 'Debian\Provider.ps1')
. (Join-Path $PSScriptRoot 'Fedora\Provider.ps1')
. (Join-Path $PSScriptRoot 'ArchLinux\Provider.ps1')
. (Join-Path $PSScriptRoot 'openSUSE\Provider.ps1')

$script:DistroShelfProviders = [ordered]@{
    'Ubuntu' = (New-DistroShelfUbuntuProvider)
    'Debian' = (New-DistroShelfDebianProvider)
    'Fedora' = (New-DistroShelfFedoraProvider)
    'Arch Linux' = (New-DistroShelfArchLinuxProvider)
    'openSUSE' = (New-DistroShelfOpenSUSEProvider)
}

function Get-DistroShelfProvider {
    param([Parameter(Mandatory)][string]$Distro)
    if(!$script:DistroShelfProviders.Contains($Distro)){throw "Unsupported distro provider: $Distro"}
    $provider=$script:DistroShelfProviders[$Distro]
    $validation=Test-DistroShelfProviderContract -Provider $provider
    if(!$validation.Valid){throw "Provider '$Distro' is invalid: $($validation.Errors -join '; ')"}
    return $provider
}
