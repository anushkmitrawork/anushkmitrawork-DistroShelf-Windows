# Non-destructive tests for per-distro Track 0 architecture.
# Run from repository root with:
# powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\DistroTrack.Tests.ps1

$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'src'
$failed=0

foreach($file in @('DistroTrackManager.ps1','RootfsProvider.ps1','Engine\HashEngine.ps1','Engine\TransactionEngine.ps1')){
    if(Test-Path -LiteralPath (Join-Path $src $file)){Write-Host "PASS  file exists: $file"}
    else{Write-Host "FAIL  missing: $file";$failed++}
}

. (Join-Path $src 'DistroTrackManager.ps1')
. (Join-Path $src 'Engine\HashEngine.ps1')
. (Join-Path $src 'Engine\TransactionEngine.ps1')

$tempRoot=Join-Path ([System.IO.Path]::GetTempPath()) ("DistroShelf-Track-Test-"+[guid]::NewGuid())
$oldRoot=$script:DistroShelfTrackRoot
try{
    $script:DistroShelfTrackRoot=$tempRoot

    $expected=@{'Ubuntu'='Ubuntu0';'Debian'='Debian0';'Fedora'='Fedora0';'Arch Linux'='ArchLinux0';'openSUSE'='openSUSE0'}
    foreach($distro in $expected.Keys){
        $track=Get-DistroShelfTrackDefinition $distro
        $ok=($track.Name -eq $expected[$distro])
        if($ok){Write-Host "PASS  track definition: $distro -> $($track.Name)"}
        else{Write-Host "FAIL  track definition: $distro";$failed++}
    }

    $u=Get-DistroShelfTrackDefinition 'Ubuntu';$f=Get-DistroShelfTrackDefinition 'Fedora'
    if($u.Root -ne $f.Root -and $u.Name -eq 'Ubuntu0' -and $f.Name -eq 'Fedora0'){Write-Host 'PASS  distro tracks are independent'}
    else{Write-Host 'FAIL  distro tracks are not independent';$failed++}

    New-Item -ItemType Directory -Path $u.Root,(Join-Path $u.Root 'metadata'),(Join-Path $u.Root 'podman') -Force|Out-Null
    'podman'|Set-Content (Join-Path $u.Root 'podman\artifact.txt')
    $stagePath=Join-Path $u.Root 'podman'
    $stageHash=Get-DistroShelfTreeHash $stagePath
    Write-DistroShelfHashRecord -Path (Join-Path $u.Root 'metadata\podman.hash.json') -Stage 'podman' -Hash $stageHash -TestResult ([pscustomobject]@{Passed=$true})|Out-Null
    if(Test-DistroShelfHashRecord -Path (Join-Path $u.Root 'metadata\podman.hash.json') -Root $stagePath -Stage 'podman'){
        Write-Host 'PASS  verified Track stage hash'
    }else{Write-Host 'FAIL  verified Track stage hash';$failed++}

    'tampered'|Set-Content (Join-Path $u.Root 'podman\artifact.txt')
    if(-not(Test-DistroShelfHashRecord -Path (Join-Path $u.Root 'metadata\podman.hash.json') -Root $stagePath -Stage 'podman')){Write-Host 'PASS  tampering invalidates Track stage hash'}
    else{Write-Host 'FAIL  tampering did not invalidate Track stage hash';$failed++}

    $tx=New-DistroShelfTransaction -Kind Track -Distro Debian
    if(Test-Path -LiteralPath $tx.Root){Write-Host 'PASS  Track transaction creates isolated attempt root'}
    else{Write-Host 'FAIL  Track transaction root missing';$failed++}
    $attemptFile=Join-Path $tx.Root 'Track\nested\artifact.txt'
    New-Item -ItemType Directory -Path (Split-Path $attemptFile) -Force|Out-Null
    'preserve-me'|Set-Content $attemptFile
    $err=[System.Management.Automation.ErrorRecord]::new([Exception]::new('synthetic Track failure'),'synthetic',[System.Management.Automation.ErrorCategory]::NotSpecified,$null)
    $trouble=Move-DistroShelfTransactionToTroubleshoot -Transaction $tx -ErrorRecord $err
    if($trouble -and (Test-Path -LiteralPath $trouble)){Write-Host 'PASS  failed Track transaction preserved in Troubleshoot'}
    else{Write-Host 'FAIL  Track transaction not preserved';$failed++}
    if(Test-Path -LiteralPath (Join-Path $trouble 'Track\nested\artifact.txt')){Write-Host 'PASS  Troubleshoot retains Track attempt contents'}
    else{Write-Host 'FAIL  Troubleshoot lost Track attempt contents';$failed++}
}finally{
    $script:DistroShelfTrackRoot=$oldRoot
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if($failed -gt 0){Write-Host "`n$failed test(s) failed.";exit 1}
Write-Host "`nAll non-destructive Track 0 tests passed."
exit 0
