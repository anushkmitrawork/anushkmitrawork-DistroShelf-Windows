# DistroShelf - stage command executor

function Invoke-DistroShelfCommand {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$Command,[switch]$CaptureOutput)
    $output=& wsl.exe --distribution $WslName -- bash -lc $Command 2>&1
    $code=$LASTEXITCODE
    $result=[pscustomobject]@{ExitCode=$code;Output=(@($output)-join "`n")}
    if($CaptureOutput){return $result}
    if($code-ne 0){throw "Command failed in '$WslName' with exit code $code: $Command`n$($result.Output)"}
    return $result
}

function Invoke-DistroShelfStageTests {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][object[]]$Tests)
    $results=@()
    foreach($test in @($Tests)){
        $r=Invoke-DistroShelfCommand -WslName $WslName -Command ([string]$test.Command) -CaptureOutput
        $expected=if($null -ne $test.ExpectedExitCode){[int]$test.ExpectedExitCode}else{0}
        $passed=$r.ExitCode -eq $expected
        if($passed -and $test.ExpectedOutput){$passed=$r.Output -match [string]$test.ExpectedOutput}
        $results+=[pscustomobject][ordered]@{Name=[string]$test.Name;Command=[string]$test.Command;Passed=$passed;ExitCode=$r.ExitCode;ExpectedExitCode=$expected;Output=$r.Output}
    }
    [pscustomobject][ordered]@{Passed=(@($results|Where-Object{-not $_.Passed}).Count-eq 0 -and $results.Count-eq @($Tests).Count);Total=$results.Count;PassedCount=@($results|Where-Object{$_.Passed}).Count;FailedCount=@($results|Where-Object{-not $_.Passed}).Count;Results=$results}
}
