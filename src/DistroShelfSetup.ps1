# DistroShelf for Windows - detection-first prototype
# Requires Windows PowerShell 5.1+ or PowerShell 7 with Windows Forms available.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# Keep this list aligned with DistroShelf's supported-terminal choices.
# Windows Terminal and arbitrary custom terminals are intentionally excluded.
$script:SupportedDistroShelfTerminals = @(
    'Alacritty',
    'COSMIC Terminal',
    'Deepin Terminal',
    'Foot',
    'GNOME Console',
    'GNOME Terminal',
    'Ghostty',
    'Kitty',
    'Konsole',
    'Ptyxis',
    'QTerminal'
)

$script:Components = @(
    @{ Key='wsl2'; Name='WSL 2'; Group='Core'; Detect={ Test-Wsl2 } }
    @{ Key='ubuntu'; Name='Ubuntu'; Group='Core'; Detect={ Test-Ubuntu } }
    @{ Key='podman'; Name='Podman'; Group='Core'; Detect={ Test-LinuxCommand 'podman' } }
    @{ Key='distrobox'; Name='Distrobox'; Group='Core'; Detect={ Test-LinuxCommand 'distrobox' } }
    @{ Key='flatpak'; Name='Flatpak'; Group='GUI'; Detect={ Test-LinuxCommand 'flatpak' } }
    @{ Key='flathub'; Name='Flathub'; Group='GUI'; Detect={ Test-Flathub } }
    @{ Key='distroshelf'; Name='DistroShelf'; Group='GUI'; Detect={ Test-DistroShelf } }
    @{ Key='git'; Name='Git for Windows'; Group='Developer'; Detect={ Test-WindowsCommand 'git.exe' } }
)

$script:UbuntuDistro = $null

function Invoke-WslCommand {
    param([string]$Command, [string]$Distro = $script:UbuntuDistro)
    if ([string]::IsNullOrWhiteSpace($Distro)) { return $null }
    try {
        $output = & wsl.exe --distribution $Distro -- bash -lc $Command 2>$null
        if ($LASTEXITCODE -eq 0) { return ($output -join "`n").Trim() }
    } catch {}
    return $null
}

function Find-UbuntuDistro {
    try {
        $lines = & wsl.exe --list --quiet 2>$null
        foreach ($line in $lines) {
            $name = ($line -replace "`0", '').Trim()
            if ($name -match '^Ubuntu($|[- ])') { return $name }
        }
    } catch {}
    return $null
}

function Test-Wsl2 {
    try {
        $wslCommand = Get-Command 'wsl.exe' -ErrorAction Stop
        $distros = @(& $wslCommand.Source --list --verbose 2>&1)
        $distroText = ($distros -join "`n") -replace "`0", ''
        foreach ($line in $distros) {
            $clean = ($line -replace "`0", '').Trim()
            if ($clean -match '\s2\s*$') { return 'Installed (WSL 2)' }
        }
        $status = @(& $wslCommand.Source --status 2>&1) -join "`n"
        $status = $status -replace "`0", ''
        if ($status -match '(?im)Default Version\s*:\s*2') {
            return 'Installed (WSL 2 default)'
        }
        if ($distroText -or $status) { return 'Installed (WSL 2 not detected)' }
    } catch {}
    return 'Not installed'
}

function Test-Ubuntu {
    $script:UbuntuDistro = Find-UbuntuDistro
    if (-not $script:UbuntuDistro) { return 'Not installed' }
    $release = Invoke-WslCommand "grep '^PRETTY_NAME=' /etc/os-release"
    if ($release) { return "Installed ($script:UbuntuDistro)" }
    return 'Needs attention'
}

function Test-LinuxCommand {
    param([string]$Command)
    if (-not $script:UbuntuDistro) { $script:UbuntuDistro = Find-UbuntuDistro }
    if (-not $script:UbuntuDistro) { return 'Needs Ubuntu' }
    $version = Invoke-WslCommand "command -v '$Command'"
    if ($version) {
        $detail = Invoke-WslCommand "'$Command' --version 2>/dev/null | head -n 1"
        if ($detail) { return "Installed ($detail)" }
        return 'Installed'
    }
    return 'Not installed'
}

function Test-Flathub {
    if (-not $script:UbuntuDistro) { $script:UbuntuDistro = Find-UbuntuDistro }
    if (-not $script:UbuntuDistro) { return 'Needs Ubuntu' }
    $remote = Invoke-WslCommand "flatpak remotes --columns=name 2>/dev/null | grep -Fx flathub"
    if ($remote) { return 'Configured' }
    return 'Not configured'
}

function Test-DistroShelf {
    if (-not $script:UbuntuDistro) { $script:UbuntuDistro = Find-UbuntuDistro }
    if (-not $script:UbuntuDistro) { return 'Needs Ubuntu' }
    $status = & wsl.exe --distribution $script:UbuntuDistro -- bash -lc "flatpak info com.ranfdev.DistroShelf >/dev/null 2>&1; echo `$?" 2>$null
    if (($status -join '').Trim() -eq '0') { return 'Installed' }
    return 'Not installed'
}

