# DistroShelf - provider contract
# A provider describes acquisition/install/test behavior. Engines own scheduling and transaction semantics.

. (Join-Path $PSScriptRoot 'PackageAcquisition.ps1')

function New-StageTest {
    param(
        [string]$Name,
        [string]$Command,
        [int]$ExpectedExitCode = 0,
        [string]$ExpectedOutput
    )

    [pscustomobject][ordered]@{
        Name = $Name
        Command = $Command
        ExpectedExitCode = $ExpectedExitCode
        ExpectedOutput = $ExpectedOutput
    }
}

function New-StageContract {
    param(
        [string]$Id,
        [string[]]$Depends,
        [string]$PackageManager,
        [string[]]$TrackAcquire,
        [string[]]$TrackInstall,
        [object[]]$TrackTests,
        [string[]]$ProfileInstall,
        [object[]]$ProfileTests,
        [string]$ExportType,
        [string]$ExportValue,
        [string]$Kind = 'dependency',
        [string]$ParallelGroup,
        [string]$ResourceLock,
        [ValidateSet('SharedBuilder','IsolatedBuilder')]
        [string]$ExecutionModel = 'SharedBuilder'
    )

    [pscustomobject][ordered]@{
        Id = $Id
        Depends = @($Depends)
        Kind = $Kind
        ParallelGroup = $ParallelGroup
        PackageManager = $PackageManager
        ResourceLock = $ResourceLock
        ExecutionModel = $ExecutionModel
        Track = [pscustomobject][ordered]@{
            Acquire = @($TrackAcquire)
            Install = @($TrackInstall)
            Tests = @($TrackTests)
            ExportType = $ExportType
            ExportValue = $ExportValue
        }
        Profile = [pscustomobject][ordered]@{
            Install = @($ProfileInstall)
            Tests = @($ProfileTests)
        }
    }
}

function New-DistroShelfRootfsStage {
    param([string]$Manager)

    [pscustomobject][ordered]@{
        Id = 'rootfs'
        Depends = @()
        Kind = 'rootfs'
        ParallelGroup = 'bootstrap'
        PackageManager = $Manager
        ResourceLock = 'wsl-rootfs'
        ExecutionModel = 'SharedBuilder'
        Track = [pscustomobject][ordered]@{
            Acquire = @()
            Install = @()
            Tests = @(
                (New-StageTest 'os-release' 'test -s /etc/os-release')
            )
            ExportType = 'none'
            ExportValue = ''
        }
        Profile = [pscustomobject][ordered]@{
            Install = @()
            Tests = @(
                (New-StageTest 'os-release' 'test -s /etc/os-release')
            )
        }
    }
}

function Test-DistroShelfProviderContract {
    param([Parameter(Mandatory)]$Provider)

    $errors = @()

    if([string]::IsNullOrWhiteSpace([string]$Provider.Distro)) {
        $errors += 'Provider has no distro.'
    }

    if([string]::IsNullOrWhiteSpace([string]$Provider.PackageManager)) {
        $errors += "Provider '$($Provider.Distro)' has no package manager."
    }

    $stages = @($Provider.Stages)
    if(!$stages.Count) {
        $errors += "Provider '$($Provider.Distro)' has no stages."
    }

    $ids = @{}
    foreach($stage in $stages) {
        $id = [string]$stage.Id
        if(!$id) {
            $errors += 'Provider contains a stage without an Id.'
            continue
        }

        if($ids.ContainsKey($id)) {
            $errors += "Duplicate stage '$id'."
        } else {
            $ids[$id] = $true
        }

        if(!$stage.Track -or !$stage.Profile) {
            $errors += "Stage '$id' is missing Track/Profile contracts."
            continue
        }

        if($id -ne 'rootfs' -and @($stage.Track.Tests).Count -eq 0) {
            $errors += "Stage '$id' has no Track tests."
        }

        if($id -ne 'rootfs' -and @($stage.Profile.Tests).Count -eq 0) {
            $errors += "Stage '$id' has no Profile tests."
        }

        if([string]$stage.ExecutionModel -notin @('SharedBuilder','IsolatedBuilder')) {
            $errors += "Stage '$id' has invalid ExecutionModel."
        }
    }

    foreach($stage in $stages) {
        foreach($dependency in @($stage.Depends)) {
            if(!$ids.ContainsKey([string]$dependency)) {
                $errors += "Stage '$($stage.Id)' depends on unknown stage '$dependency'."
            }
        }
    }

    if(@($Provider.TrackFinalTests).Count -eq 0) {
        $errors += "Provider '$($Provider.Distro)' has no Track final tests."
    }

    if(@($Provider.ProfileFinalTests).Count -eq 0) {
        $errors += "Provider '$($Provider.Distro)' has no Profile final tests."
    }

    [pscustomobject][ordered]@{
        Valid = ($errors.Count -eq 0)
        Distro = $Provider.Distro
        Errors = $errors
    }
}
