$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot;$src=Join-Path $root 'src'
function Pass($m){Write-Host "PASS  $m"};function Fail($m){throw "FAIL  $m"}
. (Join-Path $src 'Engine\TransactionEngine.ps1')
. (Join-Path $src 'Engine\AtomicCommit.ps1')
. (Join-Path $src 'ProfileManager.ps1')
. (Join-Path $src 'Profile\ProfileCommit.ps1')

function New-TestScenario {
    param([string]$Name)
    $dir=Join-Path ([IO.Path]::GetTempPath()) ("DistroShelf-ProfileAtomic-$Name-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path (Join-Path $dir 'Export') -Force|Out-Null
    $export=Join-Path $dir 'Export\profile.vhdx'
    [IO.File]::WriteAllText($export,'stable-profile-payload')
    $hash=(Get-FileHash -LiteralPath $export -Algorithm SHA256).Hash.ToLowerInvariant()
    $candidate=[pscustomobject]@{Id="candidate-$Name";Name="Ubuntu99-$Name";Distro='Ubuntu';WslName="DistroShelf-Ubuntu99-$Name";PackageManager='apt'}
    [pscustomobject]@{
        Root=$dir
        Export=$export
        Hash=$hash
        Candidate=$candidate
        Build=[pscustomobject]@{Success=$true;Candidate=$candidate;Transaction=[pscustomobject]@{Root=$dir;Id="tx-$Name"};ExportPath=$export;ProfileHash=$hash}
        Reservation=[pscustomobject]@{}
    }
}

$unregister= { param($n) 0 }
$import= { param($n,$p) 0 }
$smoke= { param($n) [pscustomobject]@{ExitCode=0;Output=@('DISTROSHELF_PROFILE_COMMIT_OK')} }
$publisher= { param($c,$t,$h) [pscustomobject]@{Published=$true;Name=$c.Name} }
$hashFile={ param($p) (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }

$scenarios=@()
try {
    # 1. Successful commit consumes the exact accepted export and moves it as-is.
    $s=New-TestScenario 'success';$scenarios+=$s
    $result=Commit-DistroShelfProfileTransaction -BuildResult $s.Build -Reservation $s.Reservation -Terminal 'GNOME Console' -HashFile $hashFile -UnregisterWsl $unregister -ImportInPlace $import -ListWsl { @($s.Candidate.WslName) } -SmokeTest $smoke -PublishProfile $publisher
    if($result.Success -and $result.ProfileHash -eq $s.Hash){Pass 'successful atomic Profile commit consumes exact artifact'}else{Fail 'successful atomic Profile commit failed'}
    $promoted=Join-Path $result.Root 'wsl\ext4.vhdx'
    if(Test-Path $promoted){Pass 'successful commit preserves promoted artifact'}else{Fail 'successful commit lost promoted artifact'}
    if(-not(Test-Path $s.Export)){Pass 'successful commit moves accepted artifact rather than copying it'}else{Fail 'successful commit copied artifact instead of moving it as-is'}
    if((Get-FileHash -LiteralPath $promoted -Algorithm SHA256).Hash.ToLowerInvariant() -eq $s.Hash){Pass 'promoted Profile artifact is byte-identical to accepted artifact'}else{Fail 'promoted Profile artifact changed during commit'}
    Remove-Item -LiteralPath $s.Root -Recurse -Force -ErrorAction SilentlyContinue

    # 2. Missing export blocks before destructive operations.
    $s=New-TestScenario 'missing-export';$scenarios+=$s
    $s.Build.ExportPath=Join-Path $s.Root 'Export\missing.vhdx'
    $called=[ordered]@{Unregister=$false;Import=$false}
    $unregGuard={param($n);$called.Unregister=$true;0};$importGuard={param($n,$p);$called.Import=$true;0}
    try { Commit-DistroShelfProfileTransaction -BuildResult $s.Build -Reservation $s.Reservation -Terminal 'GNOME Console' -UnregisterWsl $unregGuard -ImportInPlace $importGuard -ListWsl { @() } -SmokeTest $smoke -PublishProfile $publisher|Out-Null;Fail 'missing export was accepted' } catch { Pass 'missing export blocks atomic commit' }
    if(-not $called.Unregister -and -not $called.Import){Pass 'missing export fails before destructive actions'}else{Fail 'missing export reached destructive actions'}

    # 3. Hash mismatch blocks before unregister/import.
    $s=New-TestScenario 'hash-mismatch';$scenarios+=$s;$s.Build.ProfileHash=('0'*64)
    $called=[ordered]@{Unregister=$false;Import=$false}
    try { Commit-DistroShelfProfileTransaction -BuildResult $s.Build -Reservation $s.Reservation -Terminal 'GNOME Console' -UnregisterWsl $unregGuard -ImportInPlace $importGuard -ListWsl { @() } -SmokeTest $smoke -PublishProfile $publisher|Out-Null;Fail 'hash mismatch was accepted' } catch { }
    if(-not $called.Unregister -and -not $called.Import){Pass 'artifact hash mismatch fails before destructive actions'}else{Fail 'hash mismatch reached destructive actions'}

    # 4. Import failure recovers the promoted tree under the transaction root.
    $s=New-TestScenario 'import-failure';$scenarios+=$s
    $importFailure={param($n,$p)5}
    try { Commit-DistroShelfProfileTransaction -BuildResult $s.Build -Reservation $s.Reservation -Terminal 'GNOME Console' -HashFile $hashFile -UnregisterWsl $unregister -ImportInPlace $importFailure -ListWsl { @($s.Candidate.WslName) } -SmokeTest $smoke -PublishProfile $publisher|Out-Null;Fail 'import failure was accepted' } catch { Pass 'import failure aborts commit' }
    $recovered=Join-Path $s.Root 'failed-commit\Ubuntu99-import-failure\wsl\ext4.vhdx'
    if(Test-Path -LiteralPath $recovered){Pass 'failed commit preserves promoted payload for Troubleshoot recovery'}else{Fail 'failed commit lost promoted payload'}
    $recoveredHash=(Get-FileHash -LiteralPath $recovered -Algorithm SHA256).Hash.ToLowerInvariant()
    if($recoveredHash -eq $s.Hash){Pass 'recovered payload remains byte-identical'}else{Fail 'recovered payload was altered'}

    # 5. Registry publication failure aborts rather than being swallowed.
    $s=New-TestScenario 'publisher-failure';$scenarios+=$s
    $publisherFailure={param($c,$t,$h)throw 'synthetic registry failure'}
    try { Commit-DistroShelfProfileTransaction -BuildResult $s.Build -Reservation $s.Reservation -Terminal 'GNOME Console' -HashFile $hashFile -UnregisterWsl $unregister -ImportInPlace $import -ListWsl { @($s.Candidate.WslName) } -SmokeTest $smoke -PublishProfile $publisherFailure|Out-Null;Fail 'registry failure was accepted' } catch { Pass 'registry publication failure aborts transaction' }
    $recovered=Join-Path $s.Root 'failed-commit\Ubuntu99-publisher-failure\wsl\ext4.vhdx'
    if(Test-Path -LiteralPath $recovered){Pass 'registry failure preserves full committed-payload attempt'}else{Fail 'registry failure lost promoted payload'}

    Write-Host "`nAll Profile atomicity failure-injection tests passed."
}
finally {
    foreach($s in $scenarios){if(Test-Path -LiteralPath $s.Root){Remove-Item -LiteralPath $s.Root -Recurse -Force -ErrorAction SilentlyContinue}}
}
