# Non-destructive tests for the current DistroShelf Profile registry.
# Run from repository root with:
# powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\DistroShelf.Tests.ps1

$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'src'
$failed=0

foreach($file in @('ProfileManager.ps1','DistroTrackManager.ps1','InstallOrchestrator.ps1','Engine\TransactionEngine.ps1','Engine\HashEngine.ps1','Engine\DagScheduler.ps1','Engine\StageExecutor.ps1')){
    if(Test-Path -LiteralPath (Join-Path $src $file)){Write-Host "PASS  file exists: $file"}
    else{Write-Host "FAIL  missing: $file";$failed++}
}

. (Join-Path $src 'ProfileManager.ps1')
$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('DistroShelf-Profile-Test-'+[guid]::NewGuid())
$oldRoot=$script:DistroShelfProfileRoot
$oldFile=$script:DistroShelfProfileFile
try {
    $script:DistroShelfProfileRoot=$tempRoot
    $script:DistroShelfProfileFile=Join-Path $tempRoot 'profiles.json'
    Initialize-DistroShelfProfileStore

    $u=[pscustomobject]@{Id='u1';Name='Ubuntu1';Distro='Ubuntu';WslName='DistroShelf-Ubuntu1';PackageManager='apt';Status='Candidate';CreatedAt=[DateTime]::UtcNow.ToString('o');Dependencies=[ordered]@{}}
    $d=[pscustomobject]@{Id='d1';Name='Debian1';Distro='Debian';WslName='DistroShelf-Debian1';PackageManager='apt';Status='Candidate';CreatedAt=[DateTime]::UtcNow.ToString('o');Dependencies=[ordered]@{}}

    $uRecord=Commit-DistroShelfProfile -Candidate $u -Terminal 'GNOME Console' -ProfileHash ('a'*64)
    $dRecord=Commit-DistroShelfProfile -Candidate $d -Terminal 'Kitty' -ProfileHash ('b'*64)
    if(($uRecord.Status -eq 'Ready') -and ($dRecord.Status -eq 'Ready') -and ($uRecord.Name -eq 'Ubuntu1') -and ($dRecord.Name -eq 'Debian1')){Write-Host 'PASS  Profiles commit independently by distro'}else{Write-Host 'FAIL  independent profile commits';$failed++}

    $uFound=Get-DistroShelfProfileById -Id 'u1'
    $dFound=Get-DistroShelfProfileById -Id 'd1'
    if(($uFound.Name -eq 'Ubuntu1') -and ($uFound.Terminal -eq 'GNOME Console') -and ($dFound.Name -eq 'Debian1') -and ($dFound.Terminal -eq 'Kitty')){Write-Host 'PASS  profile identity and terminal metadata persist'}else{Write-Host 'FAIL  profile identity or terminal metadata';$failed++}

    $ubuntuTaken=(-not(Test-DistroShelfProfileNameAvailable -WslName 'DistroShelf-Ubuntu1'))
    $ubuntuNext=(Test-DistroShelfProfileNameAvailable -WslName 'DistroShelf-Ubuntu2')
    if($ubuntuTaken -and $ubuntuNext){Write-Host 'PASS  committed WSL names are reserved independently'}else{Write-Host 'FAIL  profile name availability check';$failed++}

    $profiles=@(Get-DistroShelfProfiles)
    if(($profiles.Count -eq 2) -and ((@($profiles|ForEach-Object Id)|Select-Object -Unique).Count -eq 2)){Write-Host 'PASS  profile records survive round-trip persistence'}else{Write-Host 'FAIL  profile persistence';$failed++}
}
finally {
    $script:DistroShelfProfileRoot=$oldRoot
    $script:DistroShelfProfileFile=$oldFile
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if($failed -gt 0){Write-Host "`n$failed test(s) failed.";exit 1}
Write-Host "`nAll current Profile registry tests passed."
exit 0
