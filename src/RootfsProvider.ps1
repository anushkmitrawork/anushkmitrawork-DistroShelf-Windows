# DistroShelf for Windows - verified WSL rootfs provider
# Rootfs artifacts live once in the selected distro's Track 0.

. (Join-Path $PSScriptRoot 'DistroTrackManager.ps1')

$script:DistroShelfDistributionManifestUrl = 'https://raw.githubusercontent.com/microsoft/WSL/master/distributions/DistributionInfo.json'
$script:DistroShelfRootfsFlavorMap = @{
    'Ubuntu'='Ubuntu'; 'Debian'='Debian'; 'Fedora'='Fedora'; 'Arch Linux'='archlinux'; 'openSUSE'='openSUSE'
}

function Get-DistroShelfRootfsManifest {
    try { return Invoke-RestMethod -Uri $script:DistroShelfDistributionManifestUrl -UseBasicParsing -ErrorAction Stop }
    catch { throw "Unable to retrieve the official WSL distribution manifest. $($_.Exception.Message)" }
}

function Get-DistroShelfRootfsProvider {
    param([Parameter(Mandatory)][string]$Distro)
    if(!$script:DistroShelfRootfsFlavorMap.ContainsKey($Distro)){throw "No WSL rootfs provider is registered for '$Distro'."}
    $manifest=Get-DistroShelfRootfsManifest
    $flavor=$script:DistroShelfRootfsFlavorMap[$Distro]
    $entries=@($manifest.ModernDistributions.$flavor)
    if(!$entries){throw "The official WSL manifest contains no ModernDistribution entry for '$Distro'."}
    $entry=$entries|Where-Object{$_.Default -eq $true}|Select-Object -First 1
    if(!$entry){$entry=$entries[0]}
    if(!$entry.Amd64Url.Url -or !$entry.Amd64Url.Sha256){throw "The official WSL manifest does not provide an AMD64 artifact and SHA-256 for '$Distro'."}
    [pscustomobject][ordered]@{
        Distro=$Distro; Name=$entry.Name; FriendlyName=$entry.FriendlyName; Architecture='amd64'
        Url=$entry.Amd64Url.Url; Sha256=($entry.Amd64Url.Sha256 -replace '^0x','').ToLowerInvariant()
    }
}

function Get-DistroShelfLegacyRootfsPath {
    param([Parameter(Mandatory)][string]$Distro)
    $legacy=Join-Path $env:LOCALAPPDATA 'DistroShelf\cache'
    switch($Distro){
        'Ubuntu' { return (Join-Path $legacy 'Ubuntu-amd64.wsl') }
        'Debian' { return (Join-Path $legacy 'Debian-amd64.wsl') }
        'Fedora' { return (Join-Path $legacy 'Fedora-amd64.wsl') }
        'Arch Linux' { return (Join-Path $legacy 'archlinux-amd64.wsl') }
        'openSUSE' { return (Join-Path $legacy 'openSUSE-amd64.wsl') }
    }
}

function Get-DistroShelfStorePackageUrl {
    param([Parameter(Mandatory)][string]$Distro)
    $manifest=Get-DistroShelfRootfsManifest
    $entry=@($manifest.Distributions)|Where-Object{$_.Name -eq $Distro -and $_.Amd64PackageUrl}|Select-Object -First 1
    if($entry){return [string]$entry.Amd64PackageUrl}
    return $null
}

function Expand-DistroShelfDebianStorePackage {
    param([Parameter(Mandatory)][string]$PackagePath,[Parameter(Mandatory)][string]$DestinationDirectory)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $outer=Join-Path $DestinationDirectory 'bundle'
    $inner=Join-Path $DestinationDirectory 'appx'
    New-Item -ItemType Directory -Path $outer,$inner -Force | Out-Null
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($PackagePath,$outer)
        $appx=Get-ChildItem $outer -Recurse -Filter '*.appx' -File | Select-Object -First 1
        if(!$appx){throw 'The Debian AppxBundle did not contain an x64 Appx package.'}
        [System.IO.Compression.ZipFile]::ExtractToDirectory($appx.FullName,$inner)
        $tar=Get-ChildItem $inner -Recurse -File | Where-Object{$_.Name -match '^(install|rootfs).*\.tar(\.gz|\.xz|\.zst)?$'} | Select-Object -First 1
        if(!$tar){throw 'The Debian Appx package did not contain a WSL root filesystem archive.'}
        return $tar.FullName
    } catch {
        throw "Unable to extract the official Debian WSL package. $($_.Exception.Message)"
    }
}

