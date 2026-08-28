# DistroShelf for Windows - detection-first GUI with installation orchestration

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:Root 'InstallOrchestrator.ps1')

$script:SupportedWslDistros = @('Ubuntu', 'Debian', 'Fedora', 'Arch Linux', 'openSUSE')
$script:SupportedDistroShelfTerminals = @('Alacritty','COSMIC Terminal','Deepin Terminal','Foot','GNOME Console','GNOME Terminal','Ghostty','Kitty','Konsole','Ptyxis','QTerminal')
$script:SelectedDistro = 'Ubuntu'
$script:SelectedDistroWslName = $null

function Get-WslDistros {
    try { return @((& wsl.exe --list --quiet 2>$null) | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ }) } catch { return @() }
}
function Find-SupportedWslDistro([string]$DisplayName) {
    foreach ($name in Get-WslDistros) {
        switch ($DisplayName) {
            'Ubuntu' { if ($name -match '^Ubuntu($|[- ])') { return $name } }
            'Debian' { if ($name -match '^Debian($|[- ])') { return $name } }
            'Fedora' { if ($name -match '^Fedora($|[- ])') { return $name } }
            'Arch Linux' { if ($name -match '^(Arch|ArchLinux)($|[- ])') { return $name } }
            'openSUSE' { if ($name -match '^openSUSE($|[- ])') { return $name } }
        }
    }
    return $null
}
function Invoke-WslCommand([string]$Command) {
    if (-not $script:SelectedDistroWslName) { return $null }
    try { $output = & wsl.exe --distribution $script:SelectedDistroWslName -- bash -lc $Command 2>$null; if ($LASTEXITCODE -eq 0) { return ($output -join "`n").Trim() } } catch {}
    return $null
}
function Test-Wsl2 {
    try {
        $lines = @(& wsl.exe --list --verbose 2>&1) -replace "`0", ''
        if ($lines -match '\s2\s*$') { return 'Installed (WSL 2)' }
        $status = (@(& wsl.exe --status 2>&1) -join "`n") -replace "`0", ''
        if ($status -match '(?im)Default Version\s*:\s*2') { return 'Installed (WSL 2 default)' }
    } catch {}
    return 'Not installed'
}
function Test-SelectedDistro {
    $script:SelectedDistroWslName = Find-SupportedWslDistro $script:SelectedDistro
    if ($script:SelectedDistroWslName) { return "Installed ($script:SelectedDistroWslName)" }
    return "Not installed ($script:SelectedDistro)"
}
function Test-LinuxCommand([string]$Command) {
    if (-not $script:SelectedDistroWslName) { $script:SelectedDistroWslName = Find-SupportedWslDistro $script:SelectedDistro }
    if (-not $script:SelectedDistroWslName) { return "Needs $($script:SelectedDistro)" }
    if (Invoke-WslCommand "command -v '$Command'") { return 'Installed' }
    return 'Not installed'
}
function Test-Flathub {
    if (-not $script:SelectedDistroWslName) { $script:SelectedDistroWslName = Find-SupportedWslDistro $script:SelectedDistro }
    if (-not $script:SelectedDistroWslName) { return "Needs $($script:SelectedDistro)" }
    if (Invoke-WslCommand "flatpak remotes --columns=name 2>/dev/null | grep -Fx flathub") { return 'Configured' }
    return 'Not configured'
}
function Test-DistroShelf {
    if (-not $script:SelectedDistroWslName) { $script:SelectedDistroWslName = Find-SupportedWslDistro $script:SelectedDistro }
    if (-not $script:SelectedDistroWslName) { return "Needs $($script:SelectedDistro)" }
    $status = (& wsl.exe --distribution $script:SelectedDistroWslName -- bash -lc "flatpak info com.ranfdev.DistroShelf >/dev/null 2>&1; echo `$?" 2>$null) -join ''
    if ($status.Trim() -eq '0') { return 'Installed' }
    return 'Not installed'
}
function Test-WindowsCommand([string]$Command) {
    try { $cmd = Get-Command $Command -ErrorAction Stop; return 'Installed' } catch { return 'Not installed' }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'DistroShelf for Windows'; $form.StartPosition = 'CenterScreen'; $form.Size = New-Object System.Drawing.Size(760,700); $form.MinimumSize = New-Object System.Drawing.Size(700,640)
$title = New-Object System.Windows.Forms.Label; $title.Text='DistroShelf for Windows'; $title.Font=New-Object System.Drawing.Font('Segoe UI',20,[System.Drawing.FontStyle]::Bold); $title.Location=New-Object System.Drawing.Point(24,18); $title.AutoSize=$true; $form.Controls.Add($title)
$subtitle = New-Object System.Windows.Forms.Label; $subtitle.Text='Detect and manage the Linux container environment on Windows.'; $subtitle.Location=New-Object System.Drawing.Point(28,58); $subtitle.AutoSize=$true; $form.Controls.Add($subtitle)
$table=New-Object System.Windows.Forms.TableLayoutPanel; $table.Location=New-Object System.Drawing.Point(24,92); $table.Size=New-Object System.Drawing.Size(696,430); $table.ColumnCount=3; $table.RowCount=1; $table.CellBorderStyle='None'; $table.BackColor=[System.Drawing.Color]::White; $table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,220))); $table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,110))); $table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100))); $form.Controls.Add($table)

