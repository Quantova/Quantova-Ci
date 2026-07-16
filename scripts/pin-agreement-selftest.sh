#!/usr/bin/env bash
# Self test for the cross repo pin agreement check.
#
# Three fixtures under fixtures/pin-agreement, each a declaration, a lockfile, and a
# stubbed remote peel, prove the three way agreement:
#   agree             all three match, the check exits zero;
#   moved-tag         the peeled tag commit differs from the lockfile commit, the
#                     check exits nonzero naming the dependency;
#   regenerated-lock  the lockfile commit differs from the declared tag commit, the
#                     check exits nonzero naming the dependency.
# The peel is stubbed from each fixture's peel-fixture file, so the self test is
# hermetic and deterministic and never reaches a remote. The real run peels the live
# remote with git ls-remote.
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

# agree: every fact matches, the check must exit zero.
out="$(QTOV_PIN_PEEL_FIXTURE="$fixtures/agree/peel-fixture" "$checker" "$fixtures/agree" 2>&1)"
code=$?
if [ "$code" = "0" ]; then report 0 "agree exits zero"; else report 1 "agree exits zero (got $code: $out)"; fi

# moved-tag: the peeled tag commit differs from the lockfile commit, the check must
# exit nonzero and name the moved dependency.
out="$(QTOV_PIN_PEEL_FIXTURE="$fixtures/moved-tag/peel-fixture" "$checker" "$fixtures/moved-tag" 2>&1)"
code=$?
if [ "$code" != "0" ]; then report 0 "moved-tag exits nonzero"; else report 1 "moved-tag exits nonzero (got $code)"; fi
case "$out" in
  *QRC-CONSENSUS*) report 0 "moved-tag names the dependency" ;;
  *) report 1 "moved-tag names the dependency (got: $out)" ;;
esac

# regenerated-lock: the lockfile commit differs from the declared tag commit, the
# check must exit nonzero and name the drifted dependency.
out="$(QTOV_PIN_PEEL_FIXTURE="$fixtures/regenerated-lock/peel-fixture" "$checker" "$fixtures/regenerated-lock" 2>&1)"
code=$?
if [ "$code" != "0" ]; then report 0 "regenerated-lock exits nonzero"; else report 1 "regenerated-lock exits nonzero (got $code)"; fi
case "$out" in
  *q-prover*) report 0 "regenerated-lock names the dependency" ;;
  *) report 1 "regenerated-lock names the dependency (got: $out)" ;;
esac

if [ "$fail" = "0" ]; then
  echo "pin-agreement self test passed"
else
  echo "pin-agreement self test failed"
fi
exit "$fail"
