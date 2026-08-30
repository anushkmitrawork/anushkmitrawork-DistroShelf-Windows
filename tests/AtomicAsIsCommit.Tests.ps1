$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'src'
. (Join-Path $src 'Engine\AtomicCommit.ps1')
. (Join-Path $src 'Engine\TransactionEngine.ps1')

function Fail([string]$m){throw "FAIL  $m"}
function Pass([string]$m){Write-Host "PASS  $m"}

$atomicText=Get-Content -LiteralPath (Join-Path $src 'Engine\AtomicCommit.ps1') -Raw
$trackText=Get-Content -LiteralPath (Join-Path $src 'Track\TrackEngine.ps1') -Raw
$profileText=Get-Content -LiteralPath (Join-Path $src 'Profile\ProfileCommit.ps1') -Raw

if($atomicText -notmatch 'Move-Item -LiteralPath \$Source -Destination \$Destination -Force'){Fail 'Atomic promotion does not move the existing source tree as-is'}
if($atomicText -match 'Copy-Item'){Fail 'Atomic promotion must not copy or mirror the source tree'}
if($trackText -notmatch 'Move-DistroShelfDirectoryAtomic -Source \$Source -Destination \$Destination'){Fail 'Track commit is not wired to the as-is atomic mover'}
if($trackText -notmatch 'Move-DistroShelfTransactionToTroubleshoot'){Fail 'Track failure is not routed to Troubleshoot'}
if($profileText -notmatch 'Move-Item -LiteralPath \$export -Destination \$finalVhdx -Force'){Fail 'Profile commit does not promote the accepted artifact by move'}
Pass 'Track/Profile commit paths use move semantics rather than replication'

$temp=Join-Path ([IO.Path]::GetTempPath()) ('DistroShelf-AsIs-'+[guid]::NewGuid())
try {
    $source=Join-Path $temp 'attempt'
    $destination=Join-Path $temp 'complete'
    New-Item -ItemType Directory -Path (Join-Path $source 'nested') -Force|Out-Null
    'payload'|Set-Content (Join-Path $source 'nested\payload.txt')
    $before=(Get-DistroShelfTreeHash -Root $source)
    Move-DistroShelfDirectoryAtomic -Source $source -Destination $destination
    if(Test-Path -LiteralPath $source){Fail 'As-is promotion left a replicated source behind'}
    if(-not(Test-Path -LiteralPath (Join-Path $destination 'nested\payload.txt'))){Fail 'As-is promotion lost source contents'}
    $after=(Get-DistroShelfTreeHash -Root $destination)
    if($before -ne $after){Fail 'As-is promotion changed the tree contents'}
    Pass 'Atomic promotion moves the exact existing tree without mirroring'

    $tx=New-DistroShelfTransaction -Kind Track -Distro Debian
    'failed-state'|Set-Content (Join-Path $tx.Root 'payload.txt')
    $tr=Move-DistroShelfTransactionToTroubleshoot -Transaction $tx -ErrorRecord ([System.Management.Automation.ErrorRecord]::new([Exception]::new('synthetic failure'),'Synthetic','OperationStopped',$null))
    if(Test-Path -LiteralPath $tx.Root){Fail 'Troubleshoot routing left the original attempt behind'}
    if(-not(Test-Path -LiteralPath (Join-Path $tr 'payload.txt'))){Fail 'Troubleshoot routing did not preserve the existing attempt contents'}
    Pass 'Troubleshoot routing moves the failed attempt as-is'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`nI.6 As-is commit boundary tests passed."