# DistroShelf for Windows - beginner-friendly detection and profile GUI

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:Root 'InstallOrchestrator.ps1')

$script:SupportedWslDistros = @('Ubuntu','Debian','Fedora','Arch Linux','openSUSE')
$script:SupportedDistroShelfTerminals = @('Alacritty','COSMIC Terminal','Deepin Terminal','Foot','GNOME Console','GNOME Terminal','Ghostty','Kitty','Konsole','Ptyxis','QTerminal')
$script:SelectedDistro = 'Ubuntu'
$script:SelectedProfileId = $null
$script:SelectedDistroWslName = $null
$script:CreatingProfile = $false

function Get-WslDistros {
    try { return @((& wsl.exe --list --quiet 2>$null) | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ }) } catch { return @() }
}

function Get-ProfileRecord([string]$Id) {
    if (-not $Id) { return $null }
    return Get-DistroShelfProfileById -Id $Id
}

function Get-SelectedProfile {
    return Get-ProfileRecord $script:SelectedProfileId
}

function Find-ProfileWslName([object]$Profile) {
    if (-not $Profile) { return $null }
    foreach ($name in Get-WslDistros) {
        if ($name -eq [string]$Profile.WslName) { return $name }
    }
    return $null
}

function Invoke-WslCommand([string]$Command) {
    $profile = Get-SelectedProfile
    $wslName = Find-ProfileWslName $profile
    if (-not $wslName) { return $null }
    try {
        $output = & wsl.exe --distribution $wslName -- bash -lc $Command 2>$null
        if ($LASTEXITCODE -eq 0) { return ($output -join "`n").Trim() }
    } catch {}
    return $null
}

function Test-Wsl2 {
    try {
        $lines = @(& wsl.exe --list -- verbose 2>&1) -replace "`0", ''
        if ($lines -match '\s2\s*$') { return 'Installed (WSL 2)' }
        $status = (@(& wsl.exe --status 2>&1) -join "`n") -replace "`0", ''
        if ($status -match '(?im)Default Version\s*:\s*2') { return 'Installed (WSL 2 default)' }
    } catch {}
    return 'Not installed'
}

function Test-SelectedDistroProfile {
    $profile = Get-SelectedProfile
    if (-not $profile) { return "Select a distro" }
    if ($profile.Status -eq 'Ready') { return "Installed ($($profile.Name))" }
    if ($profile.Status -eq 'Installation failed') { return 'Not installed' }
    return "Not installed ($($profile.Name))"
}

function Test-LinuxCommand([string]$Command) {
    $profile = Get-SelectedProfile
    if (-not $profile) { return "Needs $($script:SelectedDistro)" }
    if (-not (Find-ProfileWslName $profile)) { return "Needs $($profile.Name)" }
    if (Invoke-WslCommand "command -v '$Command'") { return 'Installed' }
    return 'Not installed'
}

function Test-Flathub {
    $profile = Get-SelectedProfile
    if (-not $profile) { return "Needs $($script:SelectedDistro)" }
    if (-not (Find-ProfileWslName $profile)) { return "Needs $($profile.Name)" }
    if (Invoke-WslCommand "flatpak remotes --columns=name 2>/dev/null | grep -Fx flathub") { return 'Configured' }
    return 'Not configured'
}

function Test-DistroShelf {
    $profile = Get-SelectedProfile
    if (-not $profile) { return "Needs $($script:SelectedDistro)" }
    if (-not (Find-ProfileWslName $profile)) { return "Needs $($profile.Name)" }
    if (Invoke-WslCommand 'flatpak info com.ranfdev.DistroShelf >/dev/null 2>&1') { return 'Installed' }
    return 'Not installed'
}

function Test-WindowsCommand([string]$Command) {
    try { Get-Command $Command -ErrorAction Stop | Out-Null; return 'Installed' } catch { return 'Not installed' }
}

function New-SelectedDistroProfile {
    if ($script:CreatingProfile) { return }
    $script:CreatingProfile = $true
    try {
        $old = Get-SelectedProfile
        if ($old -and $old.Status -eq 'Pending') {
            try { Remove-DistroShelfProfileRecord -Id $old.Id } catch {}
        }
        $profile = New-DistroShelfProfile -Distro $script:SelectedDistro
        $script:SelectedProfileId = [string]$profile.Id
    } finally { $script:CreatingProfile = $false }
}

