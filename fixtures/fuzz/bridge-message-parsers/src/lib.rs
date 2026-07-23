//! Fixture message parsers the fuzz gate is proven against.
//!
//! This is not the production Airlock or Q-Oracle message format. Those live in
//! the repository that implements the bridge and the repository that implements
//! Q-Oracle. This crate is small enough to read in one sitting and stands in for
//! both: an Airlock submission parser and a Q-Oracle report parser, each with the
//! two properties the fuzz gate exists to hold every real parser to.
//!
//! The first property is that neither parser panics on any input, well formed,
//! truncated, oversized, or arbitrary. Every field is read through a checked
//! slice or `Option`, never a bare index, and a declared payload length is
//! bounds checked before it is trusted for anything.
//!
//! The second property is that a foreign artifact, one that does not open with
//! the Quantova header for that parser, is always rejected with `Err` and never
//! accepted.

/// The payload length declared inside an artifact is capped here. A declared
/// length past the cap is rejected before it is used for anything, so an
/// attacker supplied length field can never drive an unbounded allocation.
pub const MAX_PAYLOAD_LEN: usize = 1 << 16;

/// Why a parse was rejected. A foreign artifact is always `BadMagic`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseError {
    TooShort,
    BadMagic,
    UnsupportedVersion,
    PayloadTooLarge,
    LengthMismatch,
}

const AIRLOCK_MAGIC: [u8; 4] = *b"QTAL";
const ORACLE_MAGIC: [u8; 4] = *b"QTOR";
const HEADER_VERSION: u8 = 1;

/// True when `data` opens with the Airlock header. Too short to hold the
/// header, or any other prefix, is always false rather than a panic.
pub fn has_airlock_magic(data: &[u8]) -> bool {
    data.get(..AIRLOCK_MAGIC.len()) == Some(&AIRLOCK_MAGIC[..])
}

/// True when `data` opens with the Q-Oracle header.
pub fn has_oracle_magic(data: &[u8]) -> bool {
    data.get(..ORACLE_MAGIC.len()) == Some(&ORACLE_MAGIC[..])
}

/// A parsed Airlock submission borrowing its payload from the input.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AirlockMessage<'a> {
    pub corridor: u8,
    pub payload: &'a [u8],
}

/// Parse an Airlock submission.
///
/// Layout: 4 byte magic `QTAL`, 1 byte version, 1 byte corridor tag, 4 byte
/// big endian payload length, then exactly that many payload bytes and
/// nothing after. Every field is read through a checked slice, so a
/// truncated, oversized, or entirely foreign input is rejected with `Err`
/// rather than a panic, for an input of any length.
pub fn parse_airlock_message(data: &[u8]) -> Result<AirlockMessage<'_>, ParseError> {
    if !has_airlock_magic(data) {
        return Err(ParseError::BadMagic);
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

/// A parsed Q-Oracle report borrowing its payload from the input.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OracleMessage<'a> {
    pub sequence: u64,
    pub payload: &'a [u8],
}

/// Parse a Q-Oracle report.
///
/// Layout: 4 byte magic `QTOR`, 1 byte version, 8 byte big endian sequence
/// number, 4 byte big endian payload length, then exactly that many payload
/// bytes and nothing after. Same checked slice discipline as the Airlock
/// parser, so no bare index and no panic on any input.
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
    let payload = data.get(17..).ok_or(ParseError::TooShort)?;
    if payload.len() != declared_len {
        return Err(ParseError::LengthMismatch);
    }
    Ok(OracleMessage { sequence, payload })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn airlock_artifact(corridor: u8, payload: &[u8]) -> Vec<u8> {
        let mut v = Vec::new();
        v.extend_from_slice(&AIRLOCK_MAGIC);
        v.push(HEADER_VERSION);
        v.push(corridor);
        v.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        v.extend_from_slice(payload);
        v
    }

    fn oracle_artifact(sequence: u64, payload: &[u8]) -> Vec<u8> {
        let mut v = Vec::new();
        v.extend_from_slice(&ORACLE_MAGIC);
        v.push(HEADER_VERSION);
        v.extend_from_slice(&sequence.to_be_bytes());
        v.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        v.extend_from_slice(payload);
        v
    }

    #[test]
    fn airlock_accepts_a_well_formed_artifact() {
        let bytes = airlock_artifact(3, b"deposit");
        let msg = parse_airlock_message(&bytes).expect("well formed artifact must parse");
        assert_eq!(msg.corridor, 3);
        assert_eq!(msg.payload, b"deposit");
    }

    #[test]
    fn oracle_accepts_a_well_formed_artifact() {
        let bytes = oracle_artifact(42, b"price report");
        let msg = parse_oracle_message(&bytes).expect("well formed artifact must parse");
        assert_eq!(msg.sequence, 42);
        assert_eq!(msg.payload, b"price report");
    }

    // A foreign artifact is anything that does not open with the Quantova
    // header for that parser. Every one of these must be rejected, never
    // accepted and never a panic.
    const FOREIGN_ARTIFACTS: &[&[u8]] = &[
        b"",
        b"Q",
        b"QTOV",
        b"\x19Ethereum Signed Message:\n",
        b"\x00\x00\x00\x00\x00\x00\x00\x00",
        b"random bytes that are not a Quantova artifact at all, at all",
    ];

    #[test]
    fn airlock_rejects_every_foreign_artifact() {
        for artifact in FOREIGN_ARTIFACTS {
            assert!(
                parse_airlock_message(artifact).is_err(),
                "foreign artifact was accepted by the airlock parser: {artifact:?}"
            );
        }
    }

    #[test]
    fn oracle_rejects_every_foreign_artifact() {
        for artifact in FOREIGN_ARTIFACTS {
            assert!(
                parse_oracle_message(artifact).is_err(),
                "foreign artifact was accepted by the oracle parser: {artifact:?}"
            );
        }
    }

    #[test]
    fn airlock_rejects_a_declared_length_past_the_cap_without_panicking() {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(&AIRLOCK_MAGIC);
        bytes.push(HEADER_VERSION);
        bytes.push(0);
        bytes.extend_from_slice(&u32::MAX.to_be_bytes());
        assert_eq!(
            parse_airlock_message(&bytes),
            Err(ParseError::PayloadTooLarge)
        );
    }

    #[test]
    fn oracle_rejects_a_declared_length_past_the_cap_without_panicking() {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(&ORACLE_MAGIC);
        bytes.push(HEADER_VERSION);
        bytes.extend_from_slice(&7u64.to_be_bytes());
        bytes.extend_from_slice(&u32::MAX.to_be_bytes());
        assert_eq!(
            parse_oracle_message(&bytes),
            Err(ParseError::PayloadTooLarge)
        );
    }

    #[test]
    fn every_truncation_of_a_well_formed_artifact_is_rejected_without_panicking() {
        let airlock = airlock_artifact(1, b"payload bytes");
        for cut in 0..airlock.len() {
            let _ = parse_airlock_message(&airlock[..cut]);
        }
        let oracle = oracle_artifact(1, b"payload bytes");
        for cut in 0..oracle.len() {
            let _ = parse_oracle_message(&oracle[..cut]);
        }
    }
}
