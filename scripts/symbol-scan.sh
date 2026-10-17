#!/usr/bin/env bash
# Copyright 2026 Quantova Inc
# SPDX-License-Identifier: Apache-2.0 OR MIT

set -euo pipefail

bash -s -- "${1:-target/release}" <<'SH'
set -euo pipefail
dir="$1"
patterns='secp256k1|curve25519|ristretto|ed25519|ecdsa|bls12|bn254|EC_POINT|BN_mod_exp|RSA_'
fail=0
count=0
while IFS= read -r -d '' artifact; do
  count=$((count + 1))
  if strings -a "$artifact" | grep -Eiq "$patterns"; then
    echo "::error file=$artifact::classical-crypto symbol signature detected in $artifact" >&2
    fail=1
  fi
done < <(
  find "$dir" -maxdepth 1 -type f \( -perm -u+x -o -name 'lib*.rlib' -o -name '*.so' -o -name '*.dylib' -o -name '*.a' -o -name '*.wasm' \) -print0 2>/dev/null
  find "$(dirname "$dir")" -mindepth 3 -maxdepth 3 -type f -path "$(dirname "$dir")/*/release/*.wasm" -print0 2>/dev/null
)
if [ "$count" = "0" ]; then
  echo "::error::no release artifact found in $dir, nothing was scanned" >&2
  exit 1
fi
echo "scanned $count release artifacts in $dir"
exit "$fail"
SH
