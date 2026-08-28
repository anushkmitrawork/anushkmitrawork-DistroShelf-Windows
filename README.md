# DistroShelf for Windows

A Windows setup utility for detecting, installing, repairing, and verifying the components needed for a Distrobox/DistroShelf environment on Windows through WSL2.

## Project status

🚧 Early development — detection engine and architecture are being designed first.

## Goals

- Detect WSL 2, Linux distributions, Podman, Distrobox, Flatpak, Flathub, a supported terminal, DistroShelf, and optional developer tools such as Git.
- Show clear states: Installed, Needs Attention, Not Installed, and Optional.
- Run commands directly in the correct Windows or WSL environment rather than injecting keystrokes into terminal windows.
- Install only selected missing components.
- Handle reboot-required Windows components safely.
- Verify each component after installation.
- Provide repair actions where practical.

## Architecture

The planned application is a native Windows GUI with an orchestration layer that can execute Windows commands directly and invoke Linux commands through `wsl.exe --distribution <name> -- <command>`.

The project intentionally separates detection, installation, verification, and UI so new components can be added without rewriting the application.

## Safety principles

- Never type into or automate an existing terminal window.
- Never assume that an executable being present means the component is functional.
- Never overwrite an existing working environment unnecessarily.
- Make installation operations idempotent where possible.
- Ask before destructive or irreversible operations.

## License

TBD during initial development.
