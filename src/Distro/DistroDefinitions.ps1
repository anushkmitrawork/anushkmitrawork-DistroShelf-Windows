# DistroShelf - legacy entry point retained temporarily for callers.
# All distro-specific implementation now lives under src/Distro/<Distro>/Provider.ps1.
# New code should consume Get-DistroShelfProvider from Registry.ps1.

. (Join-Path $PSScriptRoot 'Registry.ps1')

function Get-DistroShelfDistroDefinition {
    param([Parameter(Mandatory)][string]$Distro)
    return Get-DistroShelfProvider -Distro $Distro
}
