# DistroShelf - reusable functional test engine

function Invoke-DistroShelfTestCommand {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][object]$Test)
    $output = & wsl.exe --distribution $WslName -- bash -lc ([string]$Test.Command) 2>&1
    $exitCode = $LASTEXITCODE
    $expected = if($null -ne $Test.ExpectedExitCode){[int]$Test.ExpectedExitCode}else{0}
    $passed = $exitCode -eq $expected
    if($passed -and $Test.ExpectedOutput){
        $passed = ([string]($output -join "`n")) -match [string]$Test.ExpectedOutput
    }
    [pscustomobject][ordered]@{
        Name=[string]$Test.Name
        Command=[string]$Test.Command
        Passed=$passed
        ExitCode=$exitCode
        ExpectedExitCode=$expected
        Output=(@($output) -join "`n")
    }
}

function Invoke-DistroShelfAcceptanceTests {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][object[]]$Tests)
    $results=@()
    foreach($test in @($Tests)){
        $r=Invoke-DistroShelfTestCommand -WslName $WslName -Test $test
        $results+=$r
    }
    [pscustomobject][ordered]@{
        Passed=(@($results|Where-Object{-not $_.Passed}).Count -eq 0 -and $results.Count -eq @($Tests).Count)
        Total=$results.Count
        PassedCount=@($results|Where-Object{$_.Passed}).Count
        FailedCount=@($results|Where-Object{-not $_.Passed}).Count
        Results=$results
    }
}

function Assert-DistroShelfAcceptance {
    param([Parameter(Mandatory)][object]$Result)
    if(-not $Result.Passed){
        $failed=@($Result.Results|Where-Object{-not $_.Passed}|ForEach-Object{"$($_.Name): exit $($_.ExitCode)"}) -join '; '
        throw "Acceptance test suite failed ($($Result.PassedCount)/$($Result.Total)): $failed"
    }
    return $true
}
