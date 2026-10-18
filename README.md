# Quantova-Ci

The shared continuous integration for the whole Quantova organization. Every repository imports it, so the post quantum only rule and the house style are enforced from one place rather than copied and drifting across repositories.

Quantova is a sovereign post quantum Layer 1 with only NIST standardized schemes and no classical escape hatch anywhere. A rule that strong is only real if it is machine checked on every change. Quantova-Ci is where that check lives. POLICY-crypto in the Quantova-Specs repository is the supreme law, and the gates here are its executable form.

## What a repository imports

A repository wires the reusable pipeline in a few lines.

```yaml
jobs:
  ci:
    uses: Quantova/Quantova-Ci/.github/workflows/rust-ci.yml@3eedb4e772007f2c5a301a2e2c9cc013481e369c
```

A repository that ships a binary also imports the release gate.

```yaml
jobs:
  release:
    uses: Quantova/Quantova-Ci/.github/workflows/release.yml@3eedb4e772007f2c5a301a2e2c9cc013481e369c
```

The repository that implements the bridge Airlock and the repository that implements the Q-Oracle message parser also import the fuzz gate.

```yaml
jobs:
  fuzz:
    uses: Quantova/Quantova-Ci/.github/workflows/fuzz.yml@3eedb4e772007f2c5a301a2e2c9cc013481e369c
```

A JavaScript package that ships a committed wasm build of a Rust signer imports the npm and wasm gate.

```yaml
on:
  push:
    branches: [main]
    tags: ["v*"]
  pull_request:
jobs:
  sdk:
    uses: Quantova/Quantova-Ci/.github/workflows/npm-wasm-sdk.yml@<commit>
    permissions:
      contents: read
      id-token: write
```

The gates below that are not in the commit a repository pins reach it only when it moves its pin to a commit that carries them.

No repository merges while these are red.

## The gates

### Classical crypto deny list

`deny.toml` is the machine readable form of POLICY-crypto. It bans the classical crypto crates, k256, ed25519-dalek, curve25519-dalek, p256, secp256k1, rsa, bls12_381, the arkworks pairing crates, and openssl, anywhere in the dependency tree, including transitive and development dependencies. The `deny` job runs `cargo deny check` for bans, licenses, sources, and advisories. Sources are restricted to the Quantova organization pinned by git tag, licenses to Apache-2.0 and MIT, and a duplicate crate version is a hard failure so a split crypto graph cannot land quietly. This is layer one of post quantum independence, the dependency layer. Q-Oracle is the single repository exempt from the ban and nothing imports it.

### Binary symbol scan

Layer two catches what a dependency scan cannot see, classical code that was vendored or hand written into the crate itself. The `symbol-scan` job of the shared pipeline and of the release gate builds the workspace in release and runs `scripts/symbol-scan.sh`, which reads the strings of every top level artifact in `target/release`, every executable, `lib*.rlib`, `*.so`, `*.dylib`, `*.a` and `*.wasm`, and every `*.wasm` in `target/*/release`. It fails on a classical crypto signature, curve names like secp256k1 and curve25519, pairing names like bls12 and bn254, matched in any case, and the low level markers EC_POINT, BN_mod_exp, RSA_ and the mangled path of the rsa crate, matched exactly so a lowercase run of letters inside a mangled Rust name is not taken for one. It also fails when no artifact was found, so a build that produced nothing cannot pass by scanning nothing. `scripts/symbol-scan-selftest.sh` proves it fires on an executable, on a library archive and on an empty release directory. The scan reads the artifacts of the workspace being built, not the build outputs of its dependencies, which the deny gate covers.

### Cross repo pin agreement

A declared pin and a running build must never disagree. The gate reads every git source in the committed `Cargo.lock`. A source with no rev or tag, such as one that follows a branch, fails as unpinned, and one repository resolving to two commits in one lockfile fails. When the repository carries a `cross-repo-pins` file, each line names a repository and either a full 40 hex commit or a tag. A commit pin requires every lockfile source of that repository to resolve to exactly that commit. A tag pin requires the lockfile to name the tag and to resolve to the commit the remote tag peels to, read with `git ls-remote`. Every path dependency in a tracked `Cargo.toml` that leaves the repository root must then be declared in the file as well. A repository without the file still has the unpinned source and single commit rules enforced, fails if it carries a tag pinned source, and otherwise passes. The `pins` job in the shared pipeline runs it on every push and pull request, and the `pin-agreement` job in the release gate runs the same check again. A hermetic self test, `scripts/pin-agreement-selftest.sh`, drives the checker over the fixtures in `fixtures/pin-agreement`, which cover agreeing and disagreeing commit and tag pins, a branch source, two commits of one repository and an undeclared path dependency. `docs/pin-agreement.md` has the full rules and `docs/pin-flow.md` the pins the stack resolves today.

### One implementation for every inline gate

A reusable workflow runs in the checkout of the repository that calls it, so the pin agreement checker, the symbol scan, the emoji lint and the identifier format lint are carried inline in the workflows. Each script in `scripts` is the single source and each inline copy must equal it byte for byte. The `inline-copies` job runs `scripts/inline-copy-check.sh` in this repository only and fails on any difference.

### Fuzz gate

