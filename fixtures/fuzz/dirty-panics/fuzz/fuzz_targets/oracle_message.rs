#![no_main]
// Copyright 2026 Quantova Inc
// SPDX-License-Identifier: Apache-2.0 OR MIT


use dirty_panics::parse_oracle_message;
use libfuzzer_sys::fuzz_target;

const ORACLE_MAGIC: &[u8; 4] = b"QTOR";

fuzz_target!(|data: &[u8]| {
    let result = parse_oracle_message(data);
    let is_native = data.get(..ORACLE_MAGIC.len()) == Some(&ORACLE_MAGIC[..]);
    if !is_native {
        assert!(result.is_err(), "foreign artifact was accepted: {data:?}");
    }
});
