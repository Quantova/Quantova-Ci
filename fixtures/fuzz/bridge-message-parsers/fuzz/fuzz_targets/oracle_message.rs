#![no_main]

use bridge_message_parsers::parse_oracle_message;
use libfuzzer_sys::fuzz_target;

const ORACLE_MAGIC: &[u8; 4] = b"QTOR";

// Proves the fuzz gate on the fixture Q-Oracle message parser. The parser
// must never panic on any input, and a foreign artifact, one that does not
// open with the Quantova Q-Oracle header, must always be rejected rather
// than accepted. The magic check here is a plain byte comparison independent
// of the parser's own gate, so a bug in that gate cannot hide from this
// oracle by agreeing with itself.
fuzz_target!(|data: &[u8]| {
    let result = parse_oracle_message(data);
    let is_native = data.get(..ORACLE_MAGIC.len()) == Some(&ORACLE_MAGIC[..]);
    if !is_native {
        assert!(result.is_err(), "foreign artifact was accepted: {data:?}");
    }
});
