# DistroShelf - final acceptance gate

function Invoke-DistroShelfProfileAcceptance {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][object[]]$Tests)
    $result=Invoke-DistroShelfAcceptanceTests -WslName $WslName -Tests $Tests
    Assert-DistroShelfAcceptance $result
    return $result
}

function Invoke-DistroShelfTrackAcceptance {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][object[]]$Tests)
    $result=Invoke-DistroShelfAcceptanceTests -WslName $WslName -Tests $Tests
    Assert-DistroShelfAcceptance $result
    return $result
}
