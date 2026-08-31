# DistroShelf for Windows - verified WSL import engine
. (Join-Path $PSScriptRoot 'ProfileManager.ps1')
. (Join-Path $PSScriptRoot 'RootfsProvider.ps1')

function Invoke-DistroShelfWslImport {
    param([Parameter(Mandatory)][pscustomobject]$Profile,[Parameter(Mandatory)][string]$RootfsPath,[Parameter(Mandatory)][string]$ExpectedSha256,[string]$StorageRoot=(Join-Path $env:LOCALAPPDATA 'DistroShelf\wsl'))
    if(-not(Get-Command wsl.exe -ErrorAction SilentlyContinue)){throw 'wsl.exe was not found. WSL must be installed before creating a DistroShelf profile.'}
    if(-not(Test-Path -LiteralPath $RootfsPath -PathType Leaf)){throw "Rootfs file not found: $RootfsPath"}
    $actual=(Get-FileHash -LiteralPath $RootfsPath -Algorithm SHA256).Hash.ToLowerInvariant();$expected=($ExpectedSha256-replace '^0x','').ToLowerInvariant();if($actual-ne$expected){throw "Refusing import: rootfs SHA-256 mismatch. Expected $expected, received $actual."}
    $existing=@((& wsl.exe --list --quiet 2>$null)|%{($_-replace "`0",'').Trim()}|?{$_});if($existing -contains $Profile.WslName){throw "Refusing import: WSL distribution '$($Profile.WslName)' already exists."}
    $installLocation=Join-Path $StorageRoot $Profile.WslName;if(Test-Path -LiteralPath $installLocation){throw "Refusing import: installation directory already exists: $installLocation"}
    New-Item -ItemType Directory -Path $installLocation -Force|Out-Null
    & wsl.exe --import $Profile.WslName $installLocation $RootfsPath --version 2;if($LASTEXITCODE-ne 0){throw "WSL import failed for '$($Profile.WslName)' with exit code $LASTEXITCODE."}

    # Enable systemd via Windows UNC path (does NOT require the distro to be running).
    # Ubuntu 22.04+ rootfs requires systemd for user session startup; without this,
    # every bash -lc invocation fails with "Failed to start the systemd user session".
    $wslConfUnc = "\\wsl$\$($Profile.WslName)\etc\wsl.conf"
    try {
        # Ensure /etc directory exists (it always should in a Linux rootfs)
        $etcDir = "\\wsl$\$($Profile.WslName)\etc"
        if(-not (Test-Path -LiteralPath $etcDir -PathType Container)){
            New-Item -ItemType Directory -Path $etcDir -Force | Out-Null
        }
        # Write wsl.conf with systemd enabled
        "[boot]" | Out-File -FilePath $wslConfUnc -Encoding ascii -Force
        "systemd=true" | Out-File -FilePath $wslConfUnc -Encoding ascii -Append
        # Full WSL shutdown ensures the distro restarts cleanly with systemd
        & wsl.exe --shutdown 2>$null | Out-Null
        Start-Sleep -Seconds 3
    } catch {
        # Non-fatal: if UNC write fails, the verification loop below will catch it
    }

    $registered=$false;$lastVerify=''
    for($attempt=0;$attempt-lt20;$attempt++){
        $verify=@(& wsl.exe --list --verbose 2>&1)-join "`n"
        $quiet=@(& wsl.exe --list --quiet 2>&1)|ForEach-Object{($_-replace "`0",'').Trim()}|Where-Object{$_}
        if(($quiet -contains [string]$Profile.WslName) -or ($verify -match [regex]::Escape([string]$Profile.WslName))){
            $probe=& wsl.exe --distribution $Profile.WslName -- bash -lc 'true' 2>&1
            if($LASTEXITCODE -eq 0){$registered=$true;break}
            $lastVerify=($probe -join "`n")
        }else{$lastVerify=$verify}
        Start-Sleep -Seconds 1
    }
    if(-not $registered){throw "WSL import completed without a verifiable '$($Profile.WslName)' registration. $lastVerify"}
    [pscustomobject][ordered]@{ProfileId=$Profile.Id;WslName=$Profile.WslName;InstallLocation=$installLocation;RootfsSha256=$actual;Imported=$true}
}
