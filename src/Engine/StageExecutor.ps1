# DistroShelf - stage command/test executor

function Invoke-DistroShelfCommand {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][string]$Command,[switch]$CaptureOutput)
    if([string]::IsNullOrWhiteSpace($Command)){throw 'Command cannot be empty.'}
    $output=& wsl.exe --distribution $WslName -- bash -lc $Command 2>&1
    $code=$LASTEXITCODE
    $result=[pscustomobject][ordered]@{ExitCode=$code;Output=(@($output)-join "`n")}
    if($CaptureOutput){return $result}
    if($code-ne 0){throw "Command failed in '$WslName' with exit code $code: $Command`n$($result.Output)"}
    return $result
}

function Invoke-DistroShelfStageTests {
    param([Parameter(Mandatory)][string]$WslName,[Parameter(Mandatory)][object[]]$Tests,[switch]$StopOnFailure)
    if(@($Tests).Count -eq 0){return [pscustomobject][ordered]@{Passed=$false;Total=0;PassedCount=0;FailedCount=0;Results=@()}}
    $results=@()
    foreach($test in @($Tests)){
        $r=Invoke-DistroShelfCommand -WslName $WslName -Command ([string]$test.Command) -CaptureOutput
        $expected=if($null -ne $test.ExpectedExitCode){[int]$test.ExpectedExitCode}else{0}
        $passed=$r.ExitCode -eq $expected
        if($passed -and -not [string]::IsNullOrWhiteSpace([string]$test.ExpectedOutput)){$passed=$r.Output -match [string]$test.ExpectedOutput}
        $results+=[pscustomobject][ordered]@{Name=[string]$test.Name;Command=[string]$test.Command;Passed=$passed;ExitCode=$r.ExitCode;ExpectedExitCode=$expected;ExpectedOutput=[string]$test.ExpectedOutput;Output=$r.Output}
        if($StopOnFailure -and -not $passed){break}
    }
    [pscustomobject][ordered]@{Passed=(@($results|Where-Object{-not $_.Passed}).Count-eq 0 -and $results.Count-eq @($Tests).Count);Total=$results.Count;PassedCount=@($results|Where-Object{$_.Passed}).Count;FailedCount=@($results|Where-Object{-not $_.Passed}).Count;Results=$results}
}

function Invoke-DistroShelfCommands {
    param([Parameter(Mandatory)][string]$WslName,[string[]]$Commands)
    foreach($cmd in @($Commands)){if(-not [string]::IsNullOrWhiteSpace([string]$cmd)){Invoke-DistroShelfCommand -WslName $WslName -Command $cmd|Out-Null}}
}
