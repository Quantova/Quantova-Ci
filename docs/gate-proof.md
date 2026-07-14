# Crypto deny gate proof

This records that the classical crypto deny gate fires. A gate that has never fired is not yet a gate. The deny file lives in this repository and cargo deny enforces it.

## What was run

Two throwaway projects were built against the deny file.

The first project added the k256 crate as a normal dependency. The command cargo deny check bans failed. The reported reason was that the crate k256 at version 0.13.4 is explicitly banned. The process exit code was two.

The second project added the ed25519 dalek crate as a development dependency. The command cargo deny check bans failed again. It refused both the ed25519 dalek crate at version 2.2.0 and its transitive dependency curve25519 dalek at version 4.1.3. The process exit code was two.

## Result

The gate is red on a violation for both a normal dependency and a development dependency, and it is green on a clean tree. Rerun the proof at any time by adding a banned crate to a scratch project and running cargo deny check bans against this deny file.
