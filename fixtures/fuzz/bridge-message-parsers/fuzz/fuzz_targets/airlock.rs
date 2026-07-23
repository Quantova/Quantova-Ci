#![no_main]

use bridge_message_parsers::parse_airlock_message;
use libfuzzer_sys::fuzz_target;

const AIRLOCK_MAGIC: &[u8; 4] = b"QTAL";

// Proves the fuzz gate on the fixture Airlock parser. The parser must never
// panic on any input, and a foreign artifact, one that does not open with the
// Quantova Airlock header, must always be rejected rather than accepted. The
// magic check here is a plain byte comparison independent of the parser's own
// gate, so a bug in that gate cannot hide from this oracle by agreeing with
// itself.
fuzz_target!(|data: &[u8]| {
    let result = parse_airlock_message(data);
    let is_native = data.get(..AIRLOCK_MAGIC.len()) == Some(&AIRLOCK_MAGIC[..]);
    if !is_native {
        assert!(result.is_err(), "foreign artifact was accepted: {data:?}");
    }
});
