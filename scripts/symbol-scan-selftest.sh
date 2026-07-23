#!/usr/bin/env bash
# Self test for the classical-crypto symbol scan.
#
# Two fixtures under fixtures/symbol-scan, each a directory holding one executable:
#   clean   carries only post quantum symbols, the scan exits zero;
#   dirty   carries a classical curve symbol, the scan exits nonzero naming the file.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
scan="$here/symbol-scan.sh"
fixtures="$root/fixtures/symbol-scan"

fail=0

report() {
  if [ "$1" = "0" ]; then
    echo "ok   $2"
  else
    echo "FAIL $2"
    fail=1
  fi
}

out="$("$scan" "$fixtures/clean" 2>&1)"
code=$?
if [ "$code" = "0" ]; then report 0 "clean exits zero"; else report 1 "clean exits zero (got $code: $out)"; fi

out="$("$scan" "$fixtures/dirty" 2>&1)"
code=$?
if [ "$code" != "0" ]; then report 0 "dirty exits nonzero"; else report 1 "dirty exits nonzero (got $code)"; fi
case "$out" in
  *qtool*) report 0 "dirty names the file" ;;
  *) report 1 "dirty names the file (got: $out)" ;;
esac

if [ "$fail" = "0" ]; then
  echo "symbol scan self test passed"
else
  echo "symbol scan self test failed"
fi
exit "$fail"
