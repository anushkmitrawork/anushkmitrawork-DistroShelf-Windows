# DistroShelf - final acceptance gate
. (Join-Path $PSScriptRoot 'TestEngine.ps1')

function Invoke-DistroShelfProfileAcceptance {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][object[]]$Tests)
    $result=Invoke-DistroShelfAcceptanceTests -WslName $WslName -Tests $Tests
    Assert-DistroShelfAcceptance $result | Out-Null
    return $result
}

function Invoke-DistroShelfTrackAcceptance {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][object[]]$Tests)
    $result=Invoke-DistroShelfAcceptanceTests -WslName $WslName -Tests $Tests
    Assert-DistroShelfAcceptance $result | Out-Null
    return $result
}
