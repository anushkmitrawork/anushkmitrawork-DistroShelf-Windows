$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\Distro\ProviderContract.ps1')

$good = New-DistroShelfProvider -Distro 'Test' -PackageManager 'apt' -Stages @{
    rootfs = @{
        Track=@{Tests=@(@{Name='root';Command='true'})}
        Profile=@{Tests=@()}
    }
    podman = @{
        Track=@{Tests=@(@{Name='podman';Command='true'})}
        Profile=@{Tests=@(@{Name='podman';Command='true'})}
    }
} -TrackFinalTests @(@{Name='final';Command='true'}) -ProfileFinalTests @(@{Name='final';Command='true'})
$r=Test-DistroShelfProviderContract $good
if(-not $r.Valid){throw 'Valid provider was rejected.'}
Write-Host 'PASS valid provider contract'

$bad = New-DistroShelfProvider -Distro 'Broken' -PackageManager 'apt' -Stages @{
    podman = @{Track=@{Tests=@()};Profile=@{Tests=@()}}
} -TrackFinalTests @() -ProfileFinalTests @()
$r=Test-DistroShelfProviderContract $bad
if($r.Valid){throw 'Invalid provider was accepted.'}
Write-Host 'PASS invalid provider contract rejected'
