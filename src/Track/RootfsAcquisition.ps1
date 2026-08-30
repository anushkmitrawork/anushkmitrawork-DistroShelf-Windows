# DistroShelf - rootfs acquisition for a Track attempt
# This function never writes to the committed Track store.
. (Join-Path $PSScriptRoot '..\RootfsProvider.ps1')

function Save-DistroShelfAttemptRootfs {
    param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][string]$DestinationDirectory)
    New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
    $provider=Get-DistroShelfRootfsProvider -Distro $Distro
    $extension=if($provider.Url -match '\.wsl(?:\?|$)'){'.wsl'}else{'.tar'}
    $destination=Join-Path $DestinationDirectory ("{0}-{1}{2}" -f $provider.Name,$provider.Architecture,$extension)

    if(Test-Path -LiteralPath $destination -PathType Leaf){
        $cachedHash=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if($cachedHash -eq $provider.Sha256){
            return [pscustomobject]@{Path=$destination;Sha256=$cachedHash;Verified=$true;Source='attempt-cache'}
        }
        Remove-Item -LiteralPath $destination -Force
    }

    $partial="$destination.partial"
    Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
    try {
        Write-Host "Downloading $($provider.FriendlyName) for Track attempt..."
        Invoke-WebRequest -Uri $provider.Url -OutFile $partial -UseBasicParsing -ErrorAction Stop
        $actual=(Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()
        if($actual -ne $provider.Sha256){
            if($Distro -eq 'Debian' -and (Get-Command Get-DistroShelfStorePackageUrl -ErrorAction SilentlyContinue)){
                Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
                $url=Get-DistroShelfStorePackageUrl -Distro $Distro
                if(!$url){throw "Official Debian rootfs artifact hash mismatch and no Microsoft package fallback is available."}
                $work=Join-Path ([IO.Path]::GetTempPath()) ("DistroShelf-DebianFallback-"+[guid]::NewGuid())
                New-Item -ItemType Directory -Path $work -Force|Out-Null
                try {
                    $pkg=Join-Path $work 'distro.appxbundle'
                    Write-Host 'Acquiring the official Microsoft Debian WSL package for the Track attempt...'
                    Invoke-WebRequest -Uri $url -OutFile $pkg -UseBasicParsing -ErrorAction Stop
                    $tar=Expand-DistroShelfPackageToRootfs -PackagePath $pkg -DestinationDirectory $work
                    Copy-Item -LiteralPath $tar -Destination $destination -Force
                    $hash=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
                    return [pscustomobject]@{Path=$destination;Sha256=$hash;Verified=$true;Source='Microsoft WSL package fallback'}
                } finally {Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}
            }
            throw "SHA-256 mismatch for '$Distro'. Expected $($provider.Sha256), received $actual."
        }
        Move-Item -LiteralPath $partial -Destination $destination -Force
        return [pscustomobject]@{Path=$destination;Sha256=$provider.Sha256;Verified=$true;Source='official WSL artifact'}
    } finally {Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue}
}
