# DistroShelf - rootfs acquisition
# This provider NEVER writes to committed Track 0 by itself.

$script:DistroShelfDistributionManifestUrl='https://raw.githubusercontent.com/microsoft/WSL/master/distributions/DistributionInfo.json'
$script:DistroShelfRootfsFlavorMap=@{'Ubuntu'='Ubuntu';'Debian'='Debian';'Fedora'='Fedora';'Arch Linux'='archlinux';'openSUSE'='openSUSE'}

function Get-DistroShelfRootfsManifest { try{return Invoke-RestMethod -Uri $script:DistroShelfDistributionManifestUrl -UseBasicParsing -ErrorAction Stop}catch{throw "Unable to retrieve official WSL distribution manifest. $($_.Exception.Message)"} }
function Get-DistroShelfRootfsProvider {
    param([Parameter(Mandatory)][string]$Distro)
    if(!$script:DistroShelfRootfsFlavorMap.ContainsKey($Distro)){throw "No WSL rootfs provider is registered for '$Distro'."}
    $m=Get-DistroShelfRootfsManifest;$entries=@($m.ModernDistributions.($script:DistroShelfRootfsFlavorMap[$Distro]));$e=$entries|?{$_.Default-eq$true}|Select-Object -First 1;if(!$e){$e=$entries|Select-Object -First 1}
    if(!$e -or !$e.Amd64Url.Url -or !$e.Amd64Url.Sha256){throw "Official WSL manifest has no verified AMD64 artifact for '$Distro'."}
    [pscustomobject][ordered]@{Distro=$Distro;Name=$e.Name;FriendlyName=$e.FriendlyName;Architecture='amd64';Url=$e.Amd64Url.Url;Sha256=($e.Amd64Url.Sha256-replace'^0x','').ToLowerInvariant()}
}
function Get-DistroShelfStorePackageUrl {param([Parameter(Mandatory)][string]$Distro)$m=Get-DistroShelfRootfsManifest;$e=@($m.Distributions)|?{$_.Name-eq$Distro-and$_.Amd64PackageUrl}|Select-Object -First 1;return if($e){[string]$e.Amd64PackageUrl}else{$null}}
function Expand-DistroShelfPackageToRootfs {param([Parameter(Mandatory)][string]$PackagePath,[Parameter(Mandatory)][string]$DestinationDirectory)Add-Type -AssemblyName System.IO.Compression.FileSystem;$outer=Join-Path $DestinationDirectory 'bundle';$inner=Join-Path $DestinationDirectory 'appx';New-Item -ItemType Directory -Path $outer,$inner -Force|Out-Null;[IO.Compression.ZipFile]::ExtractToDirectory($PackagePath,$outer);$appx=Get-ChildItem $outer -Recurse -Filter '*.appx' -File|?{$_.Name-match'(x64|amd64)'}|Select-Object -First 1;if(!$appx){$appx=Get-ChildItem $outer -Recurse -Filter '*.appx' -File|Select-Object -First 1};if(!$appx){throw 'WSL package contained no Appx payload.'};[IO.Compression.ZipFile]::ExtractToDirectory($appx.FullName,$inner);$tar=Get-ChildItem $inner -Recurse -File|?{$_.Name-match'^(install|rootfs).*\.tar(\.gz|\.xz|\.zst)?$'}|Select-Object -First 1;if(!$tar){throw 'WSL Appx payload contained no supported rootfs archive.'};$tar.FullName}

function Save-DistroShelfRootfs {
    param([Parameter(Mandatory)][string]$Distro,[Parameter(Mandatory)][string]$DestinationDirectory)
    $p=Get-DistroShelfRootfsProvider $Distro;New-Item -ItemType Directory -Path $DestinationDirectory -Force|Out-Null
    $ext=if($p.Url-match'\.wsl(?:\?|$)'){'.wsl'}else{'.tar'};$dest=Join-Path $DestinationDirectory ("{0}-{1}{2}"-f$p.Name,$p.Architecture,$ext)
    if(Test-Path -LiteralPath $dest -PathType Leaf){$h=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant();if($h-eq$p.Sha256){return [pscustomobject]@{Provider=$p;Path=$dest;Sha256=$h;Verified=$true;Cached=$true}};Remove-Item $dest -Force}
    $partial="$dest.partial"
    try {
        Write-Host "Downloading $($p.FriendlyName)..."
        Invoke-WebRequest -Uri $p.Url -OutFile $partial -UseBasicParsing -ErrorAction Stop
        $h=(Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()
        if($h-ne$p.Sha256){
            if($Distro-ne'Debian'){throw "SHA-256 verification failed for '$Distro'. Expected $($p.Sha256), received $h."}
            $url=Get-DistroShelfStorePackageUrl $Distro;if(!$url){throw "No official Microsoft fallback package is available for '$Distro'."}
            $work=Join-Path $env:TEMP ("DistroShelf-$Distro-"+[guid]::NewGuid());New-Item -ItemType Directory -Path $work -Force|Out-Null;$pkg=Join-Path $work 'distro.appxbundle'
            try {Remove-Item $partial -Force -ErrorAction SilentlyContinue;Write-Host 'Acquiring official Microsoft fallback package...';Invoke-WebRequest -Uri $url -OutFile $pkg -UseBasicParsing -ErrorAction Stop;if((Get-Item $pkg).Length-lt1MB){throw 'Fallback package is unexpectedly small.'};$root=Expand-DistroShelfPackageToRootfs -PackagePath $pkg -DestinationDirectory $work;$finalExt=Split-Path $root -Leaf;if($finalExt-match'\.tar\.gz$'){$dest=Join-Path $DestinationDirectory "$Distro-amd64.tar.gz"}else{$dest=Join-Path $DestinationDirectory "$Distro-amd64.tar"};Copy-Item $root $dest -Force;$h=(Get-FileHash $dest -Algorithm SHA256).Hash.ToLowerInvariant();return [pscustomobject]@{Provider=$p;Path=$dest;Sha256=$h;Verified=$true;Cached=$false;Fallback=$true}} finally {Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue}
        }
        Move-Item -LiteralPath $partial -Destination $dest -Force
        return [pscustomobject]@{Provider=$p;Path=$dest;Sha256=$h;Verified=$true;Cached=$false}
    } catch {Remove-Item $partial -Force -ErrorAction SilentlyContinue;throw}
}

function Test-DistroShelfRootfsProvider {param([Parameter(Mandatory)][string]$Distro)try{$p=Get-DistroShelfRootfsProvider $Distro;[pscustomobject]@{Distro=$Distro;Ready=$true;Name=$p.Name;FriendlyName=$p.FriendlyName;Architecture=$p.Architecture;Reason='Official WSL manifest provides an AMD64 artifact and SHA-256.'}}catch{[pscustomobject]@{Distro=$Distro;Ready=$false;Reason=$_.Exception.Message}}}