function Add-HeaderCell([string]$Text,[int]$Column) { $l=New-Object System.Windows.Forms.Label; $l.Text=$Text; $l.Dock='Fill'; $l.TextAlign='MiddleLeft'; $l.Padding=New-Object System.Windows.Forms.Padding(8,0,0,0); [void]$table.Controls.Add($l,$Column,0) }
Add-HeaderCell 'Component' 0; Add-HeaderCell 'Category' 1; Add-HeaderCell 'Status' 2

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
 $row=$table.RowCount; $table.RowCount++; $table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,34)))
 $check=New-Object System.Windows.Forms.CheckBox; $check.Text=$Component.Name; $check.Tag=$Component; $check.Dock='Fill'; $check.Padding=New-Object System.Windows.Forms.Padding(8,0,0,0); [void]$table.Controls.Add($check,0,$row)
 $cat=New-Object System.Windows.Forms.Label; $cat.Text=$Component.Group; $cat.Dock='Fill'; $cat.TextAlign='MiddleLeft'; [void]$table.Controls.Add($cat,1,$row)
 $status=New-Object System.Windows.Forms.Label; $status.Dock='Fill'; $status.TextAlign='MiddleLeft'; $status.Tag=$Component.Key; [void]$table.Controls.Add($status,2,$row)
}
Add-ComponentRow $script:Components[0]

$distroRow=$table.RowCount; $table.RowCount++; $table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,34)))
$distroCheck=New-Object System.Windows.Forms.CheckBox; $distroCheck.Text='Distro options'; $distroCheck.Dock='Fill'; $distroCheck.Padding=New-Object System.Windows.Forms.Padding(8,0,0,0); [void]$table.Controls.Add($distroCheck,0,$distroRow)
$distroCategory=New-Object System.Windows.Forms.Label; $distroCategory.Text='Core'; $distroCategory.Dock='Fill'; $distroCategory.TextAlign='MiddleLeft'; [void]$table.Controls.Add($distroCategory,1,$distroRow)
$distroCombo=New-Object System.Windows.Forms.ComboBox; $distroCombo.Dock='Fill'; $distroCombo.DropDownStyle='DropDownList'; $distroCombo.Margin=New-Object System.Windows.Forms.Padding(0,4,8,4); foreach($d in $script:SupportedWslDistros){[void]$distroCombo.Items.Add($d)}; $distroCombo.SelectedItem=$script:SelectedDistro; [void]$table.Controls.Add($distroCombo,2,$distroRow)
$distroCombo.Add_SelectedIndexChanged({$script:SelectedDistro=[string]$distroCombo.SelectedItem;$script:SelectedDistroWslName=Find-SupportedWslDistro $script:SelectedDistro;Refresh-Scan})

foreach($c in $script:Components[1..4]){Add-ComponentRow $c}
$terminalRow=$table.RowCount;$table.RowCount++;$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,34)))
$terminalHost=New-Object System.Windows.Forms.Panel;$terminalHost.Dock='Fill';$table.Controls.Add($terminalHost,0,$terminalRow);[void]$table.SetColumnSpan($terminalHost,3)
$terminalPanel=New-Object System.Windows.Forms.Panel;$terminalPanel.Dock='Top';$terminalPanel.Height=86;$terminalPanel.Visible=$false;$terminalHost.Controls.Add($terminalPanel)
$terminalButton=New-Object System.Windows.Forms.Button;$terminalButton.Text='▶  Terminal Preference for DistroShelf';$terminalButton.TextAlign='MiddleLeft';$terminalButton.Dock='Top';$terminalButton.Height=34;$terminalHost.Controls.Add($terminalButton)
$terminalLabel=New-Object System.Windows.Forms.Label;$terminalLabel.Text='Choose the terminal DistroShelf should use:';$terminalLabel.Location=New-Object System.Drawing.Point(12,10);$terminalLabel.AutoSize=$true;$terminalPanel.Controls.Add($terminalLabel)
$terminalCombo=New-Object System.Windows.Forms.ComboBox;$terminalCombo.Location=New-Object System.Drawing.Point(12,36);$terminalCombo.Size=New-Object System.Drawing.Size(360,30);$terminalCombo.DropDownStyle='DropDownList';foreach($t in $script:SupportedDistroShelfTerminals){[void]$terminalCombo.Items.Add($t)};$terminalCombo.SelectedItem='GNOME Console';$terminalPanel.Controls.Add($terminalCombo)
$terminalButton.Add_Click({$terminalPanel.Visible=-not $terminalPanel.Visible;if($terminalPanel.Visible){$terminalButton.Text='▼  Terminal Preference for DistroShelf';$table.RowStyles[$terminalRow].Height=120}else{$terminalButton.Text='▶  Terminal Preference for DistroShelf';$table.RowStyles[$terminalRow].Height=34};$table.PerformLayout();$table.Refresh()})
Add-ComponentRow $script:Components[5];Add-ComponentRow $script:Components[6]

