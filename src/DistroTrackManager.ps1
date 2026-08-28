# DistroShelf for Windows - per-distro track manager
#
# A Distro track is the reusable installation source/cache for one distro.
# It is deliberately numbered 0 because user-facing profiles start at 1.
#
# Example:
#   tracks\Ubuntu0\Distro\
#   tracks\Ubuntu0\Podman\
#   tracks\Ubuntu0\Distrobox\
#   tracks\Ubuntu0\Flatpak\
#   tracks\Ubuntu0\DistroShelf\
#
# Profiles (Ubuntu1, Ubuntu2, ...) remain independent WSL instances.

$script:DistroShelfTrackRoot = Join-Path $env:LOCALAPPDATA 'DistroShelf\tracks'

function Get-DistroShelfTrackDefinition {
    param([Parameter(Mandatory)][string]$Distro)

    $safeName = switch ($Distro) {
        'Ubuntu'     { 'Ubuntu' }
        'Debian'     { 'Debian' }
        'Fedora'     { 'Fedora' }
        'Arch Linux' { 'ArchLinux' }
        'openSUSE'   { 'openSUSE' }
        default      { throw "Unsupported DistroShelf track: $Distro" }
    }

    return [pscustomobject][ordered]@{
        Distro = $Distro
        Name = "${safeName}0"
        Root = Join-Path $script:DistroShelfTrackRoot "${safeName}0"
    }
}

function Initialize-DistroShelfTrack {
    param([Parameter(Mandatory)][string]$Distro)

    $track = Get-DistroShelfTrackDefinition $Distro
    $directories = @(
        $track.Root
        (Join-Path $track.Root 'Distro')
        (Join-Path $track.Root 'Podman')
        (Join-Path $track.Root 'Distrobox')
        (Join-Path $track.Root 'Flatpak')
        (Join-Path $track.Root 'DistroShelf')
        (Join-Path $track.Root 'metadata')
    )

    foreach ($directory in $directories) {
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
    }

    return $track
}

function Get-DistroShelfTrackArtifactDirectory {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][ValidateSet('Distro','Podman','Distrobox','Flatpak','DistroShelf','metadata')][string]$Component
    )

    $track = Initialize-DistroShelfTrack $Distro
    return Join-Path $track.Root $Component
}

function Get-DistroShelfTrackManifestPath {
    param([Parameter(Mandatory)][string]$Distro)
    $track = Initialize-DistroShelfTrack $Distro
    return Join-Path $track.Root 'metadata\track.json'
}

function Get-DistroShelfTrackManifest {
    param([Parameter(Mandatory)][string]$Distro)

    $path = Get-DistroShelfTrackManifestPath $Distro
    if (-not (Test-Path -LiteralPath $path)) { return $null }

    try {
        return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Set-DistroShelfTrackManifest {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][object]$Manifest
    )

    $path = Get-DistroShelfTrackManifestPath $Distro
    $Manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Test-DistroShelfTrackDistroArtifact {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$Sha256,
        [Parameter(Mandatory)][string]$FileName
    )

    $directory = Get-DistroShelfTrackArtifactDirectory -Distro $Distro -Component 'Distro'
    $path = Join-Path $directory $FileName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }

    try {
        return ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $Sha256.ToLowerInvariant())
    } catch {
        return $false
    }
}

function Write-DistroShelfTrackReady {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$RootfsFile,
        [Parameter(Mandatory)][string]$RootfsSha256
    )

    Set-DistroShelfTrackManifest -Distro $Distro -Manifest ([pscustomobject][ordered]@{
        SchemaVersion = 1
        Distro = $Distro
        Track = (Get-DistroShelfTrackDefinition $Distro).Name
        Rootfs = [pscustomobject]@{
            File = $RootfsFile
            Sha256 = $RootfsSha256
            Verified = $true
        }
        Dependencies = [pscustomobject]@{
            Podman = $false
            Distrobox = $false
            Flatpak = $false
            DistroShelf = $false
        }
        CreatedAt = [DateTime]::UtcNow.ToString('o')
    })
}
