//! A pure, positional Borsh reader for on-device instruction argument
//! decoding. Field-for-field port of `BorshArgumentReader.swift` +
//! `DecodedArgValue.swift`. Deliberately hand-written rather than built on
//! the `borsh` crate: it needs to render integer/bool primitives, size-and-skip
//! pubkey/string/bytes/128-bit values it can locate but not usefully render,
//! and stop cleanly at the first unknown type or exhausted buffer — after
//! either, the byte alignment for later arguments is lost.
//!
//! This reader parses attacker-influenceable instruction bytes for a signing
//! app, so every read is bounds-checked (`take` never slices past the end of
//! the buffer) and no path can index-panic, regardless of offset or input
//! length.

use std::collections::HashMap;

use crate::decode::idl::AnchorIdlType;

/// The outcome of reading one field with [`BorshArgReader::read`]: either a
/// human-rendered string, a value that was sized and skipped but has no
/// useful rendering, or a signal that reading stopped (unknown type or
/// exhausted buffer).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BorshArgValue {
    Rendered(String),
    Skipped,
    Stop,
}

/// A decoded argument value, typed by width rather than rendered to a
/// string. `Unrendered` covers types that were sized and skipped (pubkey,
/// u128/i128, string, bytes) because they aren't usefully displayed as a
/// bare scalar.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecodedArgValue {
    Uint(u64),
    Int(i64),
    Bool(bool),
    Unrendered,
}

impl DecodedArgValue {
    pub fn rendered(&self) -> Option<String> {
        match self {
            DecodedArgValue::Uint(value) => Some(value.to_string()),
            DecodedArgValue::Int(value) => Some(value.to_string()),
            DecodedArgValue::Bool(value) => Some(if *value { "true" } else { "false" }.into()),
            DecodedArgValue::Unrendered => None,
        }
    }
}

/// Positional cursor over a byte buffer, advancing by the exact width of
/// each Borsh-encoded field it reads.
pub struct BorshArgReader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> BorshArgReader<'a> {
    pub fn new(bytes: &'a [u8], offset: usize) -> Self {
        Self { bytes, offset }
    }

    /// Bounds-checked slice-and-advance: returns `None` (without mutating
    /// `offset`) rather than panicking when `count` would run past the end
    /// of the buffer, at any starting offset.
    fn take(&mut self, count: usize) -> Option<&'a [u8]> {
        let end = self.offset.checked_add(count)?;
        if end > self.bytes.len() {
            return None;
        }
        let slice = &self.bytes[self.offset..end];
        self.offset = end;
        Some(slice)
    }

    fn read_length(&mut self) -> Option<usize> {
        let b = self.take(4)?;
        let mut v: u32 = 0;
        for (i, byte) in b.iter().enumerate() {
            v |= (*byte as u32) << (i * 8);
        }
        Some(v as usize)
    }

    fn unsigned_raw(&mut self, count: usize) -> Option<u64> {
        let b = self.take(count)?;
        let mut v: u64 = 0;
        for (i, byte) in b.iter().enumerate() {
            v |= (*byte as u64) << (i * 8);
        }
        Some(v)
    }

    fn signed_raw(&mut self, count: usize) -> Option<i64> {
        let b = self.take(count)?;
        let mut magnitude: u64 = 0;
        for (i, byte) in b.iter().enumerate() {
            magnitude |= (*byte as u64) << (i * 8);
        }
        let sign_bit: u64 = 1 << (count * 8 - 1);
        if magnitude & sign_bit != 0 {
            let mask = if count == 8 {
                u64::MAX
            } else {
                (1u64 << (count * 8)) - 1
            };
            Some((magnitude | !mask) as i64)
        } else {
            Some(magnitude as i64)
        }
    }

    fn unsigned_bytes(ty: AnchorIdlType) -> usize {
        match ty {
            AnchorIdlType::U8 => 1,
            AnchorIdlType::U16 => 2,
            AnchorIdlType::U32 => 4,
            AnchorIdlType::U64 => 8,
            _ => 0,
        }
    }

    fn signed_bytes(ty: AnchorIdlType) -> usize {
        match ty {
            AnchorIdlType::I8 => 1,
            AnchorIdlType::I16 => 2,
            AnchorIdlType::I32 => 4,
            AnchorIdlType::I64 => 8,
            _ => 0,
        }
    }

    pub fn read(&mut self, ty: AnchorIdlType) -> BorshArgValue {
        match self.read_value(ty) {
            None => BorshArgValue::Stop,
            Some(value) => value
                .rendered()
                .map(BorshArgValue::Rendered)
                .unwrap_or(BorshArgValue::Skipped),
        }
    }

    pub fn read_value(&mut self, ty: AnchorIdlType) -> Option<DecodedArgValue> {
        use AnchorIdlType as T;
        match ty {
            T::Bool => self
                .take(1)
                .and_then(|s| s.first().copied())
                .map(|b| DecodedArgValue::Bool(b != 0)),
            T::U8 | T::U16 | T::U32 | T::U64 => self
                .unsigned_raw(Self::unsigned_bytes(ty))
                .map(DecodedArgValue::Uint),
            T::I8 | T::I16 | T::I32 | T::I64 => self
                .signed_raw(Self::signed_bytes(ty))
                .map(DecodedArgValue::Int),
            T::U128 | T::I128 => self.take(16).map(|_| DecodedArgValue::Unrendered),
            T::Pubkey => self.take(32).map(|_| DecodedArgValue::Unrendered),
            T::String | T::Bytes => {
                let len = self.read_length()?;
                self.take(len).map(|_| DecodedArgValue::Unrendered)
            }
            T::Other => None,
        }
    }
}

