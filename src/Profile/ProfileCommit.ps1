# DistroShelf - Profile commit boundary
. (Join-Path $PSScriptRoot '..\Engine\AtomicCommit.ps1')
. (Join-Path $PSScriptRoot '..\ProfileManager.ps1')

function Commit-DistroShelfProfileTransaction {
    param([Parameter(Mandatory)]$BuildResult,[Parameter(Mandatory)]$Reservation,[Parameter(Mandatory)][string]$Terminal)
    if(-not $BuildResult.Success){throw 'Cannot commit a failed Profile transaction.'}
    $candidate=$BuildResult.Candidate
    $candidateRoot=$BuildResult.Transaction.Root
    $wslName=[string]$candidate.WslName
    $profilesRoot=Join-Path $env:LOCALAPPDATA 'DistroShelf\profiles'
    $finalRoot=Join-Path $profilesRoot ([string]$candidate.Name)
    if(Test-Path -LiteralPath $finalRoot){throw "Committed Profile already exists: $finalRoot"}
    New-Item -ItemType Directory -Path $profilesRoot -Force|Out-Null

    $journal=[ordered]@{SchemaVersion=1;TransactionId=$BuildResult.Transaction.Id;ProfileId=$candidate.Id;Name=$candidate.Name;Distro=$candidate.Distro;WslName=$wslName;ProfileHash=$BuildResult.ProfileHash;State='Prepare';CreatedAt=[DateTime]::UtcNow.ToString('o')}
    $journalPath=Join-Path $candidateRoot 'commit-journal.json'
    $journal|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $journalPath -Encoding UTF8
    try {
        $finalWsl=Join-Path $finalRoot 'wsl';New-Item -ItemType Directory -Path $finalWsl -Force|Out-Null
        $export=Join-Path $candidateRoot 'profile-export.vhdx'
        & wsl.exe --export $wslName $export --format vhd 2>&1|Out-Null
        if($LASTEXITCODE-ne 0 -or -not(Test-Path -LiteralPath $export -PathType Leaf)){throw "Failed to export verified Profile '$wslName' for commit."}
        $finalVhdx=Join-Path $finalWsl 'ext4.vhdx'
        Copy-Item -LiteralPath $export -Destination $finalVhdx -Force
        $journal.State='Exported';$journal|ConvertTo-Json -Depth 20|Set-Content $journalPath -Encoding UTF8

        & wsl.exe --unregister $wslName 2>&1|Out-Null
        if($LASTEXITCODE-ne 0){throw "Failed to unregister temporary Profile '$wslName' during commit."}
        & wsl.exe --import-in-place $wslName $finalVhdx 2>&1|Out-Null
        if($LASTEXITCODE-ne 0){throw "Failed to import committed Profile '$wslName' in place."}
        $registered=@(& wsl.exe --list --quiet 2>$null)|ForEach-Object{($_-replace "`0",'').Trim()}|Where-Object{$_}
        if($registered-notcontains$wslName){throw "Committed Profile '$wslName' is not registered with WSL."}
        $smoke=& wsl.exe --distribution $wslName -- bash -lc 'printf DISTROSHELF_PROFILE_COMMIT_OK' 2>&1
        if($LASTEXITCODE-ne 0 -or (($smoke-join "`n") -notmatch 'DISTROSHELF_PROFILE_COMMIT_OK')){throw "Committed Profile '$wslName' failed its post-commit smoke test."}

        $journal.State='WslCommitted';$journal|ConvertTo-Json -Depth 20|Set-Content $journalPath -Encoding UTF8
        [ordered]@{SchemaVersion=1;ProfileId=$candidate.Id;Name=$candidate.Name;Distro=$candidate.Distro;WslName=$wslName;PackageManager=$candidate.PackageManager;Terminal=$Terminal;ProfileHash=$BuildResult.ProfileHash;CommittedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 20|Set-Content (Join-Path $finalRoot 'profile.json') -Encoding UTF8

        $committed=Commit-DistroShelfProfile -Candidate $candidate -Terminal $Terminal -ProfileHash $BuildResult.ProfileHash
        $journal.State='Committed';$journal|ConvertTo-Json -Depth 20|Set-Content $journalPath -Encoding UTF8
        Remove-Item -LiteralPath $candidateRoot -Recurse -Force -ErrorAction SilentlyContinue
        return [pscustomobject][ordered]@{Success=$true;Profile=$committed;Root=$finalRoot;WslName=$wslName;ProfileHash=$BuildResult.ProfileHash}
    } catch {
        $journal.State='CommitFailed';$journal.Error=$_.Exception.Message;$journal|ConvertTo-Json -Depth 20|Set-Content $journalPath -Encoding UTF8
        throw
    }
}
