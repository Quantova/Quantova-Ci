#!/usr/bin/env bash
# Copyright 2026 Quantova Inc
# SPDX-License-Identifier: Apache-2.0 OR MIT

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
fixtures="$root/fixtures/fuzz"

fail=0

report() {
  if [ "$1" = "0" ]; then
    echo "ok   $2"
  else
    echo "FAIL $2"
    fail=1
  fi
}

if ! cargo +nightly fuzz --version >/dev/null 2>&1; then
  echo "fuzz-selftest: cargo fuzz is not available on a nightly toolchain named 'nightly'" >&2
  echo "install with: rustup toolchain install nightly && cargo install cargo-fuzz --locked" >&2
  exit 1
fi

run_clean() {
  local crate="$1" target="$2"
  local work
  work="$(mktemp -d)"
  cp "$fixtures/$crate/fuzz/corpus/$target"/* "$work"/ 2>/dev/null || true
  ( cd "$fixtures/$crate" && cargo +nightly fuzz run "$target" -- -runs=1000000 -max_len=1024 "$work" ) \
    >"$work.log" 2>&1
  local code=$?
  rm -rf "$work"
  if [ "$code" = "0" ]; then
    report 0 "$crate $target never panics and rejects foreign artifacts"
  else
    report 1 "$crate $target never panics and rejects foreign artifacts (got $code: $(tail -5 "$work.log"))"
  fi
  rm -f "$work.log"
}

run_dirty() {
  local crate="$1" target="$2" regression="$3" needle="$4" label="$5"
  local log
  log="$(mktemp)"
  ( cd "$fixtures/$crate" && cargo +nightly fuzz run "$target" "regression/$regression" ) \
    >"$log" 2>&1
  local code=$?
  if [ "$code" != "0" ]; then
    report 0 "$label exits nonzero"
  else
    report 1 "$label exits nonzero (got $code)"
  fi
  if grep -q "$needle" "$log"; then
    report 0 "$label names the failure"
  else
    report 1 "$label names the failure (got: $(tail -5 "$log"))"
  fi
  rm -f "$log"
}

run_clean "bridge-message-parsers" "airlock"
run_clean "bridge-message-parsers" "oracle_message"

run_dirty "dirty-accepts-foreign" "airlock" "forged-magic-full-envelope" \
  "foreign artifact was accepted" "dirty-accepts-foreign"

run_dirty "dirty-panics" "oracle_message" "declared-length-past-remaining-bytes" \
  "panicked at" "dirty-panics"

if [ "$fail" = "0" ]; then
  echo "fuzz self test passed"
else
  echo "fuzz self test failed"
fi
exit "$fail"
