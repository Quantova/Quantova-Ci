// Copyright 2026 Quantova Inc
// SPDX-License-Identifier: Apache-2.0 OR MIT

pub const MAX_PAYLOAD_LEN: usize = 1 << 16;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseError {
    TooShort,
    UnsupportedVersion,
    PayloadTooLarge,
    LengthMismatch,
}

const HEADER_VERSION: u8 = 1;

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
