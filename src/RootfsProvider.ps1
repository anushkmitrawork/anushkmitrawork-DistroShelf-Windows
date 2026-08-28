# DistroShelf for Windows - verified WSL rootfs provider
#
# WSL publishes a distribution manifest containing artifact URLs and SHA-256
# checksums. We resolve it at install time instead of hard-coding versions.
# Downloads are verified before they can be imported.

$script:DistroShelfDistributionManifestUrl = 'https://raw.githubusercontent.com/microsoft/WSL/master/distributions/DistributionInfo.json'

$script:DistroShelfRootfsFlavorMap = @{
    'Ubuntu' = 'Ubuntu'
    'Debian' = 'Debian'
    'Fedora' = 'Fedora'
    'Arch Linux' = 'archlinux'
    'openSUSE' = 'openSUSE'
}

function Get-DistroShelfRootfsManifest {
    try {
        return Invoke-RestMethod -Uri $script:DistroShelfDistributionManifestUrl -UseBasicParsing -ErrorAction Stop
    } catch {
        throw "Unable to retrieve the official WSL distribution manifest. $($_.Exception.Message)"
    }
}

function Get-DistroShelfRootfsProvider {
    param([Parameter(Mandatory)][string]$Distro)

    if (-not $script:DistroShelfRootfsFlavorMap.ContainsKey($Distro)) {
        throw "No WSL rootfs provider is registered for '$Distro'."
    }

    $manifest = Get-DistroShelfRootfsManifest
    $flavor = $script:DistroShelfRootfsFlavorMap[$Distro]
    $entries = @($manifest.ModernDistributions.$flavor)

    if (-not $entries -or $entries.Count -eq 0) {
        throw "The official WSL manifest contains no ModernDistribution entry for '$Distro'."
    }

    $entry = $entries | Where-Object { $_.Default -eq $true } | Select-Object -First 1
    if (-not $entry) { $entry = $entries[0] }

    if (-not $entry.Amd64Url.Url -or -not $entry.Amd64Url.Sha256) {
        throw "The official WSL manifest does not provide an AMD64 artifact and SHA-256 for '$Distro'."
    }

    return [pscustomobject][ordered]@{
        Distro = $Distro
        Name = $entry.Name
        FriendlyName = $entry.FriendlyName
        Architecture = 'amd64'
        Url = $entry.Amd64Url.Url
        Sha256 = ($entry.Amd64Url.Sha256 -replace '^0x','').ToLowerInvariant()
    }
}

function Save-DistroShelfRootfs {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$DestinationDirectory
    )

    $provider = Get-DistroShelfRootfsProvider $Distro

    if (-not (Test-Path -LiteralPath $DestinationDirectory)) {
        New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
    }

    $extension = if ($provider.Url -match '\.wsl(?:\?|$)') { '.wsl' } else { '.tar' }
    $fileName = "{0}-{1}{2}" -f $provider.Name, $provider.Architecture, $extension
    $destination = Join-Path $DestinationDirectory $fileName

    Write-Host "Downloading $($provider.FriendlyName)..."
    Invoke-WebRequest -Uri $provider.Url -OutFile $destination -UseBasicParsing -ErrorAction Stop

    $actualHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $provider.Sha256) {
        Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
        throw "SHA-256 verification failed for '$Distro'. Expected $($provider.Sha256), received $actualHash."
    }

    return [pscustomobject][ordered]@{
        Provider = $provider
        Path = $destination
        Sha256 = $actualHash
        Verified = $true
    }
}

function Test-DistroShelfRootfsProvider {
    param([Parameter(Mandatory)][string]$Distro)

    try {
        $provider = Get-DistroShelfRootfsProvider $Distro
        return [pscustomobject]@{
            Distro = $Distro
            Ready = $true
            Name = $provider.Name
            FriendlyName = $provider.FriendlyName
            Architecture = $provider.Architecture
            Reason = 'Official WSL manifest provides an AMD64 artifact and SHA-256.'
        }
    } catch {
        return [pscustomobject]@{
            Distro = $Distro
            Ready = $false
            Name = $null
            FriendlyName = $null
            Architecture = $null
            Reason = $_.Exception.Message
        }
    }
}
