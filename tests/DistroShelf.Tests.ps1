# Non-destructive tests for DistroShelf installer architecture.
# Run from repository root with:
# powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\DistroShelf.Tests.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'src'

$required = @(
    'ProfileManager.ps1','ProfileInstaller.ps1','Provisioning.ps1','RootfsProvider.ps1',
    'WslImporter.ps1','ProvisionProfile.ps1','DependencyEngine.ps1','InstallOrchestrator.ps1','DistroShelfSetup.ps1'
)

$failed = 0
foreach ($file in $required) {
    $path = Join-Path $src $file
    if (Test-Path -LiteralPath $path) { Write-Host "PASS  file exists: $file" }
    else { Write-Host "FAIL  missing: $file"; $failed++ }
}

. (Join-Path $src 'ProfileManager.ps1')
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("DistroShelf-Test-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$oldRoot = $script:DistroShelfProfileRoot
$oldFile = $script:DistroShelfProfileFile
try {
    $script:DistroShelfProfileRoot = $tempRoot
    $script:DistroShelfProfileFile = Join-Path $tempRoot 'profiles.json'
    Initialize-DistroShelfProfileStore

    $u1 = New-DistroShelfProfile -Distro Ubuntu
    $u2 = New-DistroShelfProfile -Distro Ubuntu
    $f1 = New-DistroShelfProfile -Distro Fedora
    $d1 = New-DistroShelfProfile -Distro Debian
    $d2 = New-DistroShelfProfile -Distro Debian

    if ($u1.Name -eq 'Ubuntu1' -and $u2.Name -eq 'Ubuntu2' -and $f1.Name -eq 'Fedora1' -and $d1.Name -eq 'Debian1' -and $d2.Name -eq 'Debian2') {
        Write-Host 'PASS  independent profile numbering'
    } else {
        Write-Host "FAIL  profile numbering: $($u1.Name), $($u2.Name), $($f1.Name), $($d1.Name), $($d2.Name)"; $failed++
    }

    # A GUI preview is not persisted and therefore does not consume the next number.
    $preview = [pscustomobject]@{Id='__PREVIEW__';Name='Ubuntu3';Distro='Ubuntu';WslName='DistroShelf-Ubuntu3';Status='Pending'}
    $next = Get-NextDistroShelfProfileNumber -Distro Ubuntu
    if ($preview.Name -eq 'Ubuntu3' -and $next -eq 3 -and @(Get-DistroShelfProfiles | Where-Object { $_.Name -eq 'Ubuntu3' }).Count -eq 0) {
        Write-Host 'PASS  pending previews do not change next committed profile number'
    } else {
        Write-Host "FAIL  pending preview numbering: preview=$($preview.Name), next=$next"; $failed++
    }

    $u3 = New-DistroShelfProfile -Distro Ubuntu
    if ($u3.Name -eq 'Ubuntu3' -and $u3.Status -eq 'Pending') {
        Write-Host 'PASS  next committed profile uses preview number'
    } else {
        Write-Host "FAIL  next committed Ubuntu profile: $($u3.Name)/$($u3.Status)"; $failed++
    }

    # Simulate a successful first Debian installation by committing d1, then create d3.
    Set-DistroShelfProfileStatus -Id $d1.Id -Status 'Ready' | Out-Null
    $d3 = New-DistroShelfProfile -Distro Debian
    if ($d1.Name -eq 'Debian1' -and $d1.Status -eq 'Ready' -and $d2.Name -eq 'Debian2' -and $d3.Name -eq 'Debian3' -and $d2.Status -eq 'Pending') {
        Write-Host 'PASS  installed distro creates independent next profile'
    } else {
        Write-Host "FAIL  repeated installed distro profile: $($d1.Name)/$($d1.Status), $($d2.Name)/$($d2.Status), $($d3.Name)/$($d3.Status)"; $failed++
    }

    $names = @(Get-DistroShelfProfiles | Select-Object -ExpandProperty WslName)
    if (($names | Select-Object -Unique).Count -eq $names.Count) { Write-Host 'PASS  profile records remain independent' } else { Write-Host 'FAIL  profile records are not independent'; $failed++ }

    $found = Get-DistroShelfProfileById -Id $u2.Id
    if ($found -and $found.Name -eq 'Ubuntu2') { Write-Host 'PASS  profile lookup by ID' } else { Write-Host 'FAIL  profile lookup by ID'; $failed++ }

    Set-DistroShelfProfileTerminal -Id $u2.Id -Terminal 'Kitty' | Out-Null
    Set-DistroShelfProfileStatus -Id $u2.Id -Status 'Ready' | Out-Null
    $updated = Get-DistroShelfProfileById -Id $u2.Id
    if ($updated.Status -eq 'Ready' -and $updated.Terminal -eq 'Kitty') { Write-Host 'PASS  profile status and terminal persist independently' } else { Write-Host 'FAIL  profile status or terminal persistence'; $failed++ }

    $remaining = @(Get-DistroShelfProfiles)
    if (($remaining | Where-Object Id -eq $u1.Id) -and ($remaining | Where-Object Id -eq $u2.Id) -and ($remaining | Where-Object Id -eq $f1.Id) -and ($remaining | Where-Object Id -eq $d1.Id) -and ($remaining | Where-Object Id -eq $d2.Id) -and ($remaining | Where-Object Id -eq $d3.Id)) { Write-Host 'PASS  profile records survive updates' } else { Write-Host 'FAIL  profile records lost during updates'; $failed++ }
} finally {
    $script:DistroShelfProfileRoot = $oldRoot
    $script:DistroShelfProfileFile = $oldFile
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$unsafe = @('--unregister', 'wsl --unregister')
foreach ($file in @('WslImporter.ps1','InstallOrchestrator.ps1')) {
    $text = Get-Content -LiteralPath (Join-Path $src $file) -Raw
    foreach ($token in $unsafe) {
        if ($text -match [regex]::Escape($token)) { Write-Host "FAIL  destructive token '$token' found in $file"; $failed++ }
    }
}

if ($failed -gt 0) { Write-Host "`n$failed test(s) failed."; exit 1 }
Write-Host "`nAll non-destructive architecture tests passed."
exit 0
