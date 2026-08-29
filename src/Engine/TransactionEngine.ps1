# DistroShelf - atomic transaction primitives

function New-DistroShelfTransaction {
    param([Parameter(Mandatory)][ValidateSet('Track','Profile')][string]$Kind,[Parameter(Mandatory)][string]$Distro)
    $id=[guid]::NewGuid().ToString('N')
    $root=Join-Path (Join-Path $env:LOCALAPPDATA 'DistroShelf\Attempts') "$Kind-$Distro-$id"
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    [pscustomobject][ordered]@{Id=$id;Kind=$Kind;Distro=$Distro;Root=$root;StartedAt=[DateTime]::UtcNow.ToString('o');State='Running'}
}

function Write-DistroShelfTransactionRecord {
    param([Parameter(Mandatory)]$Transaction,[ValidateSet('Running','Verified','Failed')][string]$State='Running',[object]$Data)
    $record=[ordered]@{SchemaVersion=1;Id=$Transaction.Id;Kind=$Transaction.Kind;Distro=$Transaction.Distro;State=$State;StartedAt=$Transaction.StartedAt;UpdatedAt=[DateTime]::UtcNow.ToString('o');Data=$Data}
    $path=Join-Path $Transaction.Root 'transaction.json';$tmp="$path.tmp"
    $record|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Move-DistroShelfTransactionToTroubleshoot {
    param([Parameter(Mandatory)]$Transaction,[Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)
    $Transaction.State='Failed'
    Write-DistroShelfTransactionRecord -Transaction $Transaction -State 'Failed' -Data @{Error=$ErrorRecord.Exception.Message;Category=[string]$ErrorRecord.CategoryInfo;Position=[string]$ErrorRecord.InvocationInfo.PositionMessage}
    $failedRoot=$Transaction.Root
    $troubleshootRoot=Join-Path $env:LOCALAPPDATA 'DistroShelf\Troubleshoot'
    if(!(Test-Path $troubleshootRoot)){New-Item -ItemType Directory -Path $troubleshootRoot -Force|Out-Null}
    $destination=Join-Path $troubleshootRoot (Split-Path $failedRoot -Leaf)
    if(Test-Path $destination){$destination=Join-Path $troubleshootRoot ((Split-Path $failedRoot -Leaf)+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))}
    Move-Item -LiteralPath $failedRoot -Destination $destination -Force
    return $destination
}

function Complete-DistroShelfTransaction {
    param([Parameter(Mandatory)]$Transaction)
    Write-DistroShelfTransactionRecord -Transaction $Transaction -State 'Verified'
    $Transaction.State='Verified'
    return $Transaction
}
