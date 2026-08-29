# DistroShelf - atomic transaction lifecycle

$script:DistroShelfStateRoot = Join-Path $env:LOCALAPPDATA 'DistroShelf'

function New-DistroShelfTransaction {
    param([Parameter(Mandatory)][ValidateSet('Track','Profile')][string]$Kind,[Parameter(Mandatory)][string]$Distro,[string]$Name)
    $id=[guid]::NewGuid().ToString('N')
    $root=Join-Path (Join-Path $script:DistroShelfStateRoot 'Attempts') $id
    New-Item -ItemType Directory -Path $root -Force|Out-Null
    [pscustomobject][ordered]@{Id=$id;Kind=$Kind;Distro=$Distro;Name=$Name;Root=$root;StartedAt=[DateTime]::UtcNow.ToString('o');State='Running'}
}

function Write-DistroShelfTransactionRecord {
    param([Parameter(Mandatory)]$Transaction,[ValidateSet('Running','Testing','Verified','Committed','Failed')][string]$State='Running',[object]$Data)
    $record=[ordered]@{SchemaVersion=1;Id=$Transaction.Id;Kind=$Transaction.Kind;Distro=$Transaction.Distro;Name=$Transaction.Name;State=$State;StartedAt=$Transaction.StartedAt;UpdatedAt=[DateTime]::UtcNow.ToString('o');Data=$Data}
    $path=Join-Path $Transaction.Root 'transaction.json';$tmp="$path.tmp"
    $record|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Move-DistroShelfTransactionToTroubleshoot {
    param([Parameter(Mandatory)]$Transaction,[Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)
    $failure=[ordered]@{TransactionId=$Transaction.Id;Kind=$Transaction.Kind;Distro=$Transaction.Distro;Name=$Transaction.Name;Error=$ErrorRecord.Exception.Message;FailedAt=[DateTime]::UtcNow.ToString('o')}
    $failure|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $Transaction.Root 'failure.json') -Encoding UTF8
    Write-DistroShelfTransactionRecord -Transaction $Transaction -State 'Failed' -Data $failure
    $troubleParent=Join-Path $script:DistroShelfStateRoot 'Troubleshoot';New-Item -ItemType Directory -Path $troubleParent -Force|Out-Null
    $troubleRoot=Join-Path $troubleParent ("{0}-{1}-{2}" -f $Transaction.Kind,$Transaction.Distro,$Transaction.Id)
    Move-Item -LiteralPath $Transaction.Root -Destination $troubleRoot -Force
    return $troubleRoot
}

function Complete-DistroShelfTransaction {
    param([Parameter(Mandatory)]$Transaction)
    Write-DistroShelfTransactionRecord -Transaction $Transaction -State 'Verified'
    $Transaction.State='Verified';return $Transaction
}

function Remove-DistroShelfSuccessfulTransaction {
    param([Parameter(Mandatory)]$Transaction)
    if(Test-Path -LiteralPath $Transaction.Root){Remove-Item -LiteralPath $Transaction.Root -Recurse -Force -ErrorAction Stop}
}
