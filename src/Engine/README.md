# Engine boundaries

The Engine layer owns orchestration semantics only.

- `TransactionEngine.ps1`: transaction lifecycle and failure preservation.
- `HashEngine.ps1`: deterministic integrity proofs.
- `DagScheduler.ps1`: dependency-derived execution eligibility and bounded concurrency.
- `TestEngine.ps1`: execution of declarative verification commands.
- `AcceptanceEngine.ps1`: final whole-environment acceptance gates.
- `AtomicCommit.ps1`: promotion of verified attempt state and atomic metadata replacement.

No engine file should contain Ubuntu/Debian/Fedora/Arch/openSUSE package-manager branching. That belongs in distro definitions.
