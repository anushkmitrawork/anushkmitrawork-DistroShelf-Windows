$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'src'
. (Join-Path $src 'Distro\Registry.ps1')
. (Join-Path $src 'Engine\DefinitionValidator.ps1')
. (Join-Path $src 'Engine\DagScheduler.ps1')
. (Join-Path $src 'Profile\ProfileArtifactInstaller.ps1')
. (Join-Path $src 'Track\TrackEngine.ps1')

function Pass([string]$m){Write-Host "PASS  $m"}
function Fail([string]$m){throw "FAIL  $m"}

$provider=Get-DistroShelfProvider -Distro 'Ubuntu'
$stages=@($provider.Stages)
$expected=@('rootfs','podman','distrobox','flatpak','flathub','distroshelf','terminal-gnome-console','terminal-kitty','terminal-alacritty','terminal-foot','terminal-konsole')
if((@($stages|ForEach-Object Id)|Sort-Object) -join ',' -ne ($expected|Sort-Object) -join ','){Fail 'Ubuntu Track stage set changed'}else{Pass 'Ubuntu Track stage set is complete'}

$contract=Test-DistroShelfProviderContract -Provider $provider
if(-not $contract.Valid){Fail "Ubuntu provider contract invalid: $($contract.Errors -join '; ')"}else{Pass 'Ubuntu provider contract is valid'}
Test-DistroShelfDag -Stages $stages|Out-Null
Pass 'Ubuntu dependency DAG is valid'

$byId=@{};foreach($s in $stages){$byId[[string]$s.Id]=$s}
if((@($byId.distrobox.Depends)-join ',') -ne 'rootfs,podman'){Fail 'Distrobox must wait for rootfs and Podman'}
if((@($byId.flathub.Depends)|Sort-Object)-join ',' -ne 'flatpak,rootfs'){Fail 'Flathub must wait for rootfs and Flatpak'}
if((@($byId.distroshelf.Depends)|Sort-Object)-join ',' -ne 'distrobox,flathub,flatpak,rootfs'){Fail 'DistroShelf must wait for core GUI/container prerequisites'}
Pass 'Ubuntu dependency edges match the intended transaction order'

$terminalMap=@{
    'GNOME Console'=@('gnome-console','kgx')
    'Kitty'=@('kitty','kitty')
    'Alacritty'=@('alacritty','alacritty')
    'Foot'=@('foot','foot')
    'Konsole'=@('konsole','konsole')
}
$terminalStages=@($stages|Where-Object Kind -eq 'terminal')
if($terminalStages.Count -ne 5){Fail "Expected 5 terminal stages, found $($terminalStages.Count)"}
foreach($s in $terminalStages){
    $pair=$terminalMap[[string]$s.TerminalName]
    if(-not $pair){Fail "Unknown terminal '$($s.TerminalName)'"}
    if([string]$s.TerminalPackage -ne $pair[0]){Fail "Package mismatch for $($s.TerminalName)"}
    if([string]$s.TerminalExecutable -ne $pair[1]){Fail "Executable mismatch for $($s.TerminalName)"}
    if([string]$s.ExecutionModel -ne 'SharedBuilder'){Fail "Unexpected execution model for $($s.TerminalName)"}
    if([string]$s.Track.ExportType -ne 'apt-cache'){Fail "Terminal $($s.TerminalName) does not export an APT artifact"}
}
Pass 'Ubuntu Track carries five independently tested terminal artifacts'

foreach($id in @('podman','distrobox','flatpak')+$terminalStages.Id){
    $s=$byId[[string]$id]
    if([string]$s.Track.Acquire -notmatch 'apt-get --download-only'){Fail "Stage '$id' does not acquire durable APT artifacts"}
    if([string]$s.Profile.Install -match '(^|[;&|`n\r]|\s)(curl|wget|git\s+clone|apt(-get)?\s+.*https?://|flatpak\s+install\s+.*https?://)'){Fail "Profile stage '$id' contains network acquisition"}
    Test-DistroShelfProfileInstallCommands -Stage $s|Out-Null
}
Pass 'Ubuntu package stages download in Track and install offline in Profile'

if([string]$byId.flathub.Track.ExportType -ne 'wsl-path'){Fail 'Flathub must be represented as reusable Track path material'}
if([string]$byId.distroshelf.Track.ExportType -ne 'flatpak-sideload'){Fail 'DistroShelf must be represented as a reusable Flatpak sideload artifact'}
Pass 'Ubuntu Flatpak material has explicit Track export contracts'

if(@($provider.TrackFinalTests|ForEach-Object Name) -notcontains 'podman-functional'){Fail 'Ubuntu final Track test must include Podman functional verification'}
if(@($provider.ProfileFinalTests|ForEach-Object Name) -notcontains 'profile-os'){Fail 'Ubuntu final Profile test is missing'}
Pass 'Ubuntu final acceptance gates are present'

# Guard the runtime implementation: a stage cannot be verified without an immediate artifact hash check.
$trackText=Get-Content (Join-Path $src 'Track\TrackEngine.ps1') -Raw
if($trackText -notmatch 'Test-DistroShelfHashRecord'){Fail 'Track runtime does not immediately re-verify persisted stage hashes'}
if($trackText -notmatch 'Write-DistroShelfHashRecord'){Fail 'Track runtime does not persist stage hashes'}
if($trackText -notmatch 'Move-DistroShelfTransactionToTroubleshoot'){Fail 'Track runtime does not preserve failures in Troubleshoot'}
if($trackText -notmatch 'Complete-DistroShelfTransaction'){Fail 'Track runtime does not mark a verified transaction before commit'}
Pass 'Ubuntu Track runtime enforces test → artifact hash → transaction verification'

Write-Host "`nUbuntu Track contract tests passed."
