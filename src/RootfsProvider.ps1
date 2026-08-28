# DistroShelf for Windows - verified WSL rootfs provider
# Rootfs artifacts are stored once in the selected distro's Track 0.

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
    $manifest=Get-DistroShelfRootfsManifest;$flavor=$script:DistroShelfRootfsFlavorMap[$Distro];$entries=@($manifest.ModernDistributions.$flavor)
    if(!$entries){throw "The official WSL manifest contains no ModernDistribution entry for '$Distro'."}
    $entry=$entries|Where-Object{$_.Default-eq $true}|Select-Object -First 1;if(!$entry){$entry=$entries[0]}
    if(!$entry.Amd64Url.Url-or !$entry.Amd64Url.Sha256){throw "The official WSL manifest does not provide an AMD64 artifact and SHA-256 for '$Distro'."}
    [pscustomobject][ordered]@{Distro=$Distro;Name=$entry.Name;FriendlyName=$entry.FriendlyName;Architecture='amd64';Url=$entry.Amd64Url.Url;Sha256=($entry.Amd64Url.Sha256-replace '^0x','').ToLowerInvariant()}
}

function Save-DistroShelfRootfs {
    param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][string]$DestinationDirectory)
    $provider=Get-DistroShelfRootfsProvider $Distro
    $track=Initialize-DistroShelfTrack $Distro
    $extension=if($provider.Url-match '\.wsl(?:\?|$)'){'.wsl'}else{'.tar'}
    $fileName="{0}-{1}{2}"-f $provider.Name,$provider.Architecture,$extension
    $trackDestination=Join-Path (Get-DistroShelfTrackArtifactDirectory $Distro 'Distro') $fileName

    if(Test-Path -LiteralPath $trackDestination -PathType Leaf){
        try{
            $hash=(Get-FileHash -LiteralPath $trackDestination -Algorithm SHA256).Hash.ToLowerInvariant()
            if($hash-eq $provider.Sha256){
                if($DestinationDirectory-ne (Split-Path $trackDestination -Parent)){
                    if(!(Test-Path -LiteralPath $DestinationDirectory)){New-Item -ItemType Directory -Path $DestinationDirectory -Force|Out-Null}
                }
                return [pscustomobject][ordered]@{Provider=$provider;Path=$trackDestination;Sha256=$hash;Verified=$true;Cached=$true}
            }
        }catch{}
        Remove-Item -LiteralPath $trackDestination -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Downloading $($provider.FriendlyName)..."
    Invoke-WebRequest -Uri $provider.Url -OutFile $trackDestination -UseBasicParsing -ErrorAction Stop
    $actualHash=(Get-FileHash -LiteralPath $trackDestination -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actualHash-ne $provider.Sha256){Remove-Item -LiteralPath $trackDestination -Force -ErrorAction SilentlyContinue;throw "SHA-256 verification failed for '$Distro'. Expected $($provider.Sha256), received $actualHash."}

    Write-DistroShelfTrackManifest -Distro $Distro -RootfsFile $fileName -RootfsSha256 $actualHash
    [pscustomobject][ordered]@{Provider=$provider;Path=$trackDestination;Sha256=$actualHash;Verified=$true;Cached=$false}
}

function Test-DistroShelfRootfsProvider {
    param([Parameter(Mandatory)][string]$Distro)
    try{$p=Get-DistroShelfRootfsProvider $Distro;[pscustomobject]@{Distro=$Distro;Ready=$true;Name=$p.Name;FriendlyName=$p.FriendlyName;Architecture=$p.Architecture;Reason='Official WSL manifest provides an AMD64 artifact and SHA-256.'}}catch{[pscustomobject]@{Distro=$Distro;Ready=$false;Name=$null;FriendlyName=$null;Architecture=$null;Reason=$_.Exception.Message}}
}
