#![no_main]

use dirty_accepts_foreign::parse_airlock_message;
use libfuzzer_sys::fuzz_target;

const AIRLOCK_MAGIC: &[u8; 4] = b"QTAL";

// Same oracle as fixtures/fuzz/bridge-message-parsers/fuzz/fuzz_targets/airlock.rs,
// run against the deliberately broken parser. It must fail on the committed
// regression input, proving the gate catches a parser that wrongly accepts a
// foreign artifact.
fuzz_target!(|data: &[u8]| {
    let result = parse_airlock_message(data);
    let is_native = data.get(..AIRLOCK_MAGIC.len()) == Some(&AIRLOCK_MAGIC[..]);
    if !is_native {
        assert!(result.is_err(), "foreign artifact was accepted: {data:?}");
    }
});
