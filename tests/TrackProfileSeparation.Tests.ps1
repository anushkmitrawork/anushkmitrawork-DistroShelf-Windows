# DistroShelf - I.1 Track/Profile separation contract tests
# Track and Profile are separate transactional lifecycles and stores.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/Engine/TransactionEngine.ps1')

$temp = Join-Path ([IO.Path]::GetTempPath()) ("DistroShelf-I1-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    $track = New-DistroShelfTransaction -Kind Track -Distro Ubuntu -BaseRoot $temp
    $profile = New-DistroShelfTransaction -Kind Profile -Distro Ubuntu -BaseRoot $temp

    if ([string]$track.Kind -ne 'Track') { throw 'Track transaction kind is not Track.' }
    if ([string]$profile.Kind -ne 'Profile') { throw 'Profile transaction kind is not Profile.' }
    if ([string]$track.Root -eq [string]$profile.Root) { throw 'Track and Profile transaction roots must be distinct.' }
    if ([string]$track.Root -notlike (Join-Path $temp 'Attempts*')) { throw 'Track transaction is not isolated under Attempts.' }
    if ([string]$profile.Root -notlike (Join-Path $temp 'Attempts*')) { throw 'Profile transaction is not isolated under Attempts.' }

    # A Track transaction and Profile transaction must not be able to masquerade
    # as one another through their persisted transaction records.
    $trackRecord = Join-Path $track.Root 'transaction.json'
    $profileRecord = Join-Path $profile.Root 'transaction.json'
    if (-not (Test-Path -LiteralPath $trackRecord -PathType Leaf)) { throw 'Track transaction record missing.' }
    if (-not (Test-Path -LiteralPath $profileRecord -PathType Leaf)) { throw 'Profile transaction record missing.' }

    $trackData = Get-Content -LiteralPath $trackRecord -Raw | ConvertFrom-Json
    $profileData = Get-Content -LiteralPath $profileRecord -Raw | ConvertFrom-Json
    if ([string]$trackData.Kind -ne 'Track') { throw 'Persisted Track transaction kind is incorrect.' }
    if ([string]$profileData.Kind -ne 'Profile') { throw 'Persisted Profile transaction kind is incorrect.' }

    Write-Host 'I.1 Track/Profile separation: PASS'
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
