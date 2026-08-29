# Non-destructive tests for per-distro Track 0 architecture.
# Run from repository root with:
# powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\DistroTrack.Tests.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'src'

$failed = 0

foreach ($file in @('DistroTrackManager.ps1','RootfsProvider.ps1','DependencyEngine.ps1')) {
    if (Test-Path -LiteralPath (Join-Path $src $file)) { Write-Host "PASS  file exists: $file" }
    else { Write-Host "FAIL  missing: $file"; $failed++ }
}

. (Join-Path $src 'DistroTrackManager.ps1')

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("DistroShelf-Track-Test-" + [guid]::NewGuid())
$oldRoot = $script:DistroShelfTrackRoot
try {
    $script:DistroShelfTrackRoot = $tempRoot

    $expected = @{
        'Ubuntu'='Ubuntu0'
        'Debian'='Debian0'
        'Fedora'='Fedora0'
        'Arch Linux'='ArchLinux0'
        'openSUSE'='openSUSE0'
    }

    foreach ($distro in $expected.Keys) {
        $track = Initialize-DistroShelfTrack $distro
        $ok = ($track.Name -eq $expected[$distro])
        foreach ($component in @('Distro','Podman','Distrobox','Flatpak','DistroShelf','metadata')) {
            if (-not (Test-Path -LiteralPath (Join-Path $track.Root $component) -PathType Container)) { $ok = $false }
        }
        if ($ok) { Write-Host "PASS  track layout: $distro -> $($track.Name)" }
        else { Write-Host "FAIL  track layout: $distro"; $failed++ }
    }

    $u = Get-DistroShelfTrackDefinition 'Ubuntu'
    $f = Get-DistroShelfTrackDefinition 'Fedora'
    if ($u.Root -ne $f.Root -and $u.Name -eq 'Ubuntu0' -and $f.Name -eq 'Fedora0') {
        Write-Host 'PASS  distro tracks are independent'
    } else { Write-Host 'FAIL  distro tracks are not independent'; $failed++ }

    Write-DistroShelfTrackManifest -Distro 'Ubuntu' -RootfsFile 'Ubuntu-amd64.wsl' -RootfsSha256 ('a' * 64) -Podman:$true -Distrobox:$false -Flatpak:$true -DistroShelf:$false
    if ((Test-DistroShelfTrackDependencyReady -Distro 'Ubuntu' -Component 'Podman') -and -not (Test-DistroShelfTrackDependencyReady -Distro 'Ubuntu' -Component 'Distrobox')) {
        Write-Host 'PASS  track dependency readiness persists independently'
    } else { Write-Host 'FAIL  track dependency readiness'; $failed++ }

    Set-DistroShelfTrackDependencyReady -Distro 'Ubuntu' -Component 'Distrobox'
    if (Test-DistroShelfTrackDependencyReady -Distro 'Ubuntu' -Component 'Distrobox') {
        Write-Host 'PASS  track dependency state updates independently'
    } else { Write-Host 'FAIL  track dependency state update'; $failed++ }
} finally {
    $script:DistroShelfTrackRoot = $oldRoot
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failed -gt 0) { Write-Host "`n$failed test(s) failed."; exit 1 }
Write-Host "`nAll non-destructive Track 0 tests passed."
exit 0
