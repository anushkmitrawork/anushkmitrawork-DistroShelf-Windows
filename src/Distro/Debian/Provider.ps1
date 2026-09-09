# DistroShelf Debian Provider
$null = . (Join-Path $PSScriptRoot '..\..\DistroProvider.ps1')

function Get-DistroShelfDebianProvider {
    return [DistroShelfProvider]@{
        Stages = @(
            @{
                Name = 'apt-update'
                Invoke = {
                    param($target, $wsl)
                    # Debian 11 base needs archive repositories or it throws 100 on apt update.
                    # Instead of a destructive hardcoded overwrite to bookworm, we elegantly disable expired sources natively if they fail.
                    $r = &$wsl -d $target -u root --exec bash -c "apt-get update"
                    if ($LASTEXITCODE -ne 0) {
                        # Disable validity check for expired mirrors
                        &$wsl -d $target -u root --exec bash -c "echo 'Acquire::Check-Valid-Until \"false\";' > /etc/apt/apt.conf.d/10no-check-valid-until"
                        
                        # Sometimes bullseye security repos 404, we comment them out so they don't break subsequent apt installs
                        &$wsl -d $target -u root --exec bash -c "sed -i 's/^deb .*bullseye-security/#&/' /etc/apt/sources.list"
                        
                        &$wsl -d $target -u root --exec bash -c "apt-get update"
                        if ($LASTEXITCODE -ne 0) { throw "apt-get update failed even after applying validity and security mirror workarounds." }
                    }
                }
                Test = {
                    param($target, $wsl)
                    &$wsl -d $target -u root --exec bash -c "apt-cache policy >/dev/null 2>&1"
                    return ($LASTEXITCODE -eq 0)
                }
            },
            @{
                Name = 'packages'
                Invoke = {
                    param($target, $wsl)
                    # Distrobox requires curl/wget, ca-certificates, and podman.
                    &$wsl -d $target -u root --exec bash -c 'DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends podman curl wget ca-certificates procps sudo'
                    if ($LASTEXITCODE -ne 0) { throw "Failed to install DistroShelf Debian core dependencies." }
                }
                Test = {
                    param($target, $wsl)
                    &$wsl -d $target --exec bash -c 'command -v podman >/dev/null && command -v curl >/dev/null'
                    return ($LASTEXITCODE -eq 0)
                }
            },
            @{
                Name = 'podman-setup'
                Invoke = {
                    param($target, $wsl)
                    # Create containers.conf directly to enforce networking configuration
                    &$wsl -d $target -u root --exec bash -c 'mkdir -p /etc/containers && echo -e "[network]\nnetwork_backend=\"netavark\"" > /etc/containers/containers.conf'
                    if($LASTEXITCODE -ne 0){throw "Failed to configure Podman networking."}
                }
                Test = {
                    param($target, $wsl)
                    $out = &$wsl -d $target -u root --exec bash -c 'grep netavark /etc/containers/containers.conf'
                    return ($LASTEXITCODE -eq 0 -and $out -match 'netavark')
                }
            },
            @{
                Name = 'distrobox'
                Invoke = {
                    param($target, $wsl)
                    # Pulling distrobox directly via curl to support older rootfs that don't package it natively
                    &$wsl -d $target -u root --exec bash -c 'curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install | sh -s -- --prefix /usr/local'
                    if ($LASTEXITCODE -ne 0) { throw "Distrobox installation script failed." }
                }
                Test = {
                    param($target, $wsl)
                    &$wsl -d $target --exec bash -c 'command -v distrobox >/dev/null'
                    return ($LASTEXITCODE -eq 0)
                }
            },
            @{
                Name = 'flatpak'
                Invoke = {
                    param($target, $wsl)
                    &$wsl -d $target -u root --exec bash -c 'DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends flatpak'
                    if ($LASTEXITCODE -ne 0) { throw "Failed to install flatpak via apt." }
                    &$wsl -d $target -u root --exec bash -c 'flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo && flatpak remote-modify --collection-id=org.flathub.Stable flathub'
                    if ($LASTEXITCODE -ne 0) { throw "Failed to configure flathub remote." }
                }
                Test = {
                    param($target, $wsl)
                    &$wsl -d $target --exec bash -c 'command -v flatpak >/dev/null'
                    return ($LASTEXITCODE -eq 0)
                }
            }
        )
    }
}
