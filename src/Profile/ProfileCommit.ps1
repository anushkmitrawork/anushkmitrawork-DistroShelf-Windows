# DistroShelf - Profile commit boundary
# The committed Profile registry is updated only after the single accepted export
# has been verified, promoted byte-for-byte, re-registered, and smoke-tested.
. (Join-Path $PSScriptRoot '..\Engine\AtomicCommit.ps1')
. (Join-Path $PSScriptRoot '..\ProfileManager.ps1')

function Commit-DistroShelfProfileTransaction {
    param([Parameter(Mandatory)]$BuildResult,[Parameter(Mandatory)]$Reservation,[Parameter(Mandatory)][string]$Terminal)
    if(-not $BuildResult.Success){throw 'Cannot commit a failed Profile transaction.'}
    if([string]::IsNullOrWhiteSpace([string]$BuildResult.ProfileHash)){throw 'Cannot commit Profile without a final Profile hash.'}
    if([string]::IsNullOrWhiteSpace([string]$BuildResult.ExportPath)){throw 'Cannot commit Profile without the accepted export artifact.'}

    $candidate=$BuildResult.Candidate
    $transactionRoot=$BuildResult.Transaction.Root
    $export=[string]$BuildResult.ExportPath
    $wslName=[string]$candidate.WslName
    $profilesRoot=Join-Path $env:LOCALAPPDATA 'DistroShelf\profiles'
    $finalRoot=Join-Path $profilesRoot ([string]$candidate.Name)
    if(Test-Path -LiteralPath $finalRoot){throw "Committed Profile already exists: $finalRoot"}
    if(-not(Test-Path -LiteralPath $export -PathType Leaf)){throw "Accepted Profile export is missing: $export"}
    New-Item -ItemType Directory -Path $profilesRoot -Force|Out-Null

    $journal=[ordered]@{
        SchemaVersion=4;TransactionId=$BuildResult.Transaction.Id;ProfileId=$candidate.Id;Name=$candidate.Name;
        Distro=$candidate.Distro;WslName=$wslName;ProfileHash=$BuildResult.ProfileHash;
        ExportPath=$export;State='Prepare';CreatedAt=[DateTime]::UtcNow.ToString('o')
    }
    $journalPath=Join-Path $transactionRoot 'commit-journal.json'

    function Save-Journal {
        $journal|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $journalPath -Encoding UTF8
    }
    Save-Journal

    try {
        # ProfileEngine has already exported the accepted WSL environment exactly once.
        # Re-exporting here would create a different artifact and weaken the identity
        # guarantee between testing, hashing, and commit.
        $artifactHash=(Get-FileHash -LiteralPath $export -Algorithm SHA256).Hash.ToLowerInvariant()
        if($artifactHash -ne [string]$BuildResult.ProfileHash.ToLowerInvariant()){
            throw "Accepted Profile artifact hash does not match ProfileHash for '$wslName'."
        }
        $journal.ExportedVhdxSha256=$artifactHash;Save-Journal

        # The temporary WSL registration is no longer needed once its already-accepted
        # export has been verified. The export remains the durable transaction artifact.
        & wsl.exe --unregister $wslName 2>&1|Out-Null
        if($LASTEXITCODE-ne 0){throw "Failed to unregister temporary Profile '$wslName' during commit."}
        $journal.State='TemporaryUnregistered';Save-Journal

        New-Item -ItemType Directory -Path $finalRoot -Force|Out-Null
        $finalWsl=Join-Path $finalRoot 'wsl';New-Item -ItemType Directory -Path $finalWsl -Force|Out-Null
        $finalVhdx=Join-Path $finalWsl 'ext4.vhdx'

        # Promotion uses the exact accepted artifact. No second export is permitted.
        Move-Item -LiteralPath $export -Destination $finalVhdx -Force
        $journal.State='PayloadPromoted';Save-Journal

        $promotedHash=(Get-FileHash -LiteralPath $finalVhdx -Algorithm SHA256).Hash.ToLowerInvariant()
        if($promotedHash -ne $artifactHash){throw "Committed Profile payload hash mismatch for '$wslName'."}
        $journal.PromotedVhdxSha256=$promotedHash;Save-Journal

        & wsl.exe --import-in-place $wslName $finalVhdx 2>&1|Out-Null
        if($LASTEXITCODE-ne 0){throw "Failed to import committed Profile '$wslName' in place."}
        $journal.State='WslRegistered';Save-Journal

        $registered=@(& wsl.exe --list --quiet 2>$null)|ForEach-Object{($_-replace "`0",'').Trim()}|Where-Object{$_}
        if($registered-notcontains$wslName){throw "Committed Profile '$wslName' is not registered with WSL."}
        $smoke=& wsl.exe --distribution $wslName -- bash -lc 'printf DISTROSHELF_PROFILE_COMMIT_OK' 2>&1
        if($LASTEXITCODE-ne 0 -or (($smoke-join "`n") -notmatch 'DISTROSHELF_PROFILE_COMMIT_OK')){throw "Committed Profile '$wslName' failed its post-commit smoke test."}
        $journal.State='WslSmokeVerified';Save-Journal

        $record=[ordered]@{
            SchemaVersion=3;ProfileId=$candidate.Id;Name=$candidate.Name;Distro=$candidate.Distro;
            WslName=$wslName;PackageManager=$candidate.PackageManager;Terminal=$Terminal;
            ProfileHash=$BuildResult.ProfileHash;ExportedVhdxSha256=$artifactHash;CommittedAt=[DateTime]::UtcNow.ToString('o')
        }
        Write-DistroShelfJsonAtomically -Path (Join-Path $finalRoot 'profile.json') -Value $record

        # Registry publication is deliberately the final step.
        $committed=Commit-DistroShelfProfile -Candidate $candidate -Terminal $Terminal -ProfileHash $BuildResult.ProfileHash
        $journal.State='Committed';$journal|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $journalPath -Encoding UTF8

        Remove-Item -LiteralPath $transactionRoot -Recurse -Force -ErrorAction SilentlyContinue
        return [pscustomobject][ordered]@{Success=$true;Profile=$committed;Root=$finalRoot;WslName=$wslName;ProfileHash=$BuildResult.ProfileHash;ExportedVhdxSha256=$artifactHash}
    } catch {
        # Never leave a partially promoted Profile outside the transaction boundary.
        try{if(@(& wsl.exe --list --quiet 2>$null)|ForEach-Object{($_-replace "`0",'').Trim()}|Where-Object{$_ -eq $wslName}){& wsl.exe --unregister $wslName 2>$null|Out-Null}}catch{}
        if(Test-Path -LiteralPath $finalRoot){
            $recover=Join-Path $transactionRoot 'failed-commit'
            try{New-Item -ItemType Directory -Path $recover -Force|Out-Null;Move-Item -LiteralPath $finalRoot -Destination (Join-Path $recover ([string]$candidate.Name)) -Force}catch{}
        }
        $journal.State='CommitFailed';$journal.Error=$_.Exception.Message;Save-Journal
        throw
    }
}
