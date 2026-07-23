# Quantova-Ci

The shared continuous integration for the whole Quantova organization. Every repository imports it, so the post quantum only rule and the house style are enforced from one place rather than copied and drifting across repositories.

Quantova is a sovereign post quantum Layer 1 with only NIST standardized schemes and no classical escape hatch anywhere. A rule that strong is only real if it is machine checked on every change. Quantova-Ci is where that check lives. POLICY-crypto in the Quantova-Specs repository is the supreme law, and the gates here are its executable form.

## What a repository imports

A repository wires the reusable pipeline in a few lines.

```yaml
jobs:
  ci:
    uses: Quantova/Quantova-Ci/.github/workflows/rust-ci.yml@main
```

A repository that ships a binary also imports the release gate.

```yaml
jobs:
  release:
    uses: Quantova/Quantova-Ci/.github/workflows/release.yml@main
```

The repository that implements the bridge Airlock and the repository that implements the Q-Oracle message parser also import the fuzz gate.

```yaml
jobs:
  fuzz:
    uses: Quantova/Quantova-Ci/.github/workflows/fuzz.yml@main
```

No repository merges while these are red.

## The gates

### Classical crypto deny list

`deny.toml` is the machine readable form of POLICY-crypto. It bans the classical crypto crates, k256, ed25519-dalek, curve25519-dalek, p256, secp256k1, rsa, bls12_381, the arkworks pairing crates, and openssl, anywhere in the dependency tree, including transitive and development dependencies. The `deny` job runs `cargo deny check` for bans, licenses, sources, and advisories. Sources are restricted to the Quantova organization pinned by git tag, licenses to Apache-2.0 and MIT, and a duplicate crate version is a hard failure so a split crypto graph cannot land quietly. This is layer one of post quantum independence, the dependency layer. Q-Oracle is the single repository exempt from the ban and nothing imports it.

### Binary symbol scan

Layer two catches what a dependency scan cannot see, classical code that was vendored or hand written into the crate itself. The release gate builds the release binaries and runs `scripts/symbol-scan.sh`, which reads the strings of every executable and fails on a classical crypto signature, curve names like secp256k1 and curve25519, pairing names like bls12 and bn254, and the low level markers EC_POINT, BN_mod_exp, and RSA_. A binary that carries any of them does not ship.

### Cross repo pin agreement

A tag and a running build must never disagree. For every cross repo git dependency of a binary the gate reads three facts and asserts they agree, the declared pin from the committed `cross-repo-pins` file, the commit the committed `Cargo.lock` resolved to, and the commit the remote tag actually points to, peeled with `git ls-remote`. A tag re pointed at the remote, or a lockfile regenerated against a different commit, breaks agreement and turns the build red with all three values named. The `pins` job in the shared pipeline runs it on every push and pull request, and the `pin-agreement` job in the release gate runs the same check again so a release cannot go out on a pin that moved since the last ordinary run. A hermetic self test, `scripts/pin-agreement-selftest.sh`, drives the checker over the fixtures in `fixtures/pin-agreement`, an agreeing tree, a moved tag, and a regenerated lockfile, so the gate is proven to fire and not only to pass.

### Fuzz gate

An Airlock submission arrives from a foreign chain, a Q-Oracle report arrives from off chain, and both cross a trust boundary an ordinary test suite does not probe. A fuzz target for each parser is held to two properties against random and mutated input, it never panics, and it rejects every artifact that does not open with its own Quantova header. `fixtures/fuzz/bridge-message-parsers` is the pattern a fuzz target follows, and `docs/fuzz.md` records how a repository adopts the gate. Two more fixtures, `dirty-accepts-foreign` and `dirty-panics`, each carry one deliberately broken parser and a committed regression input, and `scripts/fuzz-selftest.sh`, wired into the shared pipeline as the `fuzz-selftest` job, proves the gate turns red on both before it is trusted to pass a clean parser.

### Coverage gate

fmt, clippy, and a passing test suite still leave room for a function no test ever calls. The `coverage` job runs `cargo llvm-cov` over the same test run the `check` job exercises and fails the build under 70 percent line coverage. `docs/coverage-proof.md` records the gate firing under the floor and passing at it.

### Content lints

Two scanners run over the tracked files of every repository.

- The emoji lint, `scripts/emoji-scan.sh`, fails on a pictographic code point. Box drawing is permitted and never reported.
- The identifier format lint, `scripts/idfmt-scan.sh`, fails on the shape of an Ethereum hash or address, a `0x` followed by six or more hexadecimal characters. The pattern is permitted only as a bare integer literal in Rust source for low level bit math, and it is reported inside strings, inside comments, and in every non Rust file. This keeps another chain's identifier conventions out of the surface.

### Standing lint policy

`lints.toml` records the organization wide Rust and Clippy policy that repositories inherit. Unsafe code is denied, the Clippy lint set is denied as warnings, and floating point arithmetic is denied on the consensus, gas, and state paths where determinism is load bearing.

### Action pins

Every action every workflow here uses resolves by commit hash, never a tag or a branch. A tag can be repointed at the remote after it has been reviewed and trusted, the same drift the pin agreement gate exists to catch in a dependency, so the actions this pipeline runs on are held to the same standard. `dtolnay/rust-toolchain` is pinned to a commit on its `master` branch with the toolchain named explicitly through its `toolchain` input, rather than to one of its channel branches, since those branches are the moving part by design. Bumping any pin is a deliberate, reviewable change to the workflow file that carries it.

## Proof over assertion

A gate that has never fired is not yet a gate. The `docs` directory records that each one fires on a real violation and passes on a clean tree, with the exact commands to reproduce. `docs/gate-proof.md` for the deny gate, `docs/lint-proofs.md` for the two content lints, `docs/pin-agreement.md` for the pin agreement gate, `docs/fuzz.md` for the fuzz gate, and `docs/coverage-proof.md` for the coverage gate.

## Governance and license

Governed by the crypto policy, POLICY-crypto, in the Quantova-Specs repository, whose executable form lives here. Commits are authored by the owner only. Dual licensed under Apache 2.0 and MIT.
