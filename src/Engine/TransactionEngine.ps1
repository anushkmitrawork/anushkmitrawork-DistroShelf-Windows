# DistroShelf - atomic transaction primitives

function New-DistroShelfTransaction {
    param([Parameter(Mandatory)][ValidateSet('Track','Profile')][string]$Kind,[Parameter(Mandatory)][string]$Distro)
    $id=[guid]::NewGuid().ToString('N')
    $root=Join-Path $env:LOCALAPPDATA "DistroShelf\Troubleshoot\$Kind-$Distro-$id"
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    [pscustomobject][ordered]@{Id=$id;Kind=$Kind;Distro=$Distro;Root=$root;StartedAt=[DateTime]::UtcNow.ToString('o');State='Running'}
}

function Write-DistroShelfTransactionRecord {
    param([Parameter(Mandatory)]$Transaction,[string]$State='Running',[object]$Data)
    $record=[ordered]@{SchemaVersion=1;Id=$Transaction.Id;Kind=$Transaction.Kind;Distro=$Transaction.Distro;State=$State;StartedAt=$Transaction.StartedAt;UpdatedAt=[DateTime]::UtcNow.ToString('o');Data=$Data}
    $record|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $Transaction.Root 'transaction.json') -Encoding UTF8
}

function Move-DistroShelfTransactionToTroubleshoot {
    param([Parameter(Mandatory)]$Transaction,[Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)
    $errorPath=Join-Path $Transaction.Root 'failure.txt'
    $ErrorRecord | Out-String -Width 4096 | Set-Content -LiteralPath $errorPath -Encoding UTF8
    Write-DistroShelfTransactionRecord -Transaction $Transaction -State 'Failed' -Data @{Error=$ErrorRecord.Exception.Message}
    return $Transaction.Root
}

function Complete-DistroShelfTransaction {
    param([Parameter(Mandatory)]$Transaction)
    Write-DistroShelfTransactionRecord -Transaction $Transaction -State 'Verified'
    $Transaction.State='Verified'
    return $Transaction
}
