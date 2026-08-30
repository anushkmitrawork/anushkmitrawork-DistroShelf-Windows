# DistroShelf - Profile commit boundary
# The committed Profile registry is updated only after the single accepted export
# has been verified, promoted byte-for-byte, re-registered, and smoke-tested.
. (Join-Path $PSScriptRoot '..\Engine\AtomicCommit.ps1')
. (Join-Path $PSScriptRoot '..\ProfileManager.ps1')

function Commit-DistroShelfProfileTransaction {
    param(
        [Parameter(Mandatory)]$BuildResult,
        [Parameter(Mandatory)]$Reservation,
        [Parameter(Mandatory)][string]$Terminal,
        [scriptblock]$HashFile = { param($Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() },
        [scriptblock]$UnregisterWsl = { param($Name) & wsl.exe --unregister $Name 2>&1 | Out-Null; return $LASTEXITCODE },
        [scriptblock]$ImportInPlace = { param($Name,$Vhdx) & wsl.exe --import-in-place $Name $Vhdx 2>&1 | Out-Null; return $LASTEXITCODE },
        [scriptblock]$ListWsl = { @(& wsl.exe --list --quiet 2>$null) | ForEach-Object { ($_ -replace "`0",'').Trim() } | Where-Object { $_ } },
        [scriptblock]$SmokeTest = { param($Name) $output = & wsl.exe --distribution $Name -- bash -lc 'printf DISTROSHELF_PROFILE_COMMIT_OK' 2>&1; [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output) } },
        [scriptblock]$PublishProfile = { param($Candidate,$Terminal,$ProfileHash) Commit-DistroShelfProfile -Candidate $Candidate -Terminal $Terminal -ProfileHash $ProfileHash }
    )
    if(-not $BuildResult.Success){throw 'Cannot commit a failed Profile transaction.'}
    if([string]::IsNullOrWhiteSpace([string]$BuildResult.ProfileHash)){throw 'Cannot commit Profile without a final Profile hash.'}
    if([string]::IsNullOrWhiteSpace([string]$BuildResult.ExportPath)){throw 'Cannot commit Profile without the accepted export artifact.'}

    $candidate=$BuildResult.Candidate
    $transactionRoot=[IO.Path]::GetFullPath([string]$BuildResult.Transaction.Root)
    $export=[IO.Path]::GetFullPath([string]$BuildResult.ExportPath)
    if(-not $export.StartsWith($transactionRoot.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)){
        throw 'Accepted Profile export must reside inside the transaction root.'
    }
    $wslName=[string]$candidate.WslName
    $profilesRoot=Join-Path $env:LOCALAPPDATA 'DistroShelf\profiles'
    $finalRoot=Join-Path $profilesRoot ([string]$candidate.Name)
    if(Test-Path -LiteralPath $finalRoot){throw "Committed Profile already exists: $finalRoot"}
    if(-not(Test-Path -LiteralPath $export -PathType Leaf)){throw "Accepted Profile export is missing: $export"}
    New-Item -ItemType Directory -Path $profilesRoot -Force|Out-Null

    $journal=[ordered]@{
        SchemaVersion=5;TransactionId=$BuildResult.Transaction.Id;ProfileId=$candidate.Id;Name=$candidate.Name;
        Distro=$candidate.Distro;WslName=$wslName;ProfileHash=$BuildResult.ProfileHash;
        ExportPath=$export;State='Prepare';CreatedAt=[DateTime]::UtcNow.ToString('o')
    }
    $journalPath=Join-Path $transactionRoot 'commit-journal.json'

    function Save-Journal {
        $journal|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $journalPath -Encoding UTF8
    }
    Save-Journal

    try {
        # ProfileEngine has already exported the accepted WSL environment exactly once.
        # Commit consumes that artifact and is forbidden from calling wsl --export again.
        $artifactHash=& $HashFile $export
        if([string]$artifactHash -ne [string]$BuildResult.ProfileHash.ToLowerInvariant()){
            throw "Accepted Profile artifact hash does not match ProfileHash for '$wslName'."
        }
        $journal.ExportedVhdxSha256=$artifactHash
        $journal.State='ExportVerified'
        Save-Journal

        $payloadRecord=[ordered]@{
            SchemaVersion=3;ProfileId=$candidate.Id;Name=$candidate.Name;Distro=$candidate.Distro;
            WslName=$wslName;Algorithm='SHA256';Hash=$artifactHash;
            Artifact=[IO.Path]::GetRelativePath($transactionRoot,$export);
            RecordedAt=[DateTime]::UtcNow.ToString('o')
        }
        $payloadRecordPath=Join-Path $transactionRoot 'export.hash.json'
        $payloadRecord|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $payloadRecordPath -Encoding UTF8

        $unregisterResult=& $UnregisterWsl $wslName
        if([int]$unregisterResult -ne 0){throw "Failed to unregister temporary Profile '$wslName' during commit."}
        $journal.State='TemporaryUnregistered';Save-Journal

        New-Item -ItemType Directory -Path $finalRoot -Force|Out-Null
        $finalWsl=Join-Path $finalRoot 'wsl';New-Item -ItemType Directory -Path $finalWsl -Force|Out-Null
        $finalVhdx=Join-Path $finalWsl 'ext4.vhdx'

        # Promote the exact accepted artifact. No second export is permitted.
        Move-Item -LiteralPath $export -Destination $finalVhdx -Force
        $journal.State='PayloadPromoted';Save-Journal

        $promotedHash=& $HashFile $finalVhdx
        if([string]$promotedHash -ne [string]$artifactHash){throw "Committed Profile payload hash mismatch for '$wslName'."}
        $journal.PromotedVhdxSha256=$promotedHash;Save-Journal

        $importResult=& $ImportInPlace $wslName $finalVhdx
        if([int]$importResult -ne 0){throw "Failed to import committed Profile '$wslName' in place."}
        $journal.State='WslRegistered';Save-Journal

        $registered=@(& $ListWsl)
        if($registered-notcontains$wslName){throw "Committed Profile '$wslName' is not registered with WSL."}
        $smoke=& $SmokeTest $wslName
        if([int]$smoke.ExitCode -ne 0 -or (($smoke.Output -join "`n") -notmatch 'DISTROSHELF_PROFILE_COMMIT_OK')){throw "Committed Profile '$wslName' failed its post-commit smoke test."}
        $journal.State='WslSmokeVerified';Save-Journal

        $record=[ordered]@{
            SchemaVersion=4;ProfileId=$candidate.Id;Name=$candidate.Name;Distro=$candidate.Distro;
            WslName=$wslName;PackageManager=$candidate.PackageManager;Terminal=$Terminal;
            ProfileHash=$BuildResult.ProfileHash;ExportedVhdxSha256=$artifactHash;CommittedAt=[DateTime]::UtcNow.ToString('o')
        }
        Write-DistroShelfJsonAtomically -Path (Join-Path $finalRoot 'profile.json') -Value $record

        # Registry publication is deliberately the final step.
        $committed=& $PublishProfile $candidate $Terminal $BuildResult.ProfileHash
        $journal.State='Committed';$journal|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $journalPath -Encoding UTF8

        Remove-Item -LiteralPath $transactionRoot -Recurse -Force -ErrorAction SilentlyContinue
        return [pscustomobject][ordered]@{Success=$true;Profile=$committed;Root=$finalRoot;WslName=$wslName;ProfileHash=$BuildResult.ProfileHash;ExportedVhdxSha256=$artifactHash}
    } catch {
        # Never leave a partially promoted Profile outside the transaction boundary.
        try {
            $registered=@(& $ListWsl)
            if($registered -contains $wslName){ [void](& $UnregisterWsl $wslName) }
        } catch {}
        if(Test-Path -LiteralPath $finalRoot){
            $recover=Join-Path $transactionRoot 'failed-commit'
            try {
                New-Item -ItemType Directory -Path $recover -Force|Out-Null
                Move-Item -LiteralPath $finalRoot -Destination (Join-Path $recover ([string]$candidate.Name)) -Force
            } catch {}
        }
        $journal.State='CommitFailed';$journal.Error=$_.Exception.Message;Save-Journal
        throw
    }
}
