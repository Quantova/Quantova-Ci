#!/usr/bin/env bash
# Copyright 2026 Quantova Inc
# SPDX-License-Identifier: Apache-2.0 OR MIT

set -euo pipefail

python3 - <<'PY'
import subprocess, sys, os

def flagged(cp):
    return (
        0x1F300 <= cp <= 0x1FAFF
        or 0x2600 <= cp <= 0x27BF
        or cp == 0xFE0F
        or 0x2B00 <= cp <= 0x2BFF
        or 0x2300 <= cp <= 0x23FF
    )

out = subprocess.run(["git", "ls-files", "-z"], capture_output=True).stdout
paths = [p for p in out.split(b"\x00") if p]
fail = 0
for raw in paths:
    path = os.fsdecode(raw)
    if not os.path.isfile(path):
        continue
    try:
        blob = open(path, "rb").read()
    except OSError:
        continue
    if b"\x00" in blob:
        continue
    try:
        text = blob.decode("utf-8")
    except UnicodeDecodeError:
        continue
    line = 1
    for ch in text:
        if ch == "\n":
            line += 1
            continue
        cp = ord(ch)
        if flagged(cp):
            sys.stderr.write("%s:%d pictographic code point U+%04X\n" % (path, line, cp))
            fail = 1
sys.exit(1 if fail else 0)
PY
