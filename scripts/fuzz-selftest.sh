#!/usr/bin/env bash
# Self test for the fuzz gate.
#
# Three fixtures under fixtures/fuzz prove the two properties every fuzz
# target the fuzz workflow runs is held to:
#   bridge-message-parsers  a correct Airlock parser and a correct Q-Oracle
#                            message parser, neither panics and both reject
#                            every foreign artifact, the fuzz run exits zero;
#   dirty-accepts-foreign   the Airlock parser with its magic check weakened
#                            to a single byte, so it wrongly accepts a
#                            foreign artifact, the fuzz run exits nonzero;
#   dirty-panics             the Q-Oracle parser with its payload read
#                            through a bare slice range instead of a checked
#                            one, so an oversized declared length panics
#                            instead of returning Err, the fuzz run exits
#                            nonzero.
# The two dirty fixtures each carry one committed regression input under
# their regression/ directory, crafted to reach the planted bug on the first
# execution, so proving the gate fires never depends on a mutation search
# finding it by luck.
#
# Requires a nightly toolchain named `nightly` and cargo-fuzz on PATH. The
# fuzz workflow installs both before this script runs.
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
