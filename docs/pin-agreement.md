# Cross repo pin agreement

A declared pin and a running build must never disagree. A repository in this stack pins each cross repo git dependency by commit or by tag, and the lockfile records the commit cargo resolved it to. Nothing stops a tag from being moved at the remote afterwards, nothing stops a lockfile from being regenerated against a different commit, and a path dependency on a sibling checkout leaves no commit in the lockfile at all. Each of these leaves a green build that no longer matches what it claims. This gate closes those holes.

## The rules

The gate reads every git source in the committed `Cargo.lock` and every `path` value in every tracked `Cargo.toml`.

1. Every git source must name a rev or a tag. A source that follows a branch, or names neither, is reported as unpinned. A rev must be a commit prefix of the commit the source resolved to.
2. One repository resolves to exactly one commit in one lockfile. Two commits of the same repository in one lockfile fail the gate, because one build would then link two copies of that code.
3. When the repository carries a `cross-repo-pins` file, every line of it is checked. A full 40 hex commit pin requires every lockfile source of that repository, whether it names a rev or a tag, to resolve to exactly that commit. A tag pin requires every source of that repository to name that tag and to resolve to the commit the remote tag peels to, read with `git ls-remote`. A declared repository with no git source and no path dependency fails.
4. When the repository carries a `cross-repo-pins` file, every path dependency that leaves the repository root must be declared in it. The declared name is the first directory outside the repository, so `path = "../QCore.rs"` is declared as `QCore.rs`. The commit stated for it is the one the repository workflows check out beside it.
5. A repository without a `cross-repo-pins` file still has rules 1 and 2 enforced. It fails only if its lockfile carries a tag pinned git source, which must be declared. A repository with no cross repo source passes.

Every failure names the repository and prints the values that disagree.

## The declaration file

The declaration is a plain text file at the repository root named `cross-repo-pins`. It holds one repository per line, two whitespace separated fields, the repository and its pin, which is a full 40 hex commit or a tag. A hexadecimal pin shorter than 40 characters is refused as ambiguous. Blank lines and lines that open with a comment marker are ignored. The repository is the GitHub repository name under the Quantova organization.

```
Q-Crypto        12fefda211c5b7f8a8e9ed60e6a35d880da54c38
Quantova-Chain  3ed57775e1171f870e0236d8d605e07b6dc03761
QVM             f7d82abb13a01039d78dca732660fd6700d7b830
QCore.rs        c52b2b41dfc61e1ce7445e3caf26396b02226e85
```

One repository supplies many crates that all resolve to a single commit, so the pin is stated once for the repository and covers every crate it provides.

## One implementation

The checker lives in `scripts/pin-agreement.sh`. A reusable workflow runs in the checkout of the repository that calls it and cannot read files from this repository, so the `pins` job of `rust-ci.yml` and the `pin-agreement` job of `release.yml` carry the same program inline. The `inline-copies` job, which runs only in this repository, runs `scripts/inline-copy-check.sh` and fails when an inline copy differs by a single byte from its script. The symbol scan, the emoji lint and the identifier format lint are held to their scripts the same way.

## How a repository adopts it

A repository commits its Cargo.lock, commits the declaration file at its root, and imports the shared pipeline, which carries the gate as its `pins` job.

```
jobs:
  ci:
    uses: Quantova/Quantova-Ci/.github/workflows/rust-ci.yml@<commit>
```

The gate also runs by hand from a checkout of this repository against any working tree.

```
scripts/pin-agreement.sh path/to/repository
```

## The proof

`scripts/pin-agreement-selftest.sh` drives the checker over the fixtures in `fixtures/pin-agreement` and asserts the exit status and the message of each. The fixtures are a tag pin that agrees, a moved tag, a regenerated lockfile, a tag pinned source without a declaration, a commit pin that agrees and also declares a path dependency, a commit pin that disagrees, a branch source, one repository resolved to two commits, and an undeclared path dependency that leaves the repository. The remote peel is stubbed from a committed fixture, so the self test never reaches a remote.

```
scripts/pin-agreement-selftest.sh
```
