# DistroShelf - committed Profile registry
# Profiles are persistent only after a successful end-to-end acceptance test.

$script:DistroShelfProfileRoot = Join-Path $env:LOCALAPPDATA 'DistroShelf'
$script:DistroShelfProfileFile = Join-Path $script:DistroShelfProfileRoot 'profiles.json'
$script:DistroShelfProfileLock = Join-Path $script:DistroShelfProfileRoot 'profiles.lock'

$script:DistroShelfProfileDefinitions = @{
    'Ubuntu'      = @{ WslBaseName='Ubuntu'; PackageManager='apt' }
    'Debian'      = @{ WslBaseName='Debian'; PackageManager='apt' }
    'Fedora'      = @{ WslBaseName='Fedora'; PackageManager='dnf' }
    'Arch Linux'  = @{ WslBaseName='Arch'; PackageManager='pacman' }
    'openSUSE'    = @{ WslBaseName='openSUSE'; PackageManager='zypper' }
}

function Initialize-DistroShelfProfileStore {
    if (!(Test-Path -LiteralPath $script:DistroShelfProfileRoot)) { New-Item -ItemType Directory -Path $script:DistroShelfProfileRoot -Force | Out-Null }
    if (!(Test-Path -LiteralPath $script:DistroShelfProfileFile)) { '[]' | Set-Content -LiteralPath $script:DistroShelfProfileFile -Encoding UTF8 }
}

function Get-DistroShelfProfiles {
    Initialize-DistroShelfProfileStore
    $raw=Get-Content -LiteralPath $script:DistroShelfProfileFile -Raw -ErrorAction Stop
    if([string]::IsNullOrWhiteSpace($raw)){return @()}
    $v=$raw|ConvertFrom-Json
    return @($v)
}
function Save-DistroShelfProfiles {
    param([object[]]$Profiles)
    Initialize-DistroShelfProfileStore
    $tmp="$($script:DistroShelfProfileFile).tmp"
    @($Profiles)|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $script:DistroShelfProfileFile -Force
}
function Get-DistroShelfProfileDefinition { param([Parameter(Mandatory)][string]$Distro) if(!$script:DistroShelfProfileDefinitions.ContainsKey($Distro)){throw "Unsupported WSL distro: $Distro"};$script:DistroShelfProfileDefinitions[$Distro] }
function Get-DistroShelfNextCommittedProfileNumber { param([Parameter(Mandatory)][string]$Distro)
    $def=Get-DistroShelfProfileDefinition $Distro;$prefix="DistroShelf-$($def.WslBaseName)";$n=0
    foreach($p in Get-DistroShelfProfiles){if([string]$p.Status -ne 'Ready'){continue};if([string]$p.WslName -match "^$([regex]::Escape($prefix))([0-9]+)$"){$x=[int]$Matches[1];if($x -gt $n){$n=$x}}};$n+1
}
function New-DistroShelfProfileCandidate { param([Parameter(Mandatory)][ValidateSet('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')][string]$Distro)
    $d=Get-DistroShelfProfileDefinition $Distro;$num=Get-DistroShelfNextCommittedProfileNumber $Distro
    [pscustomobject][ordered]@{Id=[guid]::NewGuid().ToString();Name="$($d.WslBaseName)$num";Distro=$Distro;WslName="DistroShelf-$($d.WslBaseName)$num";PackageManager=$d.PackageManager;Status='Candidate';CreatedAt=[DateTime]::UtcNow.ToString('o');Dependencies=[ordered]@{Wsl2=$false;Podman=$false;Distrobox=$false;Flatpak=$false;Flathub=$false;DistroShelf=$false}}
}
function Commit-DistroShelfProfile {
    param([Parameter(Mandatory)][pscustomobject]$Candidate,[string]$Terminal='GNOME Console',[Parameter(Mandatory)][string]$ProfileHash)
    Initialize-DistroShelfProfileStore
    $profiles=@(Get-DistroShelfProfiles)
    if(@($profiles|?{[string]$_.WslName -eq [string]$Candidate.WslName -and [string]$_.Status -eq 'Ready'}).Count){throw "Committed profile already exists: $($Candidate.WslName)"}
    $record=[ordered]@{Id=$Candidate.Id;Name=$Candidate.Name;Distro=$Candidate.Distro;WslName=$Candidate.WslName;PackageManager=$Candidate.PackageManager;Status='Ready';CreatedAt=$Candidate.CreatedAt;CommittedAt=[DateTime]::UtcNow.ToString('o');Terminal=$Terminal;ProfileHash=$ProfileHash;Dependencies=$Candidate.Dependencies}
    $profiles+=[pscustomobject]$record;Save-DistroShelfProfiles $profiles;return [pscustomobject]$record
}
function Get-DistroShelfProfileById {param([Parameter(Mandatory)][string]$Id) return @(Get-DistroShelfProfiles|?{$_.Id -eq $Id})|Select-Object -First 1}
function Test-DistroShelfProfileNameAvailable {param([Parameter(Mandatory)][string]$WslName)return (@(Get-DistroShelfProfiles|?{[string]$_.Status -eq 'Ready'}|?{$_.WslName -eq $WslName}).Count -eq 0)}