function Test-WindowsCommand {
    param([string]$Command)
    try {
        $cmd = Get-Command $Command -ErrorAction Stop
        $version = (& $cmd.Source --version 2>$null | Select-Object -First 1)
        if ($version) { return "Installed ($version)" }
        return 'Installed'
    } catch { return 'Not installed' }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'DistroShelf for Windows'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(760, 700)
$form.MinimumSize = New-Object System.Drawing.Size(700, 640)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'DistroShelf for Windows'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 20, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(24, 18)
$title.AutoSize = $true
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Detect and manage the Linux container environment on Windows.'
$subtitle.Location = New-Object System.Drawing.Point(28, 58)
$subtitle.AutoSize = $true
$form.Controls.Add($subtitle)

$list = New-Object System.Windows.Forms.ListView
$list.Location = New-Object System.Drawing.Point(24, 92)
$list.Size = New-Object System.Drawing.Size(696, 320)
$list.View = 'Details'
$list.FullRowSelect = $true
$list.CheckBoxes = $true
$list.GridLines = $false
[void]$list.Columns.Add('Component', 220)
[void]$list.Columns.Add('Category', 110)
[void]$list.Columns.Add('Status', 340)
$form.Controls.Add($list)

# Beginner-friendly terminal preference section. It starts collapsed and sits
# directly after the Flathub/dependency area, before DistroShelf itself.
$terminalButton = New-Object System.Windows.Forms.Button
$terminalButton.Text = '▶  Terminal Preference for DistroShelf'
$terminalButton.TextAlign = 'MiddleLeft'
$terminalButton.Location = New-Object System.Drawing.Point(24, 425)
$terminalButton.Size = New-Object System.Drawing.Size(696, 36)
$form.Controls.Add($terminalButton)

$terminalPanel = New-Object System.Windows.Forms.Panel
$terminalPanel.Location = New-Object System.Drawing.Point(24, 466)
$terminalPanel.Size = New-Object System.Drawing.Size(696, 86)
$terminalPanel.BorderStyle = 'FixedSingle'
$terminalPanel.Visible = $false
$form.Controls.Add($terminalPanel)

$terminalLabel = New-Object System.Windows.Forms.Label
$terminalLabel.Text = 'Choose the terminal DistroShelf should use:'
$terminalLabel.Location = New-Object System.Drawing.Point(12, 12)
$terminalLabel.AutoSize = $true
$terminalPanel.Controls.Add($terminalLabel)

$terminalCombo = New-Object System.Windows.Forms.ComboBox
$terminalCombo.Location = New-Object System.Drawing.Point(12, 38)
$terminalCombo.Size = New-Object System.Drawing.Size(360, 30)
$terminalCombo.DropDownStyle = 'DropDownList'
foreach ($terminal in $script:SupportedDistroShelfTerminals) {
    [void]$terminalCombo.Items.Add($terminal)
}
$terminalCombo.SelectedItem = 'GNOME Console'
$terminalPanel.Controls.Add($terminalCombo)

$terminalButton.Add_Click({
    if ($terminalPanel.Visible) {
        $terminalPanel.Visible = $false
        $terminalButton.Text = '▶  Terminal Preference for DistroShelf'
    } else {
        $terminalPanel.Visible = $true
        $terminalButton.Text = '▼  Terminal Preference for DistroShelf'
    }
})

$refresh = New-Object System.Windows.Forms.Button
$refresh.Text = 'Scan again'
$refresh.Location = New-Object System.Drawing.Point(24, 570)
$refresh.Size = New-Object System.Drawing.Size(120, 38)
$form.Controls.Add($refresh)

$install = New-Object System.Windows.Forms.Button
$install.Text = 'Install selected'
$install.Location = New-Object System.Drawing.Point(155, 570)
$install.Size = New-Object System.Drawing.Size(140, 38)
$form.Controls.Add($install)

$info = New-Object System.Windows.Forms.Label
$info.Text = 'Only terminals currently supported by DistroShelf are offered. Installation actions remain disabled while detection is being validated.'
$info.Location = New-Object System.Drawing.Point(24, 620)
$info.Size = New-Object System.Drawing.Size(696, 35)
$form.Controls.Add($info)

function Refresh-Scan {
    $list.Items.Clear()
    foreach ($component in $script:Components) {
        $status = & $component.Detect
        $item = New-Object System.Windows.Forms.ListViewItem($component.Name)
        [void]$item.SubItems.Add($component.Group)
        [void]$item.SubItems.Add($status)
        $item.Tag = $component
        $item.Checked = ($status -notlike 'Installed*' -and $status -ne 'Configured')
        [void]$list.Items.Add($item)
    }
}

$refresh.Add_Click({ Refresh-Scan })
$install.Add_Click({
    [System.Windows.Forms.MessageBox]::Show(
        'Installation is intentionally disabled in this first prototype. We are validating detection before executing any changes.',
        'Development build', 'OK', 'Information') | Out-Null
})

Refresh-Scan
[void]$form.ShowDialog()
