# DistroShelf for Windows - distro-aware dependency engine
# Profiles remain isolated; Track 0 supplies reusable package artifacts.

. (Join-Path $PSScriptRoot 'ProfileManager.ps1')
. (Join-Path $PSScriptRoot 'DistroTrackManager.ps1')

$script:DistroShelfDependencyPackages=@{
 'Ubuntu'=@{Update='apt-get update';Podman='apt-get install -y podman';Distrobox='apt-get install -y distrobox';Flatpak='apt-get install -y flatpak'}
 'Debian'=@{Update='apt-get update';Podman='apt-get install -y podman';Distrobox='apt-get install -y distrobox';Flatpak='apt-get install -y flatpak'}
 'Fedora'=@{Update='dnf makecache';Podman='dnf install -y podman';Distrobox='dnf install -y distrobox';Flatpak='dnf install -y flatpak'}
 'Arch Linux'=@{Update='pacman -Sy --noconfirm';Podman='pacman -S --noconfirm podman';Distrobox='pacman -S --noconfirm distrobox';Flatpak='pacman -S --noconfirm flatpak'}
 'openSUSE'=@{Update='zypper --non-interactive refresh';Podman='zypper --non-interactive install podman';Distrobox='zypper --non-interactive install distrobox';Flatpak='zypper --non-interactive install flatpak'}
}
$script:DistroShelfFlathubUrl='https://dl.flathub.org/repo/flathub.flatpakrepo'
$script:DistroShelfFlatpakId='com.ranfdev.DistroShelf'

function Get-DistroShelfDependencyPlan { param([Parameter(Mandatory)][string]$Distro)
 if(!$script:DistroShelfDependencyPackages.ContainsKey($Distro)){throw "No dependency plan exists for '$Distro'."};$p=$script:DistroShelfDependencyPackages[$Distro]
 [pscustomobject][ordered]@{Distro=$Distro;PackageManager=(Get-DistroShelfPackageManager $Distro);Steps=@([pscustomobject]@{Name='Package metadata';Command=$p.Update},[pscustomobject]@{Name='Podman';Command=$p.Podman},[pscustomobject]@{Name='Distrobox';Command=$p.Distrobox},[pscustomobject]@{Name='Flatpak';Command=$p.Flatpak},[pscustomobject]@{Name='Flathub';Command="flatpak remote-add --if-not-exists flathub $script:DistroShelfFlathubUrl"},[pscustomobject]@{Name='DistroShelf';Command="flatpak install -y flathub $script:DistroShelfFlatpakId"})}
}
function Invoke-DistroShelfProfileCommand { param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$Command) & wsl.exe --distribution $WslName -- bash -lc $Command;if($LASTEXITCODE-ne 0){throw "Command failed in '$WslName' with exit code $LASTEXITCODE: $Command"} }
function Test-DistroShelfProfileDependency { param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$Command) & wsl.exe --distribution $WslName -- bash -lc "command -v '$Command' >/dev/null 2>&1";return($LASTEXITCODE-eq 0) }
function Test-DistroShelfFlatpakApp { param([Parameter(Mandatory)][string]$WslName) & wsl.exe --distribution $WslName -- bash -lc "flatpak info '$script:DistroShelfFlatpakId' >/dev/null 2>&1";return($LASTEXITCODE-eq 0) }
function Test-DistroShelfFlathub { param([Parameter(Mandatory)][string]$WslName) & wsl.exe --distribution $WslName -- bash -lc "flatpak remotes --columns=name 2>/dev/null|grep -Fx flathub >/dev/null";return($LASTEXITCODE-eq 0) }

