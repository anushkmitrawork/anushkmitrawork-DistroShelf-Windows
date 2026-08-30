# DistroShelf implementation and testing matrix

This matrix is the contributor-facing contract. Keep implementation and verification beside each other. Commands are examples only until validated against the exact supported distro/rootfs release.

| Distro | Stage | Track acquisition | Track test | Profile installation | Profile test |
|---|---|---|---|---|---|
| Ubuntu | rootfs | Provider rootfs acquisition | `/etc/os-release` | import verified rootfs | `/etc/os-release` |
| Ubuntu | Podman | distro package closure | `podman --version`, `podman info` | local Track packages only | `podman --version`, `podman info` |
| Ubuntu | Distrobox | distro package closure | `distrobox --version` | local Track packages only | `distrobox --version` |
| Ubuntu | Flatpak | distro package closure | `flatpak --version` | local Track packages only | `flatpak --version` |
| Ubuntu | Flathub | repository metadata/artifact | remote configured from Track data | local Track data only | remote configured |
| Ubuntu | DistroShelf | Flatpak sideload repository | application metadata | local sideload repository | application metadata |
| Ubuntu | Terminals | all supported terminal package closures | executable/version checks | selected terminal from Track | selected terminal check |
| Debian | rootfs | Provider rootfs acquisition | `/etc/os-release` | import verified rootfs | `/etc/os-release` |
| Debian | Podman | distro package closure | `podman --version`, `podman info` | local Track packages only | `podman --version`, `podman info` |
| Debian | Distrobox | distro package closure | `distrobox --version` | local Track packages only | `distrobox --version` |
| Debian | Flatpak | distro package closure | `flatpak --version` | local Track packages only | `flatpak --version` |
| Debian | Flathub | repository metadata/artifact | remote configured from Track data | local Track data only | remote configured |
| Debian | DistroShelf | Flatpak sideload repository | application metadata | local sideload repository | application metadata |
| Debian | Terminals | all supported terminal package closures | executable/version checks | selected terminal from Track | selected terminal check |
| Fedora | rootfs | Provider rootfs acquisition | `/etc/os-release` | import verified rootfs | `/etc/os-release` |
| Fedora | Podman | distro package closure | `podman --version`, `podman info` | local Track packages only | `podman --version`, `podman info` |
| Fedora | Distrobox | distro package closure | `distrobox --version` | local Track packages only | `distrobox --version` |
| Fedora | Flatpak | distro package closure | `flatpak --version` | local Track packages only | `flatpak --version` |
| Fedora | Flathub | repository metadata/artifact | remote configured from Track data | local Track data only | remote configured |
| Fedora | DistroShelf | Flatpak sideload repository | application metadata | local sideload repository | application metadata |
| Fedora | Terminals | all supported terminal package closures | executable/version checks | selected terminal from Track | selected terminal check |
| Arch Linux | rootfs | Provider rootfs acquisition | `/etc/os-release` | import verified rootfs | `/etc/os-release` |
| Arch Linux | Podman | distro package closure | `podman --version`, `podman info` | local Track packages only | `podman --version`, `podman info` |
| Arch Linux | Distrobox | distro package closure | `distrobox --version` | local Track packages only | `distrobox --version` |
| Arch Linux | Flatpak | distro package closure | `flatpak --version` | local Track packages only | `flatpak --version` |
| Arch Linux | Flathub | repository metadata/artifact | remote configured from Track data | local Track data only | remote configured |
| Arch Linux | DistroShelf | Flatpak sideload repository | application metadata | local sideload repository | application metadata |
| Arch Linux | Terminals | all supported terminal package closures | executable/version checks | selected terminal from Track | selected terminal check |
| openSUSE | rootfs | Provider rootfs acquisition | `/etc/os-release` | import verified rootfs | `/etc/os-release` |
| openSUSE | Podman | distro package closure | `podman --version`, `podman info` | local Track packages only | `podman --version`, `podman info` |
| openSUSE | Distrobox | distro package closure | `distrobox --version` | local Track packages only | `distrobox --version` |
| openSUSE | Flatpak | distro package closure | `flatpak --version` | local Track packages only | `flatpak --version` |
| openSUSE | Flathub | repository metadata/artifact | remote configured from Track data | local Track data only | remote configured |
| openSUSE | DistroShelf | Flatpak sideload repository | application metadata | local sideload repository | application metadata |
| openSUSE | Terminals | all supported terminal package closures | executable/version checks | selected terminal from Track | selected terminal check |
