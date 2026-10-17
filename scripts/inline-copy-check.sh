#!/usr/bin/env bash
# Copyright 2026 Quantova Inc
# SPDX-License-Identifier: Apache-2.0 OR MIT

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

QTOV_CI_ROOT="$root" python3 - <<'PY'
import os, re, sys

root = os.environ["QTOV_CI_ROOT"]

PAIRS = [
    ("scripts/pin-agreement.sh", ".github/workflows/rust-ci.yml", "pins"),
    ("scripts/pin-agreement.sh", ".github/workflows/release.yml", "pin-agreement"),
    ("scripts/symbol-scan.sh", ".github/workflows/rust-ci.yml", "symbol-scan"),
    ("scripts/symbol-scan.sh", ".github/workflows/release.yml", "symbol-scan"),
    ("scripts/emoji-scan.sh", ".github/workflows/rust-ci.yml", "emoji"),
    ("scripts/idfmt-scan.sh", ".github/workflows/rust-ci.yml", "idfmt"),
]

OPEN = re.compile(r"^(\s*)\S.*<<'(PY|SH)'\s*$")

def heredoc(lines, start, stop, where):
    for i in range(start, stop):
        m = OPEN.match(lines[i])
        if not m:
            continue
        indent, delim = m.group(1), m.group(2)
        body = []
        for j in range(i + 1, stop):
            line = lines[j]
            if line.rstrip("\n") == indent + delim:
                return "".join(body)
            if line.strip() == "":
                body.append("\n")
            elif line.startswith(indent):
                body.append(line[len(indent):])
            else:
                sys.exit("inline-copy-check: %s line %d is outside the block indentation" % (where, j + 1))
        sys.exit("inline-copy-check: %s has an unterminated %s block" % (where, delim))
    sys.exit("inline-copy-check: %s has no inline script block" % where)

def job_bounds(lines, job, where):
    start = None
    for i, line in enumerate(lines):
        if line.rstrip("\n") == "  %s:" % job:
            start = i
            break
    if start is None:
        sys.exit("inline-copy-check: %s has no job %s" % (where, job))
    stop = len(lines)
    for i in range(start + 1, len(lines)):
        if re.match(r"^  [A-Za-z0-9_-]+:\s*$", lines[i]):
            stop = i
            break
    return start, stop

def read_lines(rel):
    with open(os.path.join(root, rel), encoding="utf-8") as fh:
        return fh.readlines()

fail = 0
for script, workflow, job in PAIRS:
    script_lines = read_lines(script)
    canonical = heredoc(script_lines, 0, len(script_lines), script)
    wf_lines = read_lines(workflow)
    start, stop = job_bounds(wf_lines, job, workflow)
    inline = heredoc(wf_lines, start, stop, "%s job %s" % (workflow, job))
    if inline == canonical:
        print("ok   %s job %s matches %s" % (workflow, job, script))
    else:
        print("FAIL %s job %s differs from %s" % (workflow, job, script))
        a = canonical.splitlines()
        b = inline.splitlines()
        for n in range(max(len(a), len(b))):
            x = a[n] if n < len(a) else None
            y = b[n] if n < len(b) else None
            if x != y:
                print("  first difference at block line %d" % (n + 1))
                print("  script:   %r" % x)
                print("  workflow: %r" % y)
                break
        fail = 1
sys.exit(fail)
PY