function Get-ProfileDisplayText([object]$Profile) {
    if (-not $Profile) { return '' }
    switch ([string]$Profile.Status) {
        'Ready' { return "$($Profile.Name) - Installed" }
        'Installation failed' { return "$($Profile.Name) - Failed" }
        default { return "$($Profile.Name) - Not installed" }
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'DistroShelf for Windows'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(760,740)
$form.MinimumSize = New-Object System.Drawing.Size(700,680)

$title = New-Object System.Windows.Forms.Label
$title.Text='DistroShelf for Windows'
$title.Font=New-Object System.Drawing.Font('Segoe UI',20,[System.Drawing.FontStyle]::Bold)
$title.Location=New-Object System.Drawing.Point(24,18);$title.AutoSize=$true;$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text='Detect and manage isolated Linux environments on Windows.'
$subtitle.Location=New-Object System.Drawing.Point(28,58);$subtitle.AutoSize=$true;$form.Controls.Add($subtitle)

$table=New-Object System.Windows.Forms.TableLayoutPanel
$table.Location=New-Object System.Drawing.Point(24,92);$table.Size=New-Object System.Drawing.Size(696,470)
$table.ColumnCount=3;$table.RowCount=1;$table.CellBorderStyle='None';$table.BackColor=[System.Drawing.Color]::White
$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,220)))
$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,110)))
$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
$form.Controls.Add($table)

function Add-HeaderCell([string]$Text,[int]$Column) {
    $l=New-Object System.Windows.Forms.Label;$l.Text=$Text;$l.Dock='Fill';$l.TextAlign='MiddleLeft';$l.Padding=New-Object System.Windows.Forms.Padding(8,0,0,0);[void]$table.Controls.Add($l,$Column,0)
}
Add-HeaderCell 'Component' 0;Add-HeaderCell 'Category' 1;Add-HeaderCell 'Status' 2

$script:Components=@(
 @{Key='wsl2';Name='WSL 2';Group='Core';Detect={Test-Wsl2}},
 @{Key='podman';Name='Podman';Group='Core';Detect={Test-LinuxCommand 'podman'}},
 @{Key='distrobox';Name='Distrobox';Group='Core';Detect={Test-LinuxCommand 'distrobox'}},
 @{Key='flatpak';Name='Flatpak';Group='GUI';Detect={Test-LinuxCommand 'flatpak'}},
 @{Key='flathub';Name='Flathub';Group='GUI';Detect={Test-Flathub}},
 @{Key='distroshelf';Name='DistroShelf';Group='GUI';Detect={Test-DistroShelf}},
 @{Key='git';Name='Git for Windows';Group='Developer';Detect={Test-WindowsCommand 'git.exe'}}
)

function Add-ComponentRow([hashtable]$Component) {
    $row=$table.RowCount;$table.RowCount++;$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,34)))
    $check=New-Object System.Windows.Forms.CheckBox;$check.Text=$Component.Name;$check.Tag=$Component;$check.Dock='Fill';$check.Padding=New-Object System.Windows.Forms.Padding(8,0,0,0);[void]$table.Controls.Add($check,0,$row)
    $cat=New-Object System.Windows.Forms.Label;$cat.Text=$Component.Group;$cat.Dock='Fill';$cat.TextAlign='MiddleLeft';[void]$table.Controls.Add($cat,1,$row)
    $status=New-Object System.Windows.Forms.Label;$status.Dock='Fill';$status.TextAlign='MiddleLeft';$status.Tag=$Component.Key;[void]$table.Controls.Add($status,2,$row)
}

Add-ComponentRow $script:Components[0]

$distroRow=$table.RowCount;$table.RowCount++;$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,34)))
$distroCheck=New-Object System.Windows.Forms.CheckBox;$distroCheck.Text='Distro options';$distroCheck.Dock='Fill';$distroCheck.Padding=New-Object System.Windows.Forms.Padding(8,0,0,0);[void]$table.Controls.Add($distroCheck,0,$distroRow)
$distroCategory=New-Object System.Windows.Forms.Label;$distroCategory.Text='Core';$distroCategory.Dock='Fill';$distroCategory.TextAlign='MiddleLeft';[void]$table.Controls.Add($distroCategory,1,$distroRow)
$distroCombo=New-Object System.Windows.Forms.ComboBox;$distroCombo.Dock='Fill';$distroCombo.DropDownStyle='DropDownList';$distroCombo.Margin=New-Object System.Windows.Forms.Padding(0,4,8,4)
foreach($d in $script:SupportedWslDistros){[void]$distroCombo.Items.Add($d)}
$distroCombo.SelectedItem=$script:SelectedDistro;[void]$table.Controls.Add($distroCombo,2,$distroRow)

