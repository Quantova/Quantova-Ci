//! Deliberately broken fixture proving the fuzz gate fires.
//!
//! This is a copy of the Airlock parser fixture in
//! `fixtures/fuzz/bridge-message-parsers` with one bug planted: the magic
//! check only looks at the first byte instead of the full four byte header,
//! so it wrongly treats some foreign artifacts as native. It exists only so
//! `scripts/fuzz-selftest.sh` can prove the fuzz gate turns red on a real
//! violation of the reject-foreign-artifacts property, the same way
//! `fixtures/symbol-scan/dirty` proves the symbol scan fires. It is not
//! production code and is not the fixture the fuzz workflow runs in a normal
//! pass.

pub const MAX_PAYLOAD_LEN: usize = 1 << 16;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseError {
    TooShort,
    UnsupportedVersion,
    PayloadTooLarge,
    LengthMismatch,
}

const HEADER_VERSION: u8 = 1;

/// BUG: this should compare the full four byte magic `QTAL`, but compares
/// only the first byte, so it wrongly accepts a foreign artifact that merely
/// starts with `Q`.
fn has_airlock_magic(data: &[u8]) -> bool {
    data.first() == Some(&b'Q')
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AirlockMessage<'a> {
    pub corridor: u8,
    pub payload: &'a [u8],
}

pub fn parse_airlock_message(data: &[u8]) -> Result<AirlockMessage<'_>, ParseError> {
    if !has_airlock_magic(data) {
        return Err(ParseError::TooShort);
    }
    let version = *data.get(4).ok_or(ParseError::TooShort)?;
    if version != HEADER_VERSION {
        return Err(ParseError::UnsupportedVersion);
    }
    let corridor = *data.get(5).ok_or(ParseError::TooShort)?;
    let len_bytes: [u8; 4] = data
        .get(6..10)
        .ok_or(ParseError::TooShort)?
        .try_into()
        .map_err(|_| ParseError::TooShort)?;
    let declared_len = u32::from_be_bytes(len_bytes) as usize;
    if declared_len > MAX_PAYLOAD_LEN {
        return Err(ParseError::PayloadTooLarge);
    }
    let payload = data.get(10..).ok_or(ParseError::TooShort)?;
    if payload.len() != declared_len {
        return Err(ParseError::LengthMismatch);
    }
    Ok(AirlockMessage { corridor, payload })
}
