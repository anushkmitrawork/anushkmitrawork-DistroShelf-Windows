# DistroShelf - deterministic integrity hash engine

function Get-DistroShelfTreeHash {
    param([Parameter(Mandatory)][string]$Root,[string[]]$ExcludeRelativePath=@())
    if(-not(Test-Path -LiteralPath $Root -PathType Container)){throw "Cannot hash missing directory: $Root"}
    $rootFull=(Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
    $excluded=@($ExcludeRelativePath|ForEach-Object{$_.TrimStart('\','/').Replace('\','/').TrimEnd('/')})
    $lines=New-Object System.Collections.Generic.List[string]
    foreach($file in @(Get-ChildItem -LiteralPath $rootFull -Recurse -File|Sort-Object FullName)){
        $relative=$file.FullName.Substring($rootFull.Length).TrimStart('\','/').Replace('\','/')
        if(@($excluded|Where-Object{$relative-eq$_-or$relative.StartsWith("$_/")}).Count){continue}
        $hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        [void]$lines.Add("$relative`t$hash`t$($file.Length)")
    }
    $sha=[Security.Cryptography.SHA256]::Create();try{$bytes=[Text.Encoding]::UTF8.GetBytes(($lines-join "`n"));return ([BitConverter]::ToString($sha.ComputeHash($bytes))-replace '-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Write-DistroShelfHashRecord {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Stage,[Parameter(Mandatory)][string]$Hash,[Parameter(Mandatory)][object]$TestResult)
    $parent=Split-Path -Parent $Path;if($parent-and-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    $record=[ordered]@{SchemaVersion=1;Stage=$Stage;Hash=$Hash;Tests=$TestResult;CreatedAt=[DateTime]::UtcNow.ToString('o')};$tmp="$Path.tmp";$record|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $Path -Force;return [pscustomobject]$record
}
function Test-DistroShelfHashRecord {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Stage,[string[]]$ExcludeRelativePath=@())
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $false};try{$r=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json;if([string]$r.Stage-ne$Stage-or[string]::IsNullOrWhiteSpace([string]$r.Hash)){return $false};return (Get-DistroShelfTreeHash -Root $Root -ExcludeRelativePath $ExcludeRelativePath)-eq([string]$r.Hash).ToLowerInvariant()}catch{return $false}
}
