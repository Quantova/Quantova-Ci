# Cross repo pin agreement

A tag and a running build must never disagree. A binary in this stack pins each cross repo git dependency at a tag, and the lockfile records the commit that tag resolved to when the lock was written. Nothing stops a tag from being moved at the remote afterwards, and nothing stops a lockfile from being regenerated against a different commit. Either drift leaves a green build that no longer matches the tag it claims. This gate closes that hole rather than moving it up a level.

## The three facts

For each cross repo git dependency of a binary the gate reads three facts and asserts they agree.

The first is the declared pin. It is the intended tag for the dependency, written in a committed declaration file that the binary carries. The declaration is the one place the intended tag is stated, and it changes only in a deliberate reviewable commit.

The second is the committed lockfile commit. It is the commit the Cargo.lock resolved that dependency to, read from the git source string cargo writes for the package.

The third is the remote peeled tag. It is the commit the remote tag actually points to, taken from git ls-remote with the tag peeled to its commit. An annotated tag peels through its tag object to the commit it wraps.

The gate asserts the declared tag, peeled at the remote, equals the commit the committed lockfile resolved to, and that the lockfile pinned the declared tag. A tag moved and re pointed at the remote breaks agreement with the lockfile. A lockfile regenerated against a different commit breaks agreement with the declared tag. Because the declaration moves only in a reviewable commit, a silent drift on any of the three turns the build red, and the failure names the dependency and prints all three values.

## The declaration file

The declaration is a plain text file at the repository root named cross-repo-pins. It holds one cross repo git dependency per line, two whitespace separated fields, the repository and the tag, and nothing more. Blank lines and lines that open with a comment marker are ignored. The repository is the GitHub repository name under the Quantova organization, which is the only owner the stack pins.

```
# Cross repo pins. One git dependency per line: repository then tag.
QRC-CONSENSUS  v0.4.0
q-prover       v0.8.0
```

One repository supplies many crates that all resolve to a single commit at one tag, so the pin is stated once for the repository and covers every crate it provides.

## How a binary repository adopts it

A binary repository does three things.

It commits its Cargo.lock so the resolved commits are part of the record.

It commits the declaration file at the repository root, naming each cross repo dependency and the tag it is pinned at.

It imports the shared pipeline, which already carries the gate as its own job, the same way it already carries the classical crypto deny gate. A consuming repository writes

```
jobs:
  ci:
    uses: Quantova/Quantova-Ci/.github/workflows/rust-ci.yml@main
```

and the pin agreement job runs on every push and pull request beside the deny job. The job peels the live remote with git ls-remote and needs nothing from the consuming repository beyond its declaration file and its Cargo.lock. A repository that carries no declaration file passes the job untouched, so the gate stays inert until a binary opts in by committing a declaration.

The gate also runs by hand from a checkout of this repository against any working tree. The checker takes a target directory and reads the declaration file and the Cargo.lock inside it.

```
scripts/pin-agreement.sh path/to/binary
```

## Which repositories carry it

The four binaries commit their Cargo.lock and a declaration file, the chain, the node, the devnet, and the harness. Libraries do not. A library is consumed at a tag and resolves its own dependencies inside the binary that builds it, so it carries neither a committed lockfile nor a declaration. This split is fixed in the stack handoff and is not reopened here.

Wiring the gate into the four binary repositories is a separate coordinated step. This document records how a binary adopts the gate. It does not change those repositories.

## The proof

Three self tests committed beside the checker prove the gate, each a fixture and an assertion. The first is agreement, a declaration, a lockfile, and a peeled tag that all match, and the check exits zero. The second is a moved tag, the peeled tag commit differs from the lockfile commit, and the check exits nonzero naming the dependency. The third is a regenerated lock, the lockfile commit differs from the declared tag commit, and the check exits nonzero naming the dependency. The remote peel is stubbed from a committed fixture in each case, so the self tests are hermetic and deterministic and never reach a remote, while the real run peels the live remote. Rerun the proof at any time by running the self test over the committed fixtures.

```
scripts/pin-agreement-selftest.sh
```
