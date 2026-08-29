# Track engine

A Track is a reusable verified acquisition source. It is independent of Profiles.

## Contract

- Build only inside a transaction attempt.
- A stage may consume only verified prerequisite hashes.
- A stage creates its hash only after its Track tests pass.
- The final Track hash is created only after the full Track acceptance suite passes.
- Only a verified final Track may be promoted to `tracks/<Distro>0`.
- Profile creation must treat committed Track artifacts as read-only inputs.