/// Decodes named Borsh arguments positionally, stopping at the first field
/// that cannot be sized (so later fields are absent rather than
/// misaligned).
pub fn decode_arguments(
    bytes: &[u8],
    offset: usize,
    fields: &[(String, AnchorIdlType)],
) -> HashMap<String, DecodedArgValue> {
    let mut reader = BorshArgReader::new(bytes, offset);
    let mut result = HashMap::new();
    for (name, ty) in fields {
        let Some(value) = reader.read_value(*ty) else {
            break;
        };
        result.insert(name.clone(), value);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::decode::idl::AnchorIdlType::String as Str;
    use crate::decode::idl::AnchorIdlType::*;
    use crate::decode::primitives::bytes_from_hex;

    #[test]
    fn reads_unsigned_integer() {
        let mut r = BorshArgReader::new(&[136, 19, 0, 0, 0, 0, 0, 0], 0);
        assert_eq!(r.read(U64), BorshArgValue::Rendered("5000".into()));
    }

    #[test]
    fn reads_signed_negative_integer() {
        let mut r = BorshArgReader::new(&[255, 255, 255, 255], 0);
        assert_eq!(r.read(I32), BorshArgValue::Rendered("-1".into()));
    }

    #[test]
    fn reads_bool() {
        let mut r = BorshArgReader::new(&[1], 0);
        assert_eq!(r.read(Bool), BorshArgValue::Rendered("true".into()));
    }

    #[test]
    fn reads_bool_at_non_zero_offset() {
        // The fixed-bug guard: bool after a consumed u8 must read byte 1, not crash.
        let mut r = BorshArgReader::new(&[7, 1], 0);
        assert_eq!(r.read(U8), BorshArgValue::Rendered("7".into()));
        assert_eq!(r.read(Bool), BorshArgValue::Rendered("true".into()));
    }

    #[test]
    fn skips_pubkey_and_advances() {
        let mut r = BorshArgReader::new(&[7u8; 40], 0);
        assert_eq!(r.read(Pubkey), BorshArgValue::Skipped);
        assert_eq!(
            r.read(U64),
            BorshArgValue::Rendered("506381209866536711".into())
        );
    }

    #[test]
    fn skips_string_via_length_prefix() {
        let mut r = BorshArgReader::new(&[2, 0, 0, 0, 65, 66, 9], 0);
        assert_eq!(r.read(Str), BorshArgValue::Skipped);
        assert_eq!(r.read(U8), BorshArgValue::Rendered("9".into()));
    }

    #[test]
    fn stops_on_other_and_when_exhausted() {
        assert_eq!(
            BorshArgReader::new(&[1, 2, 3, 4], 0).read(Other),
            BorshArgValue::Stop
        );
        assert_eq!(
            BorshArgReader::new(&[1, 2], 0).read(U64),
            BorshArgValue::Stop
        );
    }

    #[test]
    fn read_value_typed_and_unrendered() {
        let mut r = BorshArgReader::new(&[136, 19, 0, 0, 0, 0, 0, 0, 1], 0);
        assert_eq!(r.read_value(U64), Some(DecodedArgValue::Uint(5000)));
        assert_eq!(r.read_value(Bool), Some(DecodedArgValue::Bool(true)));

        let mut buf = vec![7u8; 32];
        buf.extend_from_slice(&[2, 0, 0, 0, 65, 66, 9]);
        let mut r2 = BorshArgReader::new(&buf, 0);
        assert_eq!(r2.read_value(Pubkey), Some(DecodedArgValue::Unrendered));
        assert_eq!(r2.read_value(Str), Some(DecodedArgValue::Unrendered));
        assert_eq!(r2.read_value(U8), Some(DecodedArgValue::Uint(9)));

        assert_eq!(
            BorshArgReader::new(&[1, 2, 3, 4], 0).read_value(Other),
            None
        );
    }

    #[test]
    fn decode_arguments_builds_named_map_and_stops_at_unknown() {
        let bytes = bytes_from_hex("40420f0000000000010100000000000000").unwrap();
        let args = decode_arguments(
            &bytes,
            0,
            &[
                ("amount".into(), U64),
                ("aToB".into(), Bool),
                ("tail".into(), U64),
            ],
        );
        assert_eq!(args["amount"], DecodedArgValue::Uint(1_000_000));
        assert_eq!(args["aToB"], DecodedArgValue::Bool(true));
        assert_eq!(args["tail"], DecodedArgValue::Uint(1));

        let args2 = decode_arguments(
            &[1],
            0,
            &[
                ("flag".into(), U8),
                ("blob".into(), Other),
                ("tail".into(), U8),
            ],
        );
        assert_eq!(args2["flag"], DecodedArgValue::Uint(1));
        assert!(!args2.contains_key("blob"));
        assert!(!args2.contains_key("tail"));
    }

    #[test]
    fn rendered_matches_swift_decoded_arg_value_rendered() {
        assert_eq!(DecodedArgValue::Uint(5000).rendered(), Some("5000".into()));
        assert_eq!(DecodedArgValue::Int(-1).rendered(), Some("-1".into()));
        assert_eq!(DecodedArgValue::Bool(true).rendered(), Some("true".into()));
        assert_eq!(
            DecodedArgValue::Bool(false).rendered(),
            Some("false".into())
        );
        assert_eq!(DecodedArgValue::Unrendered.rendered(), None);
    }
}
