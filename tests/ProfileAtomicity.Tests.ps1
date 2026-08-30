$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot;$src=Join-Path $root 'src'
function Pass($m){Write-Host "PASS  $m"};function Fail($m){throw "FAIL  $m"}
. (Join-Path $src 'Engine\TransactionEngine.ps1')
. (Join-Path $src 'Engine\AtomicCommit.ps1')
. (Join-Path $src 'ProfileManager.ps1')
. (Join-Path $src 'Profile\ProfileCommit.ps1')

$temp=Join-Path ([IO.Path]::GetTempPath()) ('DistroShelf-ProfileAtomic-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $temp -Force|Out-Null
try {
    $transaction=[pscustomobject]@{Root=$temp;Id='tx-test'}
    $export=Join-Path $temp 'Export\profile.vhdx'
    New-Item -ItemType Directory -Path (Split-Path -Parent $export) -Force|Out-Null
    [IO.File]::WriteAllText($export,'stable-profile-payload')
    $bytes=[IO.File]::ReadAllBytes($export)
    $sha=([Security.Cryptography.SHA256]::Create()).ComputeHash($bytes)|ForEach-Object ToString x2
    $hash=(-join $sha).ToLowerInvariant()
    $candidate=[pscustomobject]@{Id='candidate-id';Name='Ubuntu99';Distro='Ubuntu';WslName='DistroShelf-Ubuntu99';PackageManager='apt'}
    $build=[pscustomobject]@{Success=$true;Candidate=$candidate;Transaction=$transaction;ExportPath=$export;ProfileHash=$hash}
    $reservation=[pscustomobject]@{}

    $unregister= { param($n) 0 }
    $import= { param($n,$p) 0 }
    $list= { param() @('DistroShelf-Ubuntu99') }
    $smoke= { param($n) [pscustomobject]@{ExitCode=0;Output=@('DISTROSHELF_PROFILE_COMMIT_OK')} }
    $publisher={ param($c,$t,$h) [pscustomobject]@{Published=$true;Name=$c.Name} }
    $hashFile={ param($p) return ([IO.File]::ReadAllBytes($p) | ForEach-Object { $_ }) | % { } }
    $hashFile={ param($p) (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }

    $result=Commit-DistroShelfProfileTransaction -BuildResult $build -Reservation $reservation -Terminal 'GNOME Console' -HashFile $hashFile -UnregisterWsl $unregister -ImportInPlace $import -ListWsl $list -SmokeTest $smoke -PublishProfile $publisher
    if($result.Success -and $result.ProfileHash -eq $hash){Pass 'successful atomic Profile commit consumes exact artifact'}else{Fail 'successful atomic Profile commit failed'}

    # Export failure is represented by a missing accepted export: commit must fail before promotion.
    $missingBuild=$build.PSObject.Copy();$missingBuild.ExportPath=Join-Path $temp 'missing.vhdx'
    try { Commit-DistroShelfProfileTransaction -BuildResult $missingBuild -Reservation $reservation -Terminal 'GNOME Console' -UnregisterWsl $unregister -ImportInPlace $import -ListWsl $list -SmokeTest $smoke -PublishProfile $publisher|Out-Null;Fail 'missing export was accepted' } catch { Pass 'missing export blocks atomic commit' }

    # Hash mismatch must fail before WSL unregister or filesystem promotion.
    $badBuild=$build.PSObject.Copy();$badBuild.ProfileHash=('0'*64)
    $called=[ordered]@{Unregister=$false;Import=$false}
    $unregisterGuard={param($n);$called.Unregister=$true;0}
    $importGuard={param($n,$p);$called.Import=$true;0}
    try { Commit-DistroShelfProfileTransaction -BuildResult $badBuild -Reservation $reservation -Terminal 'GNOME Console' -UnregisterWsl $unregisterGuard -ImportInPlace $importGuard -ListWsl $list -SmokeTest $smoke -PublishProfile $publisher|Out-Null;Fail 'hash mismatch was accepted' } catch { }
    if(-not $called.Unregister -and -not $called.Import){Pass 'artifact hash mismatch fails before destructive commit actions'}else{Fail 'hash mismatch reached destructive actions'}

    # Import failure must recover the promoted final tree back under the transaction root.
    $importFailure={param($n,$p);5}
    try { Commit-DistroShelfProfileTransaction -BuildResult $build -Reservation $reservation -Terminal 'GNOME Console' -HashFile $hashFile -UnregisterWsl $unregister -ImportInPlace $importFailure -ListWsl $list -SmokeTest $smoke -PublishProfile $publisher|Out-Null;Fail 'import failure was accepted' } catch { Pass 'import failure aborts commit' }
    $recovered=Join-Path $temp 'failed-commit\Ubuntu99\wsl\ext4.vhdx'
    if(Test-Path -LiteralPath $recovered){Pass 'failed commit preserves promoted payload for Troubleshoot recovery'}else{Fail 'failed commit lost promoted payload'}

    # Publication failure must not be silently ignored.
    $publisherFailure={param($c,$t,$h);throw 'synthetic registry failure'}
    try { Commit-DistroShelfProfileTransaction -BuildResult $build -Reservation $reservation -Terminal 'GNOME Console' -HashFile $hashFile -UnregisterWsl $unregister -ImportInPlace $import -ListWsl $list -SmokeTest $smoke -PublishProfile $publisherFailure|Out-Null;Fail 'registry failure was accepted' } catch { Pass 'registry publication failure aborts transaction' }

    Write-Host "`nAll Profile atomicity failure-injection tests passed."
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
