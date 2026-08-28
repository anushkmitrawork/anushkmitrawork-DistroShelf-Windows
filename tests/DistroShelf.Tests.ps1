# Non-destructive tests for DistroShelf installer architecture.
# Run from repository root with:
# powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\DistroShelf.Tests.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'src'

$required = @(
    'ProfileManager.ps1',
    'ProfileInstaller.ps1',
    'Provisioning.ps1',
    'RootfsProvider.ps1',
    'WslImporter.ps1',
    'ProvisionProfile.ps1',
    'DependencyEngine.ps1',
    'InstallOrchestrator.ps1',
    'DistroShelfSetup.ps1'
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

    $p1 = New-DistroShelfProfile -Distro Ubuntu
    $p2 = New-DistroShelfProfile -Distro Ubuntu
    $p3 = New-DistroShelfProfile -Distro Fedora
    $debian1 = New-DistroShelfProfile -Distro Debian
    Set-DistroShelfProfileStatus -Id $debian1.Id -Status 'Ready' | Out-Null
    $debian2 = New-DistroShelfProfile -Distro Debian

    if ($p1.WslName -eq 'DistroShelf-Ubuntu1' -and $p2.WslName -eq 'DistroShelf-Ubuntu2' -and $p3.WslName -eq 'DistroShelf-Fedora1') {
        Write-Host 'PASS  independent profile numbering'
    } else {
        Write-Host "FAIL  profile numbering: $($p1.WslName), $($p2.WslName), $($p3.WslName)"; $failed++
    }

    if ($debian1.Name -eq 'Debian1' -and $debian1.Status -eq 'Ready' -and $debian2.Name -eq 'Debian2' -and $debian2.Status -eq 'Pending' -and $debian1.WslName -ne $debian2.WslName) {
        Write-Host 'PASS  installed distro creates independent next profile'
    } else {
        Write-Host "FAIL  repeated installed distro profile: $($debian1.Name)/$($debian1.Status), $($debian2.Name)/$($debian2.Status)"; $failed++
    }

    $names = @(Get-DistroShelfProfiles | Select-Object -ExpandProperty WslName)
    if ($names.Count -eq 5 -and ($names | Select-Object -Unique).Count -eq 5) {
        Write-Host 'PASS  profile records remain independent'
    } else { Write-Host 'FAIL  profile records are not independent'; $failed++ }

    $found = Get-DistroShelfProfileById -Id $p2.Id
    if ($found -and $found.Name -eq 'Ubuntu2') { Write-Host 'PASS  profile lookup by ID' }
    else { Write-Host 'FAIL  profile lookup by ID'; $failed++ }

    Set-DistroShelfProfileTerminal -Id $p2.Id -Terminal 'Kitty' | Out-Null
    Set-DistroShelfProfileStatus -Id $p2.Id -Status 'Ready' | Out-Null
    $updated = Get-DistroShelfProfileById -Id $p2.Id
    if ($updated.Status -eq 'Ready' -and $updated.Terminal -eq 'Kitty') {
        Write-Host 'PASS  profile status and terminal persist independently'
    } else { Write-Host 'FAIL  profile status or terminal persistence'; $failed++ }

    $remaining = @(Get-DistroShelfProfiles)
    if (($remaining | Where-Object Id -eq $p1.Id) -and ($remaining | Where-Object Id -eq $p2.Id) -and ($remaining | Where-Object Id -eq $p3.Id) -and ($remaining | Where-Object Id -eq $debian1.Id) -and ($remaining | Where-Object Id -eq $debian2.Id)) {
        Write-Host 'PASS  profile records survive updates'
    } else { Write-Host 'FAIL  profile records lost during updates'; $failed++ }
} finally {
    $script:DistroShelfProfileRoot = $oldRoot
    $script:DistroShelfProfileFile = $oldFile
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$unsafe = @('--unregister', 'wsl --unregister')
foreach ($file in @('WslImporter.ps1','InstallOrchestrator.ps1')) {
    $text = Get-Content -LiteralPath (Join-Path $src $file) -Raw
    foreach ($token in $unsafe) {
        if ($text -match [regex]::Escape($token)) {
            Write-Host "FAIL  destructive token '$token' found in $file"; $failed++
        }
    }
}

if ($failed -gt 0) { Write-Host "`n$failed test(s) failed."; exit 1 }
Write-Host "`nAll non-destructive architecture tests passed."
exit 0
