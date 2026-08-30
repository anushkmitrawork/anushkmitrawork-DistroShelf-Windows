# Ubuntu Track 0 implementation

Ubuntu is the reference Distro Track. Debian, Fedora, Arch Linux, and openSUSE must not be declared complete by copying this contract; each provider will be validated independently.

## Atomic pipeline

```text
rootfs acquire
  -> rootfs verify
  -> rootfs hash
  -> dependency becomes eligible
  -> acquire packages
  -> install packages
  -> stage tests
  -> export reusable artifacts
  -> stage hash
  -> next dependency
  -> final Track acceptance
  -> final Track hash
  -> atomic promotion
  -> post-commit integrity verification
```

A failed stage is never published into Track 0. The whole attempt is preserved under the Troubleshoot store.

## Ubuntu Track stages

| Stage | Depends on | Track acquisition | Track verification | Profile consumption |
|---|---|---|---|---|
| rootfs | none | Official WSL AMD64 artifact | `/etc/os-release`, `uname -m`, `command -v apt-get`, `command -v dpkg` | verified rootfs import |
| podman | rootfs | `apt-get update` + `apt-get --download-only` into stage cache | `podman --version`, `podman info --format json` | local `.deb` artifacts only |
| distrobox | rootfs, podman | `apt-get --download-only` into stage cache | `distrobox --version`, `distrobox list` | local `.deb` artifacts only |
| flatpak | rootfs | `apt-get --download-only` into stage cache | `flatpak --version`, `flatpak remotes --columns=name` | local `.deb` artifacts only |
| flathub | rootfs, flatpak | download `flathub.flatpakrepo` | Flathub remote is present | local `.flatpakrepo` only |
| distroshelf | rootfs, distrobox, flatpak, flathub | install from Flathub, then create sideload repository | `flatpak info com.ranfdev.DistroShelf` | local sideload repository only |
| terminal-gnome-console | rootfs | APT package closure | `command -v kgx`, `kgx --version` | selected `.deb` closure |
| terminal-kitty | rootfs | APT package closure | `command -v kitty`, `kitty --version` | selected `.deb` closure |
| terminal-alacritty | rootfs | APT package closure | `command -v alacritty`, `alacritty --version` | selected `.deb` closure |
| terminal-foot | rootfs | APT package closure | `command -v foot`, `foot --version` | selected `.deb` closure |
| terminal-konsole | rootfs | APT package closure | `command -v konsole`, `konsole --version` | selected `.deb` closure |

Ubuntu package availability is release-sensitive. The implementation resolves the installed rootfs's configured repositories at execution time and treats the resulting package closure as the Track artifact. Current Ubuntu package listings show Podman, Distrobox, GNOME Console (`kgx`), Kitty, Alacritty, Foot, and Konsole are available in supported Ubuntu suites; the live Track test remains the authority for the exact WSL rootfs selected by the official WSL manifest.

## Hash rule

A stage hash is SHA-256 of the exact Track artifact directory for that stage. Hash creation is allowed only after that stage's verification suite passes. The next stage can execute only when its prerequisite hash records still validate against their artifact directories.

The final Track hash is SHA-256 over the complete Track tree excluding only the self-referential final metadata files `metadata/track.hash.json` and `metadata/track.json`.

## Profile rule

A Profile never re-downloads Track-managed dependencies. It verifies the committed Track, bridges the required stage artifacts into an isolated WSL environment, installs the user's selected terminal only, runs the complete Profile acceptance suite, exports the accepted environment exactly once, hashes that exact export, and commits that same artifact.

## Live verification

Run the explicit Ubuntu live integration test from an elevated PowerShell with WSL 2 enabled:

```powershell
$env:DISTROSHELF_RUN_LIVE_TESTS='1'
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\UbuntuLive.Tests.ps1
```

The live test is intentionally not part of ordinary CI because it performs real downloads, WSL imports, package installation, and artifact creation.