function Save-DistroShelfDebianFallbackRootfs {
    param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][string]$TrackDestination)
    $packageUrl=Get-DistroShelfStorePackageUrl $Distro
    if(!$packageUrl){throw "No official Microsoft package URL is available for '$Distro'."}
    $work=Join-Path ([System.IO.Path]::GetTempPath()) ("DistroShelf-{0}-{1}" -f $Distro,(Get-Random))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $package=Join-Path $work 'distro.appxbundle'
    try {
        Write-Host "The official WSL rootfs endpoint did not return a valid image. Acquiring the official Microsoft package instead..."
        Invoke-WebRequest -Uri $packageUrl -OutFile $package -UseBasicParsing -ErrorAction Stop
        $rootfs=Expand-DistroShelfDebianStorePackage -PackagePath $package -DestinationDirectory $work
        Copy-Item -LiteralPath $rootfs -Destination $TrackDestination -Force
        $hash=(Get-FileHash -LiteralPath $TrackDestination -Algorithm SHA256).Hash.ToLowerInvariant()
        return [pscustomobject][ordered]@{Path=$TrackDestination;Sha256=$hash;Source='Microsoft WSL package'}
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Save-DistroShelfRootfs {
    param([Parameter(Mandatory)][string]$Distro,[string]$DestinationDirectory)
    $provider=Get-DistroShelfRootfsProvider $Distro
    $track=Initialize-DistroShelfTrack $Distro
    $extension=if($provider.Url -match '\.wsl(?:\?|$)'){'.wsl'}else{'.tar'}
    $fileName="{0}-{1}{2}" -f $provider.Name,$provider.Architecture,$extension
    $trackDestination=Join-Path (Get-DistroShelfTrackArtifactDirectory $Distro 'Distro') $fileName

    # Existing Track 0 artifact: verify it and reuse it without downloading.
    if(Test-Path -LiteralPath $trackDestination -PathType Leaf){
        try {
            $hash=(Get-FileHash -LiteralPath $trackDestination -Algorithm SHA256).Hash.ToLowerInvariant()
            if($hash -eq $provider.Sha256){
                Write-DistroShelfTrackManifest -Distro $Distro -RootfsFile $fileName -RootfsSha256 $hash
                return [pscustomobject][ordered]@{Provider=$provider;Path=$trackDestination;Sha256=$hash;Verified=$true;Cached=$true}
            }
        } catch {}
        Remove-Item -LiteralPath $trackDestination -Force -ErrorAction SilentlyContinue
    }

    # Migrate a previously downloaded legacy cache artifact when its hash matches.
    $legacy=Get-DistroShelfLegacyRootfsPath $Distro
    if($legacy -and (Test-Path -LiteralPath $legacy -PathType Leaf)){
        try {
            $hash=(Get-FileHash -LiteralPath $legacy -Algorithm SHA256).Hash.ToLowerInvariant()
            if($hash -eq $provider.Sha256){
                Copy-Item -LiteralPath $legacy -Destination $trackDestination -Force
                Write-DistroShelfTrackManifest -Distro $Distro -RootfsFile $fileName -RootfsSha256 $hash
                return [pscustomobject][ordered]@{Provider=$provider;Path=$trackDestination;Sha256=$hash;Verified=$true;Cached=$true;Migrated=$true}
            }
        } catch {}
    }

    Write-Host "Downloading $($provider.FriendlyName)..."
    $partial="$trackDestination.partial"
    Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
    try {
        Invoke-WebRequest -Uri $provider.Url -OutFile $partial -UseBasicParsing -ErrorAction Stop
        $actualHash=(Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()
        if($actualHash -ne $provider.Sha256){
            # Debian's current WSL manifest points at a Salsa CI artifact endpoint which can
            # return a small HTML response even with HTTP 200. Do not accept that response;
            # fall back to Debian's official Microsoft WSL package and extract its rootfs.
            if($Distro -eq 'Debian'){
                Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
                $fallback=Save-DistroShelfDebianFallbackRootfs -Distro $Distro -TrackDestination $trackDestination
                Write-DistroShelfTrackManifest -Distro $Distro -RootfsFile ([System.IO.Path]::GetFileName($trackDestination)) -RootfsSha256 $fallback.Sha256
                return [pscustomobject][ordered]@{Provider=$provider;Path=$fallback.Path;Sha256=$fallback.Sha256;Verified=$true;Cached=$false;Migrated=$false;Fallback=$true}
            }
            throw "SHA-256 verification failed for '$Distro'. Expected $($provider.Sha256), received $actualHash."
        }
        Move-Item -LiteralPath $partial -Destination $trackDestination -Force
    } catch {
        Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        throw
    }

    Write-DistroShelfTrackManifest -Distro $Distro -RootfsFile $fileName -RootfsSha256 $provider.Sha256
    [pscustomobject][ordered]@{Provider=$provider;Path=$trackDestination;Sha256=$provider.Sha256;Verified=$true;Cached=$false;Migrated=$false}
}

function Test-DistroShelfRootfsProvider {
    param([Parameter(Mandatory)][string]$Distro)
    try{$p=Get-DistroShelfRootfsProvider $Distro;[pscustomobject]@{Distro=$Distro;Ready=$true;Name=$p.Name;FriendlyName=$p.FriendlyName;Architecture=$p.Architecture;Reason='Official WSL manifest provides an AMD64 artifact and SHA-256.'}}catch{[pscustomobject]@{Distro=$Distro;Ready=$false;Name=$null;FriendlyName=$null;Architecture=$null;Reason=$_.Exception.Message}}
}
