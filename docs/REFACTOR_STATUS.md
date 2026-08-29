# Refactor status

The `dev` branch is being rebuilt around atomic Track/Profile transactions.

## Retired concepts

- A Profile installing dependencies and then populating Track 0.
- Track readiness represented primarily by booleans.
- Persistent `Pending`/`Installation failed` Profile records.
- Distro-specific branching inside the generic dependency engine.
- GUI code creating committed Profiles before installation succeeds.

## Active architecture

- Track and Profile are separate transactions.
- Stage completion is test-gated.
- Stage hashes are trust gates.
- Track is reusable and read-only to Profile operations.
- Profile is committed only after whole-environment acceptance passes.
- Failed attempts are preserved in Troubleshoot.
- Distro-specific implementation is declarative and separate from execution engines.
- DAG scheduling derives safe concurrency from prerequisites.

The old installer entry points are intentionally being removed or replaced rather than preserved for backwards compatibility.