$profileRow=$table.RowCount;$table.RowCount++;$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,34)))
$profileLabel=New-Object System.Windows.Forms.Label;$profileLabel.Text='Profile';$profileLabel.Dock='Fill';$profileLabel.Padding=New-Object System.Windows.Forms.Padding(8,0,0,0);$profileLabel.TextAlign='MiddleLeft';[void]$table.Controls.Add($profileLabel,0,$profileRow)
$profileCategory=New-Object System.Windows.Forms.Label;$profileCategory.Text='Core';$profileCategory.Dock='Fill';$profileCategory.TextAlign='MiddleLeft';[void]$table.Controls.Add($profileCategory,1,$profileRow)
$profileCombo=New-Object System.Windows.Forms.ComboBox;$profileCombo.Dock='Fill';$profileCombo.DropDownStyle='DropDownList';$profileCombo.Margin=New-Object System.Windows.Forms.Padding(0,4,8,4);[void]$table.Controls.Add($profileCombo,2,$profileRow)

foreach($c in $script:Components[1..4]){Add-ComponentRow $c}

$terminalRow=$table.RowCount;$table.RowCount++;$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,34)))
$terminalLabel=New-Object System.Windows.Forms.Label;$terminalLabel.Text='Terminal Preference for DistroShelf';$terminalLabel.Dock='Fill';$terminalLabel.Padding=New-Object System.Windows.Forms.Padding(8,0,0,0);$terminalLabel.TextAlign='MiddleLeft';[void]$table.Controls.Add($terminalLabel,0,$terminalRow)
$terminalCategory=New-Object System.Windows.Forms.Label;$terminalCategory.Text='GUI';$terminalCategory.Dock='Fill';$terminalCategory.TextAlign='MiddleLeft';[void]$table.Controls.Add($terminalCategory,1,$terminalRow)
$terminalCombo=New-Object System.Windows.Forms.ComboBox;$terminalCombo.Dock='Fill';$terminalCombo.DropDownStyle='DropDownList';$terminalCombo.Margin=New-Object System.Windows.Forms.Padding(0,4,8,4)
foreach($t in $script:SupportedDistroShelfTerminals){[void]$terminalCombo.Items.Add($t)}
$terminalCombo.SelectedItem='GNOME Console';[void]$table.Controls.Add($terminalCombo,2,$terminalRow)

Add-ComponentRow $script:Components[5];Add-ComponentRow $script:Components[6]

$refresh=New-Object System.Windows.Forms.Button;$refresh.Text='Scan again';$refresh.Location=New-Object System.Drawing.Point(24,610);$refresh.Size=New-Object System.Drawing.Size(120,38);$form.Controls.Add($refresh)
$install=New-Object System.Windows.Forms.Button;$install.Text='Install selected';$install.Location=New-Object System.Drawing.Point(155,610);$install.Size=New-Object System.Drawing.Size(140,38);$form.Controls.Add($install)
$info=New-Object System.Windows.Forms.Label;$info.Text='Select a Linux distribution. A new isolated profile is created automatically.';$info.Location=New-Object System.Drawing.Point(24,660);$info.Size=New-Object System.Drawing.Size(696,40);$form.Controls.Add($info)

function Refresh-ProfileCombo {
    $profileCombo.Items.Clear()
    $profiles = @(Get-DistroShelfProfiles | Where-Object { [string]$_.Distro -eq $script:SelectedDistro })
    foreach($p in $profiles){
        [void]$profileCombo.Items.Add([pscustomobject]@{Text=(Get-ProfileDisplayText $p);Id=[string]$p.Id})
    }
    $current = Get-SelectedProfile
    if($current -and [string]$current.Distro -eq $script:SelectedDistro){
        $idx=-1
        for($i=0;$i -lt $profileCombo.Items.Count;$i++){if([string]$profileCombo.Items[$i].Id -eq [string]$current.Id){$idx=$i;break}}
        if($idx -ge 0){$profileCombo.SelectedIndex=$idx}
    }
}

$profileCombo.DisplayMember='Text'
$profileCombo.Add_SelectedIndexChanged({
    if($profileCombo.SelectedItem){
        $script:SelectedProfileId=[string]$profileCombo.SelectedItem.Id
        Refresh-Scan
    }
})

$distroCombo.Add_SelectedIndexChanged({
    $script:SelectedDistro=[string]$distroCombo.SelectedItem
    New-SelectedDistroProfile
    Refresh-ProfileCombo
    Refresh-Scan
})

