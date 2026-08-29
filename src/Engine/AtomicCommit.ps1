# DistroShelf - commit helpers

function Move-DistroShelfDirectoryAtomic {
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination)
    if(-not(Test-Path -LiteralPath $Source -PathType Container)){throw "Commit source does not exist: $Source"}
    $parent=Split-Path -Parent $Destination
    if($parent -and -not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    if(Test-Path -LiteralPath $Destination){throw "Commit destination already exists: $Destination"}
    Move-Item -LiteralPath $Source -Destination $Destination -Force
}

function Write-DistroShelfJsonAtomically {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object]$Value)
    $parent=Split-Path -Parent $Path
    if($parent -and -not(Test-Path $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    $tmp="$Path.tmp"
    $Value|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}
