# DistroShelf - Profile commit boundary
# The committed Profile registry is updated only after the exported WSL environment
# has been re-registered and passed a post-commit smoke test.
. (Join-Path $PSScriptRoot '..\Engine\AtomicCommit.ps1')
. (Join-Path $PSScriptRoot '..\ProfileManager.ps1')

function Commit-DistroShelfProfileTransaction {
    param([Parameter(Mandatory)]$BuildResult,[Parameter(Mandatory)]$Reservation,[Parameter(Mandatory)][string]$Terminal)
    if(-not $BuildResult.Success){throw 'Cannot commit a failed Profile transaction.'}
    if([string]::IsNullOrWhiteSpace([string]$BuildResult.ProfileHash)){throw 'Cannot commit Profile without a final Profile hash.'}

    $candidate=$BuildResult.Candidate
    $transactionRoot=$BuildResult.Transaction.Root
    $wslName=[string]$candidate.WslName
    $profilesRoot=Join-Path $env:LOCALAPPDATA 'DistroShelf\profiles'
    $finalRoot=Join-Path $profilesRoot ([string]$candidate.Name)
    if(Test-Path -LiteralPath $finalRoot){throw "Committed Profile already exists: $finalRoot"}
    New-Item -ItemType Directory -Path $profilesRoot -Force|Out-Null

    $journal=[ordered]@{
        SchemaVersion=3;TransactionId=$BuildResult.Transaction.Id;ProfileId=$candidate.Id;Name=$candidate.Name;
        Distro=$candidate.Distro;WslName=$wslName;ProfileHash=$BuildResult.ProfileHash;
        State='Prepare';CreatedAt=[DateTime]::UtcNow.ToString('o')
    }
    $journalPath=Join-Path $transactionRoot 'commit-journal.json'

    function Save-Journal {
        $journal|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $journalPath -Encoding UTF8
    }
    Save-Journal

    try {
        # Export the already-accepted temporary environment exactly once. This export is
        # the durable payload whose integrity is subsequently verified and whose exact
        # bytes are promoted to the committed Profile.
        $export=Join-Path $transactionRoot 'profile-export.vhdx'
        & wsl.exe --export $wslName $export --format vhd 2>&1|Out-Null
        if($LASTEXITCODE-ne 0 -or -not(Test-Path -LiteralPath $export -PathType Leaf)){throw "Failed to export verified Profile '$wslName' for commit."}
        $journal.State='Exported';Save-Journal

        $exportHash=(Get-FileHash -LiteralPath $export -Algorithm SHA256).Hash.ToLowerInvariant()
        if([string]::IsNullOrWhiteSpace($exportHash)){throw "Failed to hash exported Profile '$wslName'."}
        $journal.ExportedVhdxSha256=$exportHash;Save-Journal

        # The build hash must remain tied to the accepted Profile metadata. The payload
        # hash is recorded separately because the VHDX is the actual committed object.
        $payloadRecord=[ordered]@{
            SchemaVersion=1;ProfileId=$candidate.Id;Name=$candidate.Name;Distro=$candidate.Distro;
            WslName=$wslName;ProfileHash=$BuildResult.ProfileHash;ExportedVhdxSha256=$exportHash;
            RecordedAt=[DateTime]::UtcNow.ToString('o')
        }
        $payloadRecordPath=Join-Path $transactionRoot 'export.hash.json'
        $payloadRecord|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $payloadRecordPath -Encoding UTF8
        $journal.State='ExportVerified';Save-Journal

        & wsl.exe --unregister $wslName 2>&1|Out-Null
        if($LASTEXITCODE-ne 0){throw "Failed to unregister temporary Profile '$wslName' during commit."}
        $journal.State='TemporaryUnregistered';Save-Journal

        New-Item -ItemType Directory -Path $finalRoot -Force|Out-Null
        $finalWsl=Join-Path $finalRoot 'wsl';New-Item -ItemType Directory -Path $finalWsl -Force|Out-Null
        $finalVhdx=Join-Path $finalWsl 'ext4.vhdx'

        # Promotion of the exact exported artifact is the irreversible filesystem move.
        Move-Item -LiteralPath $export -Destination $finalVhdx -Force
        $journal.State='PayloadPromoted';Save-Journal

        # Verify that the promoted file is byte-identical to the accepted export before WSL
        # registration. A mismatch aborts the commit and preserves the transaction.
        $promotedHash=(Get-FileHash -LiteralPath $finalVhdx -Algorithm SHA256).Hash.ToLowerInvariant()
        if($promotedHash -ne $exportHash){throw "Committed Profile payload hash mismatch for '$wslName'."}
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
            SchemaVersion=2;ProfileId=$candidate.Id;Name=$candidate.Name;Distro=$candidate.Distro;
            WslName=$wslName;PackageManager=$candidate.PackageManager;Terminal=$Terminal;
            ProfileHash=$BuildResult.ProfileHash;ExportedVhdxSha256=$exportHash;CommittedAt=[DateTime]::UtcNow.ToString('o')
        }
        Write-DistroShelfJsonAtomically -Path (Join-Path $finalRoot 'profile.json') -Value $record

        # Registry publication is deliberately the final step. A failed WSL commit therefore
        # cannot leave a Ready profile in profiles.json.
        $committed=Commit-DistroShelfProfile -Candidate $candidate -Terminal $Terminal -ProfileHash $BuildResult.ProfileHash
        $journal.State='Committed';$journal|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $journalPath -Encoding UTF8

        Remove-Item -LiteralPath $transactionRoot -Recurse -Force -ErrorAction SilentlyContinue
        return [pscustomobject][ordered]@{Success=$true;Profile=$committed;Root=$finalRoot;WslName=$wslName;ProfileHash=$BuildResult.ProfileHash;ExportedVhdxSha256=$exportHash}
    } catch {
        # Never leave a partially promoted Profile outside the transaction journal. If the
        # WSL registration exists, unregister it first; then move every remaining artifact
        # back under the transaction root so the entire failed attempt can be preserved by
        # the caller's Troubleshoot handling.
        try{if(@(& wsl.exe --list --quiet 2>$null)|ForEach-Object{($_-replace "`0",'').Trim()}|Where-Object{$_ -eq $wslName}){& wsl.exe --unregister $wslName 2>$null|Out-Null}}catch{}
        if(Test-Path -LiteralPath $finalRoot){
            $recover=Join-Path $transactionRoot 'failed-commit'
            try{New-Item -ItemType Directory -Path $recover -Force|Out-Null;Move-Item -LiteralPath $finalRoot -Destination (Join-Path $recover ([string]$candidate.Name)) -Force}catch{}
        }
        $journal.State='CommitFailed';$journal.Error=$_.Exception.Message;Save-Journal
        throw
    }
}
