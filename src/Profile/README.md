# Profile engine

A Profile is an independent environment built from a verified Track.

## Contract

- Verify the Track final hash before starting.
- Create a profile candidate/reservation only inside the transaction.
- Install Track-managed resources from verified local Track artifacts.
- Run the complete distro-specific Profile acceptance suite.
- Generate a Profile hash only after 100% mandatory tests pass.
- Commit the Profile record only after the final hash exists.
- Never modify the committed Track during Profile creation.
