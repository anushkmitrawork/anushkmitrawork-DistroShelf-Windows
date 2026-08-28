# Development

## Current milestone: detection engine

The `dev` branch currently contains a Windows PowerShell + WinForms prototype. It deliberately does not install or modify anything.

Run it from Windows PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\src\DistroShelfSetup.ps1
```

The prototype scans:

- WSL 2
- Ubuntu WSL distribution
- Podman
- Distrobox
- Flatpak
- Flathub
- GNOME Console (`kgx`)
- DistroShelf
- Git for Windows

Commands intended for Linux are executed through `wsl.exe --distribution <name> -- bash -lc ...`; the program never injects keystrokes into an existing terminal window.

## Next milestones

1. Validate detection on clean Windows 11 + WSL installations.
2. Improve component model and error reporting.
3. Add safe installation providers.
4. Add dependency ordering and reboot checkpoints.
5. Add verification and repair actions.
6. Package the application for normal Windows distribution.
7. Add CI tests and release artifacts.
