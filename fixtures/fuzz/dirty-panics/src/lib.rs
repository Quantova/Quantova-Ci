// Copyright 2026 Quantova Inc
// SPDX-License-Identifier: Apache-2.0 OR MIT

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
    let payload = &data[17..17 + declared_len];
    Ok(OracleMessage { sequence, payload })
}
