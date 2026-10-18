#!/usr/bin/env bash
# Copyright 2026 Quantova Inc
# SPDX-License-Identifier: Apache-2.0 OR MIT

set -euo pipefail

dir="${1:-.}"

QTOV_PINS_FILE="$dir/cross-repo-pins" \
QTOV_LOCK_FILE="$dir/Cargo.lock" \
QTOV_REPO_ROOT="$dir" \
python3 - <<'PY'
import os, re, subprocess, sys

pins_path = os.environ["QTOV_PINS_FILE"]
lock_path = os.environ["QTOV_LOCK_FILE"]
repo_root = os.environ.get("QTOV_REPO_ROOT") or "."
fixture_path = os.environ.get("QTOV_PIN_PEEL_FIXTURE")

DEFAULT_OWNER = "Quantova"
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
HEX_RE = re.compile(r"^[0-9a-fA-F]+$")

failures = 0

def die(msg):
    sys.stderr.write("pin-agreement: %s\n" % msg)
    sys.exit(1)

def fail(msg):
    global failures
    sys.stderr.write("pin-agreement: %s\n" % msg)
    failures += 1

def repo_name(value):
    value = value.strip()
    value = re.sub(r"^git\+", "", value)
    value = value.split("#", 1)[0]
    value = value.split("?", 1)[0]
    value = re.sub(r"\.git$", "", value.rstrip("/"))
    return value.rstrip("/").rsplit("/", 1)[-1].lower()

def owner_slug(declared_repo):
    declared_repo = declared_repo.strip().rstrip("/")
    if "/" in declared_repo:
        return declared_repo
    return "%s/%s" % (DEFAULT_OWNER, declared_repo)

def short(commit):
    return commit[:12] if commit else commit

def parse_source(src):
    base, _, commit = src.partition("#")
    query = base.split("?", 1)[1] if "?" in base else ""
    params = {}
    for item in query.split("&"):
        if "=" in item:
            k, v = item.split("=", 1)
            params[k] = v
    return {
        "source": src,
        "repo": repo_name(src),
        "tag": params.get("tag"),
        "rev": params.get("rev"),
        "branch": params.get("branch"),
        "commit": commit.lower(),
    }

lock_sources = []
if os.path.isfile(lock_path):
    with open(lock_path, encoding="utf-8") as fh:
        lock_text = fh.read()
    for m in re.finditer(r'source = "git\+([^"]+)"', lock_text):
        lock_sources.append(parse_source(m.group(1)))

unique_sources = {}
for entry in lock_sources:
    unique_sources.setdefault(entry["source"], entry)

for entry in unique_sources.values():
    if not COMMIT_RE.match(entry["commit"]):
        fail("%s: git source %s does not resolve to a full commit" % (entry["repo"], entry["source"]))
        continue
    if entry["tag"]:
        continue
    rev = entry["rev"]
    if rev and HEX_RE.match(rev) and 7 <= len(rev) <= 40 and entry["commit"].startswith(rev.lower()):
        continue
    if rev:
        fail("%s: git source %s pins rev=%s which is not a commit prefix of the resolved commit" % (entry["repo"], entry["source"], rev))
    elif entry["branch"]:
        fail("%s: git source %s follows branch %s and is unpinned" % (entry["repo"], entry["source"], entry["branch"]))
    else:
        fail("%s: git source %s names no rev or tag and is unpinned" % (entry["repo"], entry["source"]))

commits_by_repo = {}
for entry in lock_sources:
    commits_by_repo.setdefault(entry["repo"], set()).add(entry["commit"])
for repo, commits in sorted(commits_by_repo.items()):
    if len(commits) > 1:
        fail("%s: lockfile resolves it to more than one commit: %s" % (repo, ", ".join(short(c) for c in sorted(commits))))

def manifest_paths():
    out = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "-z", "--", "*Cargo.toml"],
        cwd=repo_root,
        capture_output=True,
    )
    if out.returncode == 0:
        return sorted(os.fsdecode(p) for p in out.stdout.split(b"\x00") if p and os.path.basename(os.fsdecode(p)) == "Cargo.toml")
    found = []
    for base, dirs, files in os.walk(repo_root):
        dirs[:] = [d for d in dirs if d not in (".git", "target", "node_modules")]
        if "Cargo.toml" in files:
            found.append(os.path.relpath(os.path.join(base, "Cargo.toml"), repo_root))
    return sorted(found)

