# Distro Implementation and Testing Matrix

This matrix is the contract for distro-specific implementation. Commands are intentionally kept with the dependency they implement and test. The executable engine should consume this data rather than hard-code distro branches.

| Distro | Package manager | Track rootfs | Track package acquisition | Profile package installation | Minimum functional test |
|---|---|---|---|---|---|
| Ubuntu | apt | Official WSL AMD64 artifact | `apt-get download` / repository cache acquisition | `apt-get install --no-download` from verified Track resources | `podman --version`; `distrobox --version`; `flatpak --version` |
| Debian | apt | Official WSL AMD64 artifact | `apt-get download` / repository cache acquisition | `apt-get install --no-download` from verified Track resources | `podman --version`; `distrobox --version`; `flatpak --version` |
| Fedora | dnf | Official WSL AMD64 artifact | `dnf download` with required dependency closure | `dnf -C install` from verified local resources | `podman --version`; `distrobox --version`; `flatpak --version` |
| Arch Linux | pacman | Official WSL AMD64 artifact | `pacman` package/cache acquisition with dependency closure | local-cache install without network | `podman --version`; `distrobox --version`; `flatpak --version` |
| openSUSE | zypper | Official WSL AMD64 artifact | RPM acquisition with dependency closure | local RPM installation without refresh/network | `podman --version`; `distrobox --version`; `flatpak --version` |

## Important

This is an architectural matrix, not a claim that the placeholder acquisition commands above are already implemented. Before enabling a command in production, its exact current syntax, repository behavior, dependency closure behavior, and offline installation semantics must be verified for the supported distro release.

Every dependency entry should eventually define:

- prerequisites
- Track acquisition commands
- Track verification commands
- Profile installation commands
- Profile verification commands
- artifact paths
- expected files/binaries
- hash inputs
- optional resource locks
- whether acquisition may run concurrently

Terminal implementations belong to the same matrix and are acquired for Track independently of the terminal selected for a Profile.
