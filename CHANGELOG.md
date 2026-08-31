# DistroShelf — Changelog

## Phase 1 — Provider Alignment (complete)

- Aligned Debian, Fedora, ArchLinux, openSUSE providers to the Ubuntu reference:
  SchemaVersion=4, symmetric TrackFinalTests (3) and ProfileFinalTests (2),
  distrobox-list and flatpak-remotes functional tests, rootfs architecture coverage.
- Removed the invalid `-MaxConcurrency` parameter from `tests/UbuntuLive.Tests.ps1`.
- All 9 static/contract tests verified; PR #2 merged into `dev`.

## Phase 2 — Ubuntu Live Track Execution

- Pre-flight verified the full live-test dependency chain (16 modules, all 12
  called functions, opt-in guard, no `wsl --export` in ProfileCommit).
- `[live]` commit authorizes the CI end-to-end gate. On a real WSL2 host this
  persists Track `Ubuntu0` under `%LOCALAPPDATA%\DistroShelf\tracks` and
  builds a committed DistroShelf profile from the verified Track.