An Airlock submission arrives from a foreign chain, a Q-Oracle report arrives from off chain, and both cross a trust boundary an ordinary test suite does not probe. A fuzz target for each parser is held to two properties against random and mutated input, it never panics, and it rejects every artifact that does not open with its own Quantova header. `fixtures/fuzz/bridge-message-parsers` is the pattern a fuzz target follows, and `docs/fuzz.md` records how a repository adopts the gate. Two more fixtures, `dirty-accepts-foreign` and `dirty-panics`, each carry one deliberately broken parser and a committed regression input, and `scripts/fuzz-selftest.sh`, wired into the shared pipeline as the `fuzz-selftest` job, proves the gate turns red on both before it is trusted to pass a clean parser. A repository that imports the fuzz gate and has no target in `fuzz/fuzz_targets` fails it, unless it sets the input `require-targets` to false. Each target runs for `seconds-per-target` seconds, 300 by default and never less than 60.

### Coverage gate

fmt, clippy, and a passing test suite still leave room for a function no test ever calls. The `coverage` job runs `cargo llvm-cov` over the same test run the `check` job exercises and fails the build under 70 percent line coverage. `docs/coverage-proof.md` records the gate firing under the floor and passing at it.

### Content lints

Two scanners run over the tracked files of every repository.

- The emoji lint, `scripts/emoji-scan.sh`, fails on a pictographic code point. Box drawing is permitted and never reported. Files under a directory named `hostile`, which hold adversarial test input, are skipped by both lints.
- The identifier format lint, `scripts/idfmt-scan.sh`, fails on the shape of an Ethereum hash or address, a `0x` followed by six or more hexadecimal characters. The pattern is permitted only as a bare integer literal in Rust source for low level bit math, and it is reported inside strings, inside comments, and in every non Rust file. This keeps another chain's identifier conventions out of the surface.

### Standing lint policy

`lints.toml` records the organization wide Rust and Clippy policy. The shared pipeline enforces the part of it that every repository importing the pipeline passes today, and the rest is opt in.

1. Enforced for every repository. The `check` job runs Clippy over all targets with warnings as errors and denies `clippy::dbg_macro`, `clippy::todo` and `clippy::unimplemented`.
2. Opt in. Setting the input `deny-unsafe-code` to true adds `-D unsafe_code` and setting `deny-float-arithmetic` to true adds `-D clippy::float_arithmetic`. They are not on by default because Q-Crypto, QRC-CONSENSUS, QVRF and q-prover use unsafe code for SIMD and for volatile wiping of secrets, and Q-Crypto, QRC-CONSENSUS and q-prover use floating point in benches, examples, the sortition probability report and the prover soundness estimate. Q-Lightclient, QVM, Quanta-Smart-Contract-language and Quantova-Conformance pass both, and QVRF passes the floating point rule.
3. Advisory only. The panic and arithmetic pass, `clippy::indexing_slicing` and `clippy::arithmetic_side_effects`, runs on every build and never fails it, because every Rust repository importing the pipeline reports hundreds of hits.

Each repository may enforce more through its own `[lints]` table and `forbid(unsafe_code)` attributes.

### npm and wasm gate

`npm-wasm-sdk.yml` serves a JavaScript package that commits a wasm build of a Rust signer. Its first job installs the toolchain named by the caller's `rust-toolchain.toml`, or the pinned `rust-toolchain` input when the caller has none, installs binaryen from its release archive checked against a pinned SHA-256, installs wasm-pack and the wasm-bindgen version locked in `native/Cargo.lock` with `cargo install --locked`, reruns the build script, which must build with `--locked`, and fails when the lockfile or anything in the wasm directory differs from what is committed. It then runs `npm ci` and the test command. A second job runs only for a pushed tag that starts with `v`, checks that the tag equals the `package.json` version, runs in the protected `npm` environment with the `id-token` write permission granted to that job alone, and publishes with `npm publish --provenance --access public --ignore-scripts`. The token is read from an `NPM_TOKEN` secret of the `npm` environment. The inputs `native-dir`, `wasm-dir` and `build-script` default to the `native`, `wasm` and `native/build.sh` layout of the Qstamp family packages, and a package without native code passes an empty `native-dir`. The packages define no npm test script yet, so each one adds a test script or passes a `test-command`. Adoption is a step for the owner of each package.

### Action pins

Every action every workflow here uses resolves by commit hash, never a tag or a branch. A tag can be repointed at the remote after it has been reviewed and trusted, the same drift the pin agreement gate exists to catch in a dependency, so the actions this pipeline runs on are held to the same standard. `dtolnay/rust-toolchain` is pinned to a commit on its `master` branch with the toolchain named explicitly through its `toolchain` input, rather than to one of its channel branches, since those branches are the moving part by design. Bumping any pin is a deliberate, reviewable change to the workflow file that carries it.

## Proof over assertion

A gate that has never fired is not yet a gate. The `docs` directory records that each one fires on a real violation and passes on a clean tree, with the exact commands to reproduce. `docs/gate-proof.md` for the deny gate, `docs/lint-proofs.md` for the two content lints, `docs/pin-agreement.md` for the pin agreement gate, `docs/fuzz.md` for the fuzz gate, and `docs/coverage-proof.md` for the coverage gate.

## Governance and license

Governed by the crypto policy, POLICY-crypto, in the Quantova-Specs repository, whose executable form lives here. Commits are authored by the owner only. Dual licensed under Apache 2.0 and MIT.
