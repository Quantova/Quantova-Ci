#!/usr/bin/env bash
# Copyright 2026 Quantova Inc
# SPDX-License-Identifier: Apache-2.0 OR MIT

set -euo pipefail

python3 - <<'PY'
import subprocess, sys, os, re

pat = re.compile(r"0[xX][0-9A-Fa-f]{6,}")
boundary = set(" \t([{,+*/%&|^~<>=")

def comment_start(line):
    in_str = False
    esc = False
    i = 0
    n = len(line)
    while i < n - 1:
        c = line[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        else:
            if c == '"':
                in_str = True
            elif c == "/" and line[i + 1] == "/":
                return i
        i += 1
    return n

out = subprocess.run(["git", "ls-files", "-z"], capture_output=True).stdout
paths = [p for p in out.split(b"\x00") if p]
fail = 0
for raw in paths:
    path = os.fsdecode(raw)
    if "hostile" in path.replace(os.sep, "/").split("/"):
        continue
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
    is_rs = path.endswith(".rs")
    for lineno, line in enumerate(text.split("\n"), start=1):
        cpos = comment_start(line)
        for m in pat.finditer(line):
            start = m.start()
            prev = line[start - 1] if start > 0 else ""
            head = line[:start]
            in_string = (head.count('"') - head.count('\\"')) % 2 == 1
            bare = start == 0 or prev in boundary
            permitted = is_rs and start < cpos and not in_string and bare
            if permitted:
                continue
            sys.stderr.write("%s:%d Ethereum hex value %s\n" % (path, lineno, m.group(0)))
            fail = 1
sys.exit(1 if fail else 0)
PY
