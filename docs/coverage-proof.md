# Coverage gate proof

This records that the coverage gate fires. A gate that has never fired is not yet a gate. The gate lives in the `coverage` job in `rust-ci.yml` and runs `cargo llvm-cov --all-features --workspace --fail-under-lines 70` over the same test run the `check` job exercises.

## What was run

A throwaway scratch crate was built with two functions, one exercised by a test and one not. Running `cargo llvm-cov --all-features --workspace --fail-under-lines 70` against it measured 66.67 percent line coverage, below the 70 percent floor, and the command exited with status one.

A test for the second function was then added and the same command run again. Coverage measured 100 percent and the command exited with status zero.

## Result

The gate is red under the floor and green at or above it. Rerun the proof at any time by writing an untested function into a scratch crate and running `cargo llvm-cov --all-features --workspace --fail-under-lines 70` against it, then adding a test for it and running the same command again.