function Invoke-DistroShelfDependencyInstall {
 param([Parameter(Mandatory)][pscustomobject]$Profile)
 $d=$Profile.Distro;$plan=Get-DistroShelfDependencyPlan $d
 $trackReady=@{Podman=Test-DistroShelfTrackDependencyReady $d 'Podman';Distrobox=Test-DistroShelfTrackDependencyReady $d 'Distrobox';Flatpak=Test-DistroShelfTrackDependencyReady $d 'Flatpak';DistroShelf=Test-DistroShelfTrackDependencyReady $d 'DistroShelf'}

 # Seed the package-manager caches from Track 0 before doing any installs.
 foreach($c in @('Podman','Distrobox','Flatpak')){if($trackReady[$c]){Invoke-DistroShelfWslCopyCache -WslName $Profile.WslName -Distro $d -Component $c -Mode Seed}}

 $commands=@{}
 if($d -in @('Ubuntu','Debian')){
   $commands.Podman=if($trackReady.Podman){'apt-get install -y --no-download podman'}else{$plan.Steps[1].Command}
   $commands.Distrobox=if($trackReady.Distrobox){'apt-get install -y --no-download distrobox'}else{$plan.Steps[2].Command}
   $commands.Flatpak=if($trackReady.Flatpak){'apt-get install -y --no-download flatpak'}else{$plan.Steps[3].Command}
 } elseif($d -eq 'Fedora'){
   $commands.Podman=if($trackReady.Podman){'dnf -y -C install podman'}else{$plan.Steps[1].Command}
   $commands.Distrobox=if($trackReady.Distrobox){'dnf -y -C install distrobox'}else{$plan.Steps[2].Command}
   $commands.Flatpak=if($trackReady.Flatpak){'dnf -y -C install flatpak'}else{$plan.Steps[3].Command}
 } elseif($d -eq 'Arch Linux'){
   $commands.Podman=$plan.Steps[1].Command;$commands.Distrobox=$plan.Steps[2].Command;$commands.Flatpak=$plan.Steps[3].Command
 } else {
   $commands.Podman=if($trackReady.Podman){'zypper --non-interactive --no-refresh install /var/cache/zypp/packages/*.rpm'}else{$plan.Steps[1].Command}
   $commands.Distrobox=if($trackReady.Distrobox){'zypper --non-interactive --no-refresh install /var/cache/zypp/packages/*.rpm'}else{$plan.Steps[2].Command}
   $commands.Flatpak=if($trackReady.Flatpak){'zypper --non-interactive --no-refresh install /var/cache/zypp/packages/*.rpm'}else{$plan.Steps[3].Command}
 }

 if($d -in @('Ubuntu','Debian') -and -not ($trackReady.Podman -and $trackReady.Distrobox -and $trackReady.Flatpak)){Invoke-DistroShelfProfileCommand $Profile.WslName $plan.Steps[0].Command}
 if($d -eq 'Fedora' -and -not ($trackReady.Podman -and $trackReady.Distrobox -and $trackReady.Flatpak)){Invoke-DistroShelfProfileCommand $Profile.WslName $plan.Steps[0].Command}
 if($d -eq 'Arch Linux' -and -not ($trackReady.Podman -and $trackReady.Distrobox -and $trackReady.Flatpak)){Invoke-DistroShelfProfileCommand $Profile.WslName $plan.Steps[0].Command}
 if($d -eq 'openSUSE' -and -not ($trackReady.Podman -and $trackReady.Distrobox -and $trackReady.Flatpak)){Invoke-DistroShelfProfileCommand $Profile.WslName $plan.Steps[0].Command}

 foreach($component in @('Podman','Distrobox','Flatpak')){
   if($component -eq 'Podman'){$cmd=$commands.Podman}elseif($component -eq 'Distrobox'){$cmd=$commands.Distrobox}else{$cmd=$commands.Flatpak}
   if($component -eq 'Flatpak' -and $d -eq 'openSUSE' -and $trackReady.Flatpak){$cmd='zypper --non-interactive --no-refresh install /var/cache/zypp/packages/*.rpm'}
   Invoke-DistroShelfProfileCommand $Profile.WslName $cmd
   Invoke-DistroShelfWslCopyCache -WslName $Profile.WslName -Distro $d -Component $component -Mode Export
   Set-DistroShelfTrackDependencyReady -Distro $d -Component $component
 }

 Invoke-DistroShelfProfileCommand $Profile.WslName "flatpak remote-add --if-not-exists flathub $script:DistroShelfFlathubUrl"
 if(Test-DistroShelfTrackDependencyReady $d 'DistroShelf'){
   $bundle=Join-Path (Get-DistroShelfTrackArtifactDirectory $d 'DistroShelf') 'DistroShelf.flatpak';$bundleWsl=Get-DistroShelfWslPath (Get-DistroShelfTrackArtifactDirectory $d 'DistroShelf')
   Invoke-DistroShelfProfileCommand $Profile.WslName "if [ -f '$bundleWsl/DistroShelf.flatpak' ]; then flatpak install -y '$bundleWsl/DistroShelf.flatpak'; else flatpak install -y flathub $script:DistroShelfFlatpakId; fi"
 } else {
   Invoke-DistroShelfProfileCommand $Profile.WslName "flatpak install -y flathub $script:DistroShelfFlatpakId"
   if(New-DistroShelfFlatpakBundle -WslName $Profile.WslName -Distro $d){Set-DistroShelfTrackDependencyReady -Distro $d -Component 'DistroShelf'}
 }

 if(!(Test-DistroShelfProfileDependency $Profile.WslName 'podman')){throw "Podman verification failed in '$($Profile.WslName)'."}
 if(!(Test-DistroShelfProfileDependency $Profile.WslName 'distrobox')){throw "Distrobox verification failed in '$($Profile.WslName)'."}
 if(!(Test-DistroShelfProfileDependency $Profile.WslName 'flatpak')){throw "Flatpak verification failed in '$($Profile.WslName)'."}
 if(!(Test-DistroShelfFlathub $Profile.WslName)){throw "Flathub verification failed in '$($Profile.WslName)'."}
 if(!(Test-DistroShelfFlatpakApp $Profile.WslName)){throw "DistroShelf Flatpak verification failed in '$($Profile.WslName)'."}
 [pscustomobject][ordered]@{Profile=$Profile.WslName;Podman=$true;Distrobox=$true;Flatpak=$true;Flathub=$true;DistroShelf=$true}
}