$refresh=New-Object System.Windows.Forms.Button;$refresh.Text='Scan again';$refresh.Location=New-Object System.Drawing.Point(24,570);$refresh.Size=New-Object System.Drawing.Size(120,38);$form.Controls.Add($refresh)
$install=New-Object System.Windows.Forms.Button;$install.Text='Install selected';$install.Location=New-Object System.Drawing.Point(155,570);$install.Size=New-Object System.Drawing.Size(140,38);$form.Controls.Add($install)
$info=New-Object System.Windows.Forms.Label;$info.Text='Select a WSL distro and components to install.';$info.Location=New-Object System.Drawing.Point(24,620);$info.Size=New-Object System.Drawing.Size(696,35);$form.Controls.Add($info)

function Refresh-Scan {
 $script:SelectedDistroWslName=Find-SupportedWslDistro $script:SelectedDistro
 foreach($control in $table.Controls){if($control -is [System.Windows.Forms.CheckBox] -and $control.Tag){$component=$control.Tag;$status=& $component.Detect;foreach($child in $table.Controls){if($child -is [System.Windows.Forms.Label] -and $child.Tag -eq $component.Key){$child.Text=$status;if($status -like 'Installed*' -or $status -eq 'Configured'){$child.ForeColor=[System.Drawing.Color]::Green}else{$child.ForeColor=[System.Drawing.SystemColors]::ControlText};break}};$control.Checked=($status -notlike 'Installed*' -and $status -ne 'Configured')}}
 $distroStatus=Test-SelectedDistro;$distroCheck.Checked=$distroStatus -like 'Not installed*'
}

$refresh.Add_Click({Refresh-Scan})
$install.Add_Click({
 if(-not $distroCombo.SelectedItem){[System.Windows.Forms.MessageBox]::Show('Please select a Linux distribution first.','DistroShelf');return}
 $selected=@($table.Controls|Where-Object{$_ -is [System.Windows.Forms.CheckBox] -and $_.Tag -and $_.Checked})
 if($selected.Count -eq 0){[System.Windows.Forms.MessageBox]::Show('Nothing is selected for installation.','DistroShelf');return}

 $progressForm=New-Object System.Windows.Forms.Form;$progressForm.Text='Installing DistroShelf';$progressForm.StartPosition='CenterParent';$progressForm.Size=New-Object System.Drawing.Size(520,190);$progressForm.ControlBox=$false
 $progressLabel=New-Object System.Windows.Forms.Label;$progressLabel.Text='Preparing...';$progressLabel.Location=New-Object System.Drawing.Point(20,20);$progressLabel.Size=New-Object System.Drawing.Size(460,45);$progressForm.Controls.Add($progressLabel)
 $bar=New-Object System.Windows.Forms.ProgressBar;$bar.Location=New-Object System.Drawing.Point(20,75);$bar.Size=New-Object System.Drawing.Size(460,25);$bar.Minimum=0;$bar.Maximum=100;$progressForm.Controls.Add($bar)
 $cancel=New-Object System.Windows.Forms.Button;$cancel.Text='Close after completion';$cancel.Enabled=$false;$cancel.Location=New-Object System.Drawing.Point(330,115);$cancel.Size=New-Object System.Drawing.Size(150,30);$progressForm.Controls.Add($cancel)
 $progressForm.Show($form);$form.Enabled=$false
 try {
   $result=Invoke-DistroShelfInstall -Distro ([string]$distroCombo.SelectedItem) -Terminal ([string]$terminalCombo.SelectedItem) -OnProgress {param($p,$m)$bar.Value=[Math]::Min(100,[Math]::Max(0,$p));$progressLabel.Text=$m;$progressForm.Refresh()} 
   if($result.Success){$progressLabel.Text='Installation complete!';$bar.Value=100;$info.Text="Ready: $($result.ProfileName)";[System.Windows.Forms.MessageBox]::Show("DistroShelf is ready in $($result.ProfileName).","Installation complete",'OK','Information')|Out-Null}else{[System.Windows.Forms.MessageBox]::Show($result.Error,'Installation failed','OK','Error')|Out-Null}
 } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Installation failed','OK','Error')|Out-Null } finally {$form.Enabled=$true;$cancel.Enabled=$true;$progressForm.ControlBox=$true;$progressForm.Refresh();Refresh-Scan}
})

Refresh-Scan
[void]$form.ShowDialog()
