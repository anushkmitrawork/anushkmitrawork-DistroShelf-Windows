# DistroShelf - temporary profile-number reservations
$script:DistroShelfReservationRoot = Join-Path $env:LOCALAPPDATA 'DistroShelf\reservations'
$script:DistroShelfReservationMutexName = 'Local\DistroShelf.ProfileNumberReservation'

function Reserve-DistroShelfProfileNumber {
    param([Parameter(Mandatory)][ValidateSet('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')][string]$Distro)
    if(!(Test-Path -LiteralPath $script:DistroShelfReservationRoot)){New-Item -ItemType Directory -Path $script:DistroShelfReservationRoot -Force|Out-Null}
    $mutex=[Threading.Mutex]::new($false,$script:DistroShelfReservationMutexName)
    if(-not $mutex.WaitOne([TimeSpan]::FromSeconds(30))){$mutex.Dispose();throw 'Timed out waiting for the profile-number reservation lock.'}
    try {
        $path=Join-Path $script:DistroShelfReservationRoot 'reservations.json'
        $all=@()
        if(Test-Path -LiteralPath $path){try{$all=@(Get-Content $path -Raw|ConvertFrom-Json)}catch{$all=@()}}
        $cutoff=[DateTime]::UtcNow.AddHours(-24)
        $all=@($all|Where-Object{try{[DateTime]::Parse([string]$_.CreatedAt).ToUniversalTime() -gt $cutoff}catch{$false}})
        $prefix=(Get-DistroShelfProfileDefinition $Distro).WslBaseName
        $numbers=@()
        foreach($p in @(Get-DistroShelfProfiles)){
            if([string]$p.Status -eq 'Ready' -and [string]$p.Name -match "^$([regex]::Escape($prefix))([0-9]+)$"){$numbers+=[int]$Matches[1]}
        }
        foreach($r in $all){if([string]$r.Distro -eq $Distro){$numbers+=[int]$r.Number}}
        $n=1;while($numbers -contains $n){$n++}
        $reservation=[pscustomobject][ordered]@{Id=[guid]::NewGuid().ToString();Distro=$Distro;Number=$n;Name="$prefix$n";CreatedAt=[DateTime]::UtcNow.ToString('o');Mutex=$mutex;Path=$path}
        $persist=@($all)+([pscustomobject]@{Id=$reservation.Id;Distro=$Distro;Number=$n;Name=$reservation.Name;CreatedAt=$reservation.CreatedAt})
        $tmp="$path.tmp"
        @($persist)|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $path -Force
        return $reservation
    } catch {try{$mutex.ReleaseMutex()}catch{};$mutex.Dispose();throw}
}

function Release-DistroShelfProfileReservation {
    param([Parameter(Mandatory)]$Reservation)
    try {
        $path=[string]$Reservation.Path
        if(Test-Path -LiteralPath $path){
            $all=@(Get-Content $path -Raw|ConvertFrom-Json)
            $all=@($all|Where-Object{[string]$_.Id -ne [string]$Reservation.Id})
            $tmp="$path.tmp"
            @($all)|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $tmp -Encoding UTF8
            Move-Item -LiteralPath $tmp -Destination $path -Force
        }
    } finally {
        try{$Reservation.Mutex.ReleaseMutex()}catch{}
        try{$Reservation.Mutex.Dispose()}catch{}
    }
}
