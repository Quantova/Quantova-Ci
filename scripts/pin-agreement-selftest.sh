#!/usr/bin/env bash
# Copyright 2026 Quantova Inc
# SPDX-License-Identifier: Apache-2.0 OR MIT

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
checker="$here/pin-agreement.sh"
fixtures="$root/fixtures/pin-agreement"

fail=0

report() {
  if [ "$1" = "0" ]; then
    echo "ok   $2"
  else
    echo "FAIL $2"
    fail=1
  fi
}

out="$(QTOV_PIN_PEEL_FIXTURE="$fixtures/agree/peel-fixture" "$checker" "$fixtures/agree" 2>&1)"
code=$?
if [ "$code" = "0" ]; then report 0 "agree exits zero"; else report 1 "agree exits zero (got $code: $out)"; fi

out="$(QTOV_PIN_PEEL_FIXTURE="$fixtures/moved-tag/peel-fixture" "$checker" "$fixtures/moved-tag" 2>&1)"
code=$?
if [ "$code" != "0" ]; then report 0 "moved-tag exits nonzero"; else report 1 "moved-tag exits nonzero (got $code)"; fi
case "$out" in
  *QRC-CONSENSUS*) report 0 "moved-tag names the dependency" ;;
  *) report 1 "moved-tag names the dependency (got: $out)" ;;
esac

out="$(QTOV_PIN_PEEL_FIXTURE="$fixtures/regenerated-lock/peel-fixture" "$checker" "$fixtures/regenerated-lock" 2>&1)"
code=$?
if [ "$code" != "0" ]; then report 0 "regenerated-lock exits nonzero"; else report 1 "regenerated-lock exits nonzero (got $code)"; fi
case "$out" in
  *q-prover*) report 0 "regenerated-lock names the dependency" ;;
  *) report 1 "regenerated-lock names the dependency (got: $out)" ;;
esac

out="$("$checker" "$fixtures/no-pins" 2>&1)"
code=$?
if [ "$code" != "0" ]; then report 0 "no-pins fails closed"; else report 1 "no-pins fails closed (got $code)"; fi
case "$out" in
  *cross-repo-pins*) report 0 "no-pins names the missing declaration" ;;
  *) report 1 "no-pins names the missing declaration (got: $out)" ;;
esac

if [ "$fail" = "0" ]; then
  echo "pin-agreement self test passed"
else
  echo "pin-agreement self test failed"
fi
exit "$fail"
