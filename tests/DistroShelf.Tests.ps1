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
    if (Test-Path -LiteralPath $path) {
        Write-Host "PASS  file exists: $file"
    } else {
        Write-Host "FAIL  missing: $file"
        $failed++
    }
}

# Load the profile manager and validate profile naming without creating a real
# profile. This test uses a temporary profile store and restores the variables.
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

    if ($p1.WslName -eq 'DistroShelf-Ubuntu1' -and $p2.WslName -eq 'DistroShelf-Ubuntu2' -and $p3.WslName -eq 'DistroShelf-Fedora1') {
        Write-Host 'PASS  independent profile numbering'
    } else {
        Write-Host "FAIL  profile numbering: $($p1.WslName), $($p2.WslName), $($p3.WslName)"
        $failed++
    }

    $names = @(Get-DistroShelfProfiles | Select-Object -ExpandProperty WslName)
    if ($names.Count -eq 3 -and ($names | Select-Object -Unique).Count -eq 3) {
        Write-Host 'PASS  profile records remain independent'
    } else {
        Write-Host 'FAIL  profile records are not independent'
        $failed++
    }
} finally {
    $script:DistroShelfProfileRoot = $oldRoot
    $script:DistroShelfProfileFile = $oldFile
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# Static safety checks: these files must not contain destructive unregister
# commands as part of the normal installation path.
$unsafe = @('--unregister', 'wsl --unregister')
foreach ($file in @('WslImporter.ps1','InstallOrchestrator.ps1')) {
    $text = Get-Content -LiteralPath (Join-Path $src $file) -Raw
    foreach ($token in $unsafe) {
        if ($text -match [regex]::Escape($token)) {
            Write-Host "FAIL  destructive token '$token' found in $file"
            $failed++
        }
    }
}

if ($failed -gt 0) {
    Write-Host "`n$failed test(s) failed."
    exit 1
}

Write-Host "`nAll non-destructive architecture tests passed."
exit 0
