$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'src'
. (Join-Path $src 'Distro\Registry.ps1')
. (Join-Path $src 'Engine\DefinitionValidator.ps1')
. (Join-Path $src 'Engine\DagScheduler.ps1')
. (Join-Path $src 'Profile\ProfileArtifactInstaller.ps1')

function Pass([string]$m){Write-Host "PASS  $m"}
function Fail([string]$m){throw "FAIL  $m"}

$provider=Get-DistroShelfProvider -Distro 'Ubuntu'
$stages=@($provider.Stages)
$ids=@($stages|ForEach-Object{[string]$_.Id})
$expected=@('rootfs','podman','distrobox','flatpak','flathub','distroshelf','terminal-gnome-console','terminal-kitty','terminal-alacritty','terminal-foot','terminal-konsole')
if(@($ids|Sort-Object) -join ',' -ne @($expected|Sort-Object) -join ','){Fail "Ubuntu stage matrix changed unexpectedly: $($ids -join ', ')"}else{Pass 'Ubuntu stage matrix is explicit and complete'}

$validation=Test-DistroShelfProviderContract -Provider $provider
if(-not $validation.Valid){Fail "Ubuntu provider contract invalid: $($validation.Errors -join '; ')"}else{Pass 'Ubuntu provider contract is valid'}

Test-DistroShelfDag -Stages $stages|Out-Null
Pass 'Ubuntu Track DAG is acyclic and dependency-valid'

$byId=@{}
foreach($stage in $stages){$byId[[string]$stage.Id]=$stage}
if(@($byId['distrobox'].Depends) -join ',' -ne 'rootfs,podman'){Fail 'Ubuntu Distrobox dependency edge is wrong'}else{Pass 'Ubuntu Distrobox waits for verified Podman stage'}
if((@($byId['flathub'].Depends) -notcontains 'flatpak') -or (@($byId['flathub'].Depends) -notcontains 'rootfs')){Fail 'Ubuntu Flathub dependency edges are wrong'}else{Pass 'Ubuntu Flathub waits for rootfs and Flatpak'}
if((@($byId['distroshelf'].Depends) -notcontains 'distrobox') -or (@($byId['distroshelf'].Depends) -notcontains 'flathub')){Fail 'Ubuntu DistroShelf dependency edges are wrong'}else{Pass 'Ubuntu DistroShelf waits for Distrobox and Flathub'}

$terminalStages=@($stages|Where-Object Kind -eq 'terminal')
if($terminalStages.Count -ne 5){Fail "Ubuntu must carry 5 terminal Track stages, found $($terminalStages.Count)"}else{Pass 'Ubuntu Track carries all five terminal preferences'}
foreach($stage in $terminalStages){
    if([string]$stage.Depends[0] -ne 'rootfs'){Fail "Ubuntu terminal '$($stage.TerminalName)' does not wait for rootfs"}
    $expectedExecutable=@{'GNOME Console'='kgx';'Kitty'='kitty';'Alacritty'='alacritty';'Foot'='foot';'Konsole'='konsole'}[[string]$stage.TerminalName]
    if([string]$stage.TerminalExecutable -ne [string]$expectedExecutable){Fail "Ubuntu terminal executable mismatch for '$($stage.TerminalName)'"}
    if([string]$stage.Track.Acquire -notmatch 'apt-get --download-only'){Fail "Ubuntu terminal '$($stage.TerminalName)' does not use Track download-only acquisition"}
    if(@($stage.Track.Tests|ForEach-Object Command|Where-Object {$_ -match 'command -v|--version'}).Count -lt 2){Fail "Ubuntu terminal '$($stage.TerminalName)' lacks command/version verification"}
    Test-DistroShelfProfileInstallCommands -Stage $stage|Out-Null
}
Pass 'Ubuntu terminal stages download all choices and verify usability before hashing'

foreach($id in @('podman','distrobox','flatpak')){
    $stage=$byId[$id]
    if([string]$stage.Track.Acquire -notmatch 'apt-get --download-only'){Fail "Ubuntu '$id' Track stage does not download artifacts"}
    if(@($stage.Track.Tests).Count -lt 3){Fail "Ubuntu '$id' Track stage does not have a multi-level verification suite"}
    Test-DistroShelfProfileInstallCommands -Stage $stage|Out-Null
}
if(@($byId['distrobox'].Track.Tests|ForEach-Object Command|Where-Object {$_ -eq 'distrobox list'}).Count -ne 1){Fail 'Ubuntu Distrobox stage is missing the functional list check'}else{Pass 'Ubuntu Distrobox stage has a functional command check'}
Pass 'Ubuntu core stages separate durable acquisition from functional verification and offline Profile installation'

$fl=$byId['flathub']
if([string]$fl.Track.Acquire -notmatch 'curl -fsSL https://dl.flathub.org/repo/flathub.flatpakrepo'){Fail 'Ubuntu Flathub stage does not acquire the official repository descriptor'}
if(@($fl.Track.Tests|ForEach-Object Command|Where-Object {$_ -match 'flatpak remotes'}).Count -lt 1){Fail 'Ubuntu Flathub stage lacks remote verification'}else{Pass 'Ubuntu Flathub stage verifies the acquired repository state'}

$ds=$byId['distroshelf']
if([string]$ds.Track.ExportType -ne 'flatpak-sideload'){Fail 'Ubuntu DistroShelf stage is not exported as a sideload artifact'}else{Pass 'Ubuntu DistroShelf is captured as a reusable Flatpak sideload artifact'}

if(@($provider.TrackFinalTests|ForEach-Object Name) -notcontains 'podman-functional'){Fail 'Ubuntu Track final test is missing Podman functional verification'}else{Pass 'Ubuntu Track has functional Podman final verification'}
if(@($provider.ProfileFinalTests|ForEach-Object Name) -notcontains 'profile-os'){Fail 'Ubuntu Profile final test is missing'}else{Pass 'Ubuntu Profile has final OS verification'}

Write-Host "`nUbuntu reference architecture tests passed."