function Refresh-Scan {
    $profile=Get-SelectedProfile
    if($profile){$script:SelectedDistroWslName=Find-ProfileWslName $profile}else{$script:SelectedDistroWslName=$null}

    foreach($control in $table.Controls){
        if($control -is [System.Windows.Forms.CheckBox] -and $control.Tag){
            $component=$control.Tag;$status=& $component.Detect
            foreach($child in $table.Controls){
                if($child -is [System.Windows.Forms.Label] -and $child.Tag -eq $component.Key){
                    $child.Text=$status
                    if($status -like 'Installed*' -or $status -eq 'Configured'){$child.ForeColor=[System.Drawing.Color]::Green}else{$child.ForeColor=[System.Drawing.SystemColors]::ControlText}
                    break
                }
            }
            $control.Checked=($status -notlike 'Installed*' -and $status -ne 'Configured')
        }
    }

    $distroStatus=Test-SelectedDistroProfile
    $distroCheck.Checked=$distroStatus -like 'Not installed*'
    $current=Get-SelectedProfile
    if($current){$info.Text="Profile: $($current.Name) - $($current.Status)"}
}

$refresh.Add_Click({Refresh-ProfileCombo;Refresh-Scan})

$install.Add_Click({
    $profile=Get-SelectedProfile
    if(-not $profile){[System.Windows.Forms.MessageBox]::Show('Please select a Linux distribution first.','DistroShelf');return}
    if([string]$profile.Status -eq 'Ready'){
        [System.Windows.Forms.MessageBox]::Show("$($profile.Name) is already installed. Select the distro again to create a new independent profile.",'DistroShelf');return
    }

    $selected=@($table.Controls|Where-Object{$_ -is [System.Windows.Forms.CheckBox] -and $_.Tag -and $_.Checked})
    if($selected.Count -eq 0){[System.Windows.Forms.MessageBox]::Show('Nothing is selected for installation.','DistroShelf');return}

    $progressForm=New-Object System.Windows.Forms.Form;$progressForm.Text="Installing $($profile.Name)";$progressForm.StartPosition='CenterParent';$progressForm.Size=New-Object System.Drawing.Size(520,190);$progressForm.ControlBox=$false
    $progressLabel=New-Object System.Windows.Forms.Label;$progressLabel.Text='Preparing...';$progressLabel.Location=New-Object System.Drawing.Point(20,20);$progressLabel.Size=New-Object System.Drawing.Size(460,45);$progressForm.Controls.Add($progressLabel)
    $bar=New-Object System.Windows.Forms.ProgressBar;$bar.Location=New-Object System.Drawing.Point(20,75);$bar.Size=New-Object System.Drawing.Size(460,25);$bar.Minimum=0;$bar.Maximum=100;$progressForm.Controls.Add($bar)
    $closeButton=New-Object System.Windows.Forms.Button;$closeButton.Text='Close';$closeButton.Enabled=$false;$closeButton.Location=New-Object System.Drawing.Point(380,115);$closeButton.Size=New-Object System.Drawing.Size(100,30);$progressForm.Controls.Add($closeButton)
    $progressForm.Show($form);$form.Enabled=$false
    try {
        $result=Invoke-DistroShelfInstall -Distro ([string]$distroCombo.SelectedItem) -ProfileId ([string]$profile.Id) -Terminal ([string]$terminalCombo.SelectedItem) -OnProgress {param($p,$m)$bar.Value=[Math]::Min(100,[Math]::Max(0,$p));$progressLabel.Text=$m;$progressForm.Refresh()}
        if($result.Success){$progressLabel.Text='Installation complete!';$bar.Value=100;$info.Text="Ready: $($result.ProfileName)";[System.Windows.Forms.MessageBox]::Show("DistroShelf is ready in $($result.ProfileName).","Installation complete",'OK','Information')|Out-Null}
        else{[System.Windows.Forms.MessageBox]::Show($result.Error,'Installation failed','OK','Error')|Out-Null}
    } catch {[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Installation failed','OK','Error')|Out-Null}
    finally {$form.Enabled=$true;$closeButton.Enabled=$true;$progressForm.ControlBox=$true;$progressForm.Refresh();Refresh-ProfileCombo;Refresh-Scan}
})

# Selecting the initial distro creates its first independent profile.
New-SelectedDistroProfile
Refresh-ProfileCombo
Refresh-Scan
[void]$form.ShowDialog()
