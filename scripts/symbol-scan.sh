#!/usr/bin/env bash
# Copyright 2026 Quantova Inc
# SPDX-License-Identifier: Apache-2.0 OR MIT

set -euo pipefail

dir="${1:-target/release}"
patterns='secp256k1|curve25519|ristretto|ed25519|ecdsa|bls12|bn254|EC_POINT|BN_mod_exp|RSA_'
fail=0

while IFS= read -r bin; do
  if strings "$bin" | grep -Eiq "$patterns"; then
    echo "classical-crypto symbol signature detected in $bin" >&2
    fail=1
  fi
done < <(find "$dir" -maxdepth 1 -type f -perm -u+x 2>/dev/null)

exit "$fail"
