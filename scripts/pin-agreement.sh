#!/usr/bin/env bash
# Cross repo pin agreement check.
#
# For every cross repo git dependency of a binary, three facts must agree:
#   1. the declared pin, the intended tag for the dependency, from the committed
#      cross-repo-pins file in the repository;
#   2. the committed lockfile, the commit the Cargo.lock resolved that dependency to;
#   3. the remote peeled tag, the commit the remote tag actually points to.
# The check asserts the declared tag, peeled at the remote, equals the commit the
# committed lockfile resolved to, and that the lockfile pinned the declared tag.
# A moved tag re-pointed at the remote, or a regenerated lockfile that resolved
# elsewhere, breaks agreement and fails the check.
#
# Usage: scripts/pin-agreement.sh [repo-dir]
# Reads <repo-dir>/cross-repo-pins and <repo-dir>/Cargo.lock. repo-dir defaults to
# the current directory. Exits zero when every declared dependency agrees, and
# exits nonzero with a message naming the dependency and the three values when any
# pair disagrees.
#
# The real run peels the live remote with git ls-remote. Setting QTOV_PIN_PEEL_FIXTURE
# to a fixture file makes the peel read from that file instead of the network, which
# is how the hermetic self tests run without reaching any remote.
set -euo pipefail

dir="${1:-.}"

QTOV_PINS_FILE="$dir/cross-repo-pins" \
QTOV_LOCK_FILE="$dir/Cargo.lock" \
python3 - <<'PY'
import os, re, subprocess, sys

pins_path = os.environ["QTOV_PINS_FILE"]
lock_path = os.environ["QTOV_LOCK_FILE"]
fixture_path = os.environ.get("QTOV_PIN_PEEL_FIXTURE")

DEFAULT_OWNER = "Quantova"


def die(msg):
    sys.stderr.write("pin-agreement: %s\n" % msg)
    sys.exit(1)


def repo_name(value):
    # The bare repository name used to match a declaration against a lockfile
    # source. A leading git+, a query string, a trailing .git, and any owner or
    # host prefix are not significant; the final path segment, lowercased, is the
    # identity. The stack pins only Quantova repositories, so the bare name is
    # unambiguous.
    value = value.strip()
    value = re.sub(r"^git\+", "", value)
    value = value.split("?", 1)[0]
    value = re.sub(r"\.git$", "", value)
    return value.rstrip("/").rsplit("/", 1)[-1].lower()


def owner_slug(declared_repo):
    # Expand a declared repository to an owner/name slug for the remote url. A bare
    # name takes the Quantova organization, the only owner the stack pins.
    declared_repo = declared_repo.strip().rstrip("/")
    if "/" in declared_repo:
        return declared_repo
    return "%s/%s" % (DEFAULT_OWNER, declared_repo)


if not os.path.isfile(pins_path):
    # No declaration means no cross repo pins to police in this repository.
    sys.exit(0)

