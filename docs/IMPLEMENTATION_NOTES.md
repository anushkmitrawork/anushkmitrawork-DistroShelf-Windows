# Implementation notes

## Package acquisition

Track construction must resolve and acquire the complete package set for each dependency stage into an isolated stage directory. The Profile side must install only from those local artifacts.

APT stages use an isolated `Dir::Cache::archives` directory with `apt-get --download-only`, which lets APT resolve the dependency closure without installing it. The same directory is then used for Track verification and export.

DNF stages use `--downloadonly --downloaddir` so the resolved RPM set is persisted in the stage artifact directory.

Pacman stages use `-w/--downloadonly` with an isolated cache directory and later install the resulting package files with `pacman -U`.

Zypper stages use `--download-only` with an isolated package cache directory, then install the downloaded RPM set as local files.

## Flatpak

A single `.flatpak` bundle is not sufficient as the generic offline artifact because it does not include dependencies. Track acquisition therefore uses Flatpak sideload repositories (`create-usb`) for the DistroShelf application and its required runtime/dependencies. Profile installation consumes that local sideload repository.

## Verification

A stage is trusted only after its declared functional tests pass. Its hash is then generated over the exported stage tree. Subsequent stages use the hash as the prerequisite gate.

## References

Podman documents native installation through apt, dnf, pacman and zypper for the five target families. Debian documents recursive package dependencies through APT. The Flatpak documentation recommends `create-usb`/sideload repositories for offline application distribution because single-file bundles do not include dependencies.
