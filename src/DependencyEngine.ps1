# DistroShelf - generic stage engine
# Distro-specific implementation lives under src/Distro.
# This engine knows transaction semantics, not distro package-manager commands.

function Invoke-DistroShelfCommand {
    param(
        [Parameter(Mandatory)][string]$WslName,
        [Parameter(Mandatory)][string]$Command,
        [switch]$CaptureOutput
    )
    $output = & wsl.exe --distribution $WslName -- bash -lc $Command 2>&1
    $code = $LASTEXITCODE
    if ($CaptureOutput) { return [pscustomobject]@{ ExitCode=$code; Output=(@($output) -join "`n") } }
    if ($code -ne 0) { throw "Command failed in '$WslName' with exit code $code: $Command`n$(@($output) -join "`n")" }
}

function Invoke-DistroShelfStageTests {
    param(
        [Parameter(Mandatory)][string]$WslName,
        [Parameter(Mandatory)][object[]]$Tests
    )
    $results = @()
    foreach ($test in @($Tests)) {
        $r = Invoke-DistroShelfCommand -WslName $WslName -Command ([string]$test.Command) -CaptureOutput
        $passed = $r.ExitCode -eq 0
        $results += [pscustomobject][ordered]@{ Name=[string]$test.Name; Command=[string]$test.Command; Passed=$passed; ExitCode=$r.ExitCode; Output=$r.Output }
        if (-not $passed) { break }
    }
    [pscustomobject][ordered]@{ Passed=(@($results | Where-Object { -not $_.Passed }).Count -eq 0 -and $results.Count -eq @($Tests).Count); Results=$results }
}

function Get-DistroShelfStageHash {
    param([Parameter(Mandatory)][string]$Root)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Cannot hash missing stage root: $Root" }
    $items = Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName
    $buffer = New-Object System.Text.StringBuilder
    foreach ($item in $items) {
        $relative = $item.FullName.Substring($Root.Length).TrimStart('\','/')
        $fileHash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        [void]$buffer.Append($relative); [void]$buffer.Append("`n"); [void]$buffer.Append($fileHash); [void]$buffer.Append("`n")
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($buffer.ToString())
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-','').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Write-DistroShelfHashRecord {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Stage,[Parameter(Mandatory)][string]$Hash,[Parameter(Mandatory)][object]$Tests)
    $record = [ordered]@{ SchemaVersion=1; Stage=$Stage; Hash=$Hash; Tests=$Tests; CreatedAt=[DateTime]::UtcNow.ToString('o') }
    $tmp = "$Path.tmp"
    $record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Test-DistroShelfHashRecord {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$ExpectedStage)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $r = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        if ([string]$r.Stage -ne $ExpectedStage -or [string]::IsNullOrWhiteSpace([string]$r.Hash)) { return $false }
        return (Get-DistroShelfStageHash -Root $Root) -eq ([string]$r.Hash).ToLowerInvariant()
    } catch { return $false }
}

function Invoke-DistroShelfTrackedStage {
    param(
        [Parameter(Mandatory)][string]$WslName,
        [Parameter(Mandatory)][object]$Stage,
        [Parameter(Mandatory)][string]$ArtifactRoot,
        [Parameter(Mandatory)][string]$HashPath
    )
    $tests = @()
    if ($Stage.Tests) { $tests = @($Stage.Tests) }
    $testResult = Invoke-DistroShelfStageTests -WslName $WslName -Tests $tests
    if (-not $testResult.Passed) { throw "Stage '$($Stage.Id)' failed verification." }
    $hash = Get-DistroShelfStageHash -Root $ArtifactRoot
    Write-DistroShelfHashRecord -Path $HashPath -Stage $Stage.Id -Hash $hash -Tests $testResult
    return [pscustomobject][ordered]@{ Stage=$Stage.Id; Hash=$hash; Tests=$testResult; Verified=$true }
}