# Read the declaration: one dependency per line, two whitespace separated fields,
# the repository and the tag. Blank lines and lines opening with a comment marker
# are ignored.
declared = []
seen = set()
with open(pins_path, encoding="utf-8") as fh:
    for lineno, raw in enumerate(fh, start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 2:
            die("%s:%d expected `repository tag`, found %r" % (pins_path, lineno, line))
        repo, tag = parts
        key = repo_name(repo)
        if key in seen:
            die("%s:%d repository %s declared twice" % (pins_path, lineno, repo))
        seen.add(key)
        declared.append((repo, tag))

if not declared:
    sys.exit(0)

if not os.path.isfile(lock_path):
    die("%s declares pins but %s is missing" % (pins_path, lock_path))

# Read the lockfile. Every package block that carries a git source records the tag
# it was pinned at and the commit it resolved to in its source string, of the shape
# git+<url>?tag=<tag>#<commit>. All packages that come from one repository at one
# tag share the same source, so a repository maps to a single (tag, commit) pair.
resolved = {}
source_re = re.compile(r'source = "git\+([^"]+)"')
with open(lock_path, encoding="utf-8") as fh:
    lock_text = fh.read()
for m in source_re.finditer(lock_text):
    src = m.group(1)
    tag_m = re.search(r"[?&]tag=([^&#]+)", src)
    commit_m = re.search(r"#([0-9a-fA-F]{7,40})$", src)
    if not tag_m or not commit_m:
        # A git dependency pinned by rev or branch rather than tag is outside the
        # scope of this gate and is left for the source policy in deny.toml.
        continue
    key = repo_name(src)
    entry = (tag_m.group(1), commit_m.group(1).lower())
    resolved.setdefault(key, set()).add(entry)

peel_fixture = None
if fixture_path is not None:
    peel_fixture = {}
    with open(fixture_path, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, start=1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) != 3:
                die("%s:%d expected `repository tag commit`" % (fixture_path, lineno))
            repo, tag, commit = parts
            peel_fixture[(repo_name(repo), tag)] = commit.lower()


def peel_remote(declared_repo, tag):
    # Peel the tag to the commit it points to. The real run asks the live remote
    # with git ls-remote and prefers the peeled (^{}) line, which resolves an
    # annotated tag to its commit; a lightweight tag has only the plain line. A
    # fixture, when set, answers from a committed file so the self tests never
    # reach the network.
    if peel_fixture is not None:
        commit = peel_fixture.get((repo_name(declared_repo), tag))
        if commit is None:
            die("peel fixture has no entry for %s %s" % (declared_repo, tag))
        return commit
    url = "https://github.com/%s.git" % owner_slug(declared_repo)
    out = subprocess.run(
        ["git", "ls-remote", url, "refs/tags/%s" % tag, "refs/tags/%s^{}" % tag],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        die("git ls-remote failed for %s %s: %s" % (declared_repo, tag, out.stderr.strip()))
    plain = None
    peeled = None
    for row in out.stdout.splitlines():
        sha, _, ref = row.partition("\t")
        if ref.endswith("^{}"):
            peeled = sha.strip().lower()
        elif ref:
            plain = sha.strip().lower()
    commit = peeled or plain
    if commit is None:
        die("remote has no tag %s in %s" % (tag, declared_repo))
    return commit


def short(commit):
    return commit[:12] if commit else commit


failures = 0
for declared_repo, declared_tag in declared:
    key = repo_name(declared_repo)
    entries = resolved.get(key)
    if not entries:
        sys.stderr.write(
            "pin-agreement: %s: declared at %s but no git dependency on it is present in %s\n"
            % (declared_repo, declared_tag, lock_path)
        )
        failures += 1
        continue
    if len(entries) > 1:
        joined = ", ".join("%s at %s" % (t, short(c)) for t, c in sorted(entries))
        sys.stderr.write(
            "pin-agreement: %s: lockfile resolves it to more than one pin: %s\n"
            % (declared_repo, joined)
        )
        failures += 1
        continue
    lock_tag, lock_commit = next(iter(entries))
    remote_commit = peel_remote(declared_repo, declared_tag)

    tag_ok = lock_tag == declared_tag
    commit_ok = lock_commit == remote_commit
    if tag_ok and commit_ok:
        continue

    failures += 1
    if not tag_ok:
        reason = "declared tag and lockfile tag disagree"
    else:
        reason = "lockfile commit and remote peeled commit disagree"
    sys.stderr.write("pin-agreement: %s: %s\n" % (declared_repo, reason))
    sys.stderr.write("  declared tag:         %s\n" % declared_tag)
    sys.stderr.write("  lockfile tag:         %s\n" % lock_tag)
    sys.stderr.write("  lockfile commit:      %s\n" % lock_commit)
    sys.stderr.write("  remote peeled commit: %s\n" % remote_commit)

sys.exit(1 if failures else 0)
PY
