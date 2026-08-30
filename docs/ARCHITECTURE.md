# DistroShelf Architecture

## Core rule
DistroShelf follows an atomic, transactional installation model. A Track or Profile is committed only after its required tests pass and its integrity hash is created. Failed work is preserved in `Troubleshoot`.

## Track vs Profile
A Track (`Ubuntu0`, `Debian0`, `Fedora0`, `ArchLinux0`, `openSUSE0`) is a verified reusable acquisition source. It is independent of any Profile.

A Profile (`Debian1`, `Debian2`, etc.) is an independent WSL environment built from its distro's verified Track.

### Separation invariant
Track and Profile are separate lifecycles with separate responsibilities and committed stores.

- **Track acquires and implements** reusable distro resources, verifies dependencies, and produces a verified Track.
- **Profile only implements** from an already verified Track; it does not reacquire Track-managed dependencies.
- A Track does not create, depend on, or become a Profile.
- A Profile does not create, modify, or replace its source Track.
- Track and Profile transactions have distinct transaction kinds and remain isolated until their own acceptance succeeds.
- A Track may be consumed by multiple Profiles; Profile creation must not mutate the committed Track.

Shared engine helpers are permitted, but Track acquisition/verification responsibilities must not move into Profile creation and Profile state must not become Track state.

## Track state machine
Each Track stage follows:

1. Require predecessor hash(es).
2. Acquire/download the stage resources using the distro-specific implementation.
3. Run the distro-specific Track tests.
4. Generate and persist the stage hash only after all required tests pass.
5. Make the next eligible stages runnable.

The final Track hash is generated only after the complete Track acceptance suite passes.

## Profile state machine
A Profile uses an already verified Track. It consumes Track artifacts locally rather than re-downloading Track-managed dependencies.

1. Reserve the next profile number.
2. Create an isolated Profile attempt.
3. Install/use the required Track resources.
4. Run the complete Profile acceptance suite.
5. Generate the final Profile hash only after 100% mandatory tests pass.
6. Atomically commit the Profile and release the reservation.

A Profile does not become a persistent record while the attempt is running.

## Transaction promotion
Track and Profile attempts are the actual in-progress state. On success, the accepted transaction state is promoted to its committed destination; on failure, that same transaction state is preserved in `Troubleshoot`. The destination is not reconstructed from a recipe or summary. If a storage boundary requires controlled copying/finalization, it must preserve the exact transaction contents and identity.

## Core execution
The Core execution model is permanently **linear and deterministic**. Track and Profile correctness must never depend on parallel execution.

- A dependency is executed only after its declared prerequisites have been verified.
- Stages are executed one at a time in a deterministic topological order.
- A successful stage records its verification hash before a dependent stage may execute.
- A failed or unverified stage never unlocks a dependent stage.
- The linear executor is the canonical reference implementation and the permanent fallback path.

The dependency graph remains part of the Core contract because it defines prerequisite correctness. Parallel interpretation of that graph is not part of Core.

## Parallelism feature boundary
Parallelism is a separate optional feature block to be developed only after the five distro Track/Profile implementations and the rest of the Core are complete.

Parallelism may interpret the same dependency graph to improve speed, but it must not change Track/Profile semantics. If the Parallel executor is unavailable or fails, Linear execution remains usable.

## Troubleshoot
An unsuccessful transaction is moved/preserved as the actual attempt. It is not reconstructed from a summary. The failed tree includes artifacts, logs, test results, hashes, metadata, and any staged WSL data needed for diagnosis.

## Source of truth
Directory presence alone never proves validity. A committed stage is trusted only through a valid recorded hash whose creation was gated by successful tests.
