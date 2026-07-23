//! Deliberately broken fixture proving the fuzz gate fires.
//!
//! This is a copy of the Q-Oracle parser fixture in
//! `fixtures/fuzz/bridge-message-parsers` with one bug planted: the payload
//! is read with a bare slice range built from the attacker supplied length
//! field instead of a checked `get`, so a length that claims more bytes than
//! are actually present panics instead of returning `Err`. It exists only so
//! `scripts/fuzz-selftest.sh` can prove the fuzz gate turns red on a real
//! violation of the never-panic property, the same way
//! `fixtures/symbol-scan/dirty` proves the symbol scan fires. It is not
//! production code and is not the fixture the fuzz workflow runs in a normal
//! pass.

pub const MAX_PAYLOAD_LEN: usize = 1 << 16;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseError {
    TooShort,
    BadMagic,
    UnsupportedVersion,
    PayloadTooLarge,
}

const ORACLE_MAGIC: [u8; 4] = *b"QTOR";
const HEADER_VERSION: u8 = 1;

fn has_oracle_magic(data: &[u8]) -> bool {
    data.get(..ORACLE_MAGIC.len()) == Some(&ORACLE_MAGIC[..])
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OracleMessage<'a> {
    pub sequence: u64,
    pub payload: &'a [u8],
}

pub fn parse_oracle_message(data: &[u8]) -> Result<OracleMessage<'_>, ParseError> {
    if !has_oracle_magic(data) {
        return Err(ParseError::BadMagic);
    }
    let version = *data.get(4).ok_or(ParseError::TooShort)?;
    if version != HEADER_VERSION {
        return Err(ParseError::UnsupportedVersion);
    }
    let seq_bytes: [u8; 8] = data
        .get(5..13)
        .ok_or(ParseError::TooShort)?
        .try_into()
        .map_err(|_| ParseError::TooShort)?;
    let sequence = u64::from_be_bytes(seq_bytes);
    let len_bytes: [u8; 4] = data
        .get(13..17)
        .ok_or(ParseError::TooShort)?
        .try_into()
        .map_err(|_| ParseError::TooShort)?;
    let declared_len = u32::from_be_bytes(len_bytes) as usize;
    if declared_len > MAX_PAYLOAD_LEN {
        return Err(ParseError::PayloadTooLarge);
    }
    // BUG: this should read the payload through a checked `get(17..)` and
    // then compare its length against `declared_len`, the way the real
    // fixture in fixtures/fuzz/bridge-message-parsers does. A bare slice
    // range built from an attacker supplied length instead panics whenever
    // the declared length claims more bytes than the input actually holds.
    let payload = &data[17..17 + declared_len];
    Ok(OracleMessage { sequence, payload })
}