def declared_paths(text):
    try:
        import tomllib
        doc = tomllib.loads(text)
    except Exception:
        return [m.group(1) or m.group(2) for m in re.finditer(r"""(?m)^[^#\n]*?\bpath\s*=\s*(?:"([^"]*)"|'([^']*)')""", text)]
    found = []
    stack = [doc]
    while stack:
        node = stack.pop()
        if isinstance(node, dict):
            value = node.get("path")
            if isinstance(value, str):
                found.append(value)
            stack.extend(node.values())
        elif isinstance(node, list):
            stack.extend(node)
    return found

root_abs = os.path.realpath(repo_root)
external_paths = []
for manifest in manifest_paths():
    full = os.path.join(root_abs, manifest)
    try:
        with open(full, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        continue
    for value in declared_paths(text):
        target = os.path.normpath(os.path.join(os.path.dirname(full), value))
        rel = os.path.relpath(target, root_abs)
        parts = rel.replace(os.sep, "/").split("/")
        if parts[0] != "..":
            continue
        outside = [p for p in parts if p != ".."]
        key = (outside[0] if outside else os.path.basename(target)).lower()
        external_paths.append((manifest, value, key))

if not os.path.isfile(pins_path):
    tagged = sorted({e["repo"] for e in lock_sources if e["tag"]})
    if tagged:
        fail("%s has tag pinned cross repo git dependencies (%s) but no %s" % (lock_path, ", ".join(tagged), pins_path))
    for manifest, value, key in external_paths:
        fail("%s: path dependency %s leaves the repository but there is no %s to pin %s" % (manifest, value, pins_path, key))
    sys.exit(1 if failures else 0)

declared = []
seen = set()
with open(pins_path, encoding="utf-8") as fh:
    for lineno, raw in enumerate(fh, start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 2:
            die("%s:%d expected `repository tag` or `repository commit`, found %r" % (pins_path, lineno, line))
        repo, pin = parts
        if HEX_RE.match(pin) and len(pin) != 40:
            die("%s:%d %s is pinned to %s, a commit pin must be the full 40 hex commit" % (pins_path, lineno, repo, pin))
        key = repo_name(repo)
        if key in seen:
            die("%s:%d repository %s declared twice" % (pins_path, lineno, repo))
        seen.add(key)
        declared.append((repo, pin))

for manifest, value, key in external_paths:
    if key not in seen:
        fail("%s: path dependency %s leaves the repository and %s is not declared in %s" % (manifest, value, key, pins_path))

if not declared:
    sys.exit(1 if failures else 0)

if not os.path.isfile(lock_path) and not external_paths:
    die("%s declares pins but %s is missing" % (pins_path, lock_path))

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

path_keys = {key for _, _, key in external_paths}

for declared_repo, pin in declared:
    key = repo_name(declared_repo)
    entries = [e for e in lock_sources if e["repo"] == key]
    if not entries:
        if key in path_keys:
            continue
        fail("%s: declared at %s but no git or path dependency on it is present" % (declared_repo, pin))
        continue
    if COMMIT_RE.match(pin.lower()):
        want = pin.lower()
        for entry in {e["source"]: e for e in entries}.values():
            if entry["commit"] != want:
                fail("%s: declared commit and lockfile commit disagree" % declared_repo)
                sys.stderr.write("  declared commit:  %s\n" % want)
                sys.stderr.write("  lockfile source:  %s\n" % entry["source"])
                sys.stderr.write("  lockfile commit:  %s\n" % entry["commit"])
        continue
    tags = sorted({e["tag"] or "" for e in entries})
    commits = sorted({e["commit"] for e in entries})
    if tags != [pin]:
        fail("%s: declared tag and lockfile tag disagree" % declared_repo)
        sys.stderr.write("  declared tag:     %s\n" % pin)
        sys.stderr.write("  lockfile tags:    %s\n" % ", ".join(t or "(none)" for t in tags))
        continue
    if len(commits) != 1:
        continue
    remote_commit = peel_remote(declared_repo, pin)
    if commits[0] != remote_commit:
        fail("%s: lockfile commit and remote peeled commit disagree" % declared_repo)
        sys.stderr.write("  declared tag:         %s\n" % pin)
        sys.stderr.write("  lockfile tag:         %s\n" % pin)
        sys.stderr.write("  lockfile commit:      %s\n" % commits[0])
        sys.stderr.write("  remote peeled commit: %s\n" % remote_commit)

sys.exit(1 if failures else 0)
PY
