//! Anchor IDL model types: the primitive type map, argument/instruction
//! shapes, and the whole-document decoder. Field-for-field port of
//! `AnchorIDLDocument.swift`. This is the tier-2 decoder's *model* half —
//! turning raw IDL JSON into typed Rust — with no interpretation logic.

use serde::{Deserialize, Deserializer};
use sha2::{Digest, Sha256};

/// An Anchor IDL argument type. Known primitives get their own case;
/// anything else (defined/vec/array/option shapes, or an unrecognized
/// primitive name) collapses to `Other`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AnchorIdlType {
    Bool,
    U8,
    U16,
    U32,
    U64,
    U128,
    I8,
    I16,
    I32,
    I64,
    I128,
    Pubkey,
    String,
    Bytes,
    Other,
}

impl AnchorIdlType {
    /// Maps a raw IDL `type` field to an `AnchorIdlType`. A JSON string is
    /// looked up in the primitive-name table (unknown name → `Other`); any
    /// other JSON shape (e.g. `{"vec":...}`, `{"defined":...}`) is `Other`.
    pub fn from_type_json(value: &serde_json::Value) -> AnchorIdlType {
        match value.as_str() {
            Some(name) => Self::from_primitive_name(name).unwrap_or(AnchorIdlType::Other),
            None => AnchorIdlType::Other,
        }
    }

    fn from_primitive_name(name: &str) -> Option<AnchorIdlType> {
        match name {
            "bool" => Some(AnchorIdlType::Bool),
            "u8" => Some(AnchorIdlType::U8),
            "u16" => Some(AnchorIdlType::U16),
            "u32" => Some(AnchorIdlType::U32),
            "u64" => Some(AnchorIdlType::U64),
            "u128" => Some(AnchorIdlType::U128),
            "i8" => Some(AnchorIdlType::I8),
            "i16" => Some(AnchorIdlType::I16),
            "i32" => Some(AnchorIdlType::I32),
            "i64" => Some(AnchorIdlType::I64),
            "i128" => Some(AnchorIdlType::I128),
            "pubkey" | "publicKey" => Some(AnchorIdlType::Pubkey),
            "string" => Some(AnchorIdlType::String),
            "bytes" => Some(AnchorIdlType::Bytes),
            _ => None,
        }
    }
}

/// One `{name, type}` entry from an instruction's `args` array.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AnchorIdlArgument {
    pub name: String,
    pub arg_type: AnchorIdlType,
}

/// One instruction from an IDL's `instructions` array, with its
/// discriminator resolved (explicit if present, else the sighash fallback).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AnchorIdlInstruction {
    pub name: String,
    pub discriminator: Vec<u8>,
    pub arguments: Vec<AnchorIdlArgument>,
}

/// A parsed Anchor IDL document: just the name and instruction list, which
/// is all the tier-2 decoder needs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AnchorIdlDocument {
    pub name: String,
    pub instructions: Vec<AnchorIdlInstruction>,
}

#[derive(Deserialize)]
struct RawMetadata {
    name: Option<String>,
}

#[derive(Deserialize)]
struct RawArgument {
    name: String,
    #[serde(rename = "type")]
    arg_type: serde_json::Value,
}

#[derive(Deserialize)]
struct RawInstruction {
    name: String,
    discriminator: Option<Vec<u8>>,
    #[serde(default)]
    args: Vec<RawArgument>,
}

#[derive(Deserialize)]
struct RawDocument {
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    metadata: Option<RawMetadata>,
    #[serde(default)]
    instructions: Vec<RawInstruction>,
}

impl<'de> Deserialize<'de> for AnchorIdlDocument {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let raw = RawDocument::deserialize(deserializer)?;
        let name = raw
            .metadata
            .and_then(|metadata| metadata.name)
            .or(raw.name)
            .unwrap_or_default();

        let instructions = raw
            .instructions
            .into_iter()
            .map(|raw_instruction| AnchorIdlInstruction {
                discriminator: raw_instruction
                    .discriminator
                    .unwrap_or_else(|| sighash(&raw_instruction.name)),
                name: raw_instruction.name,
                arguments: raw_instruction
                    .args
                    .into_iter()
                    .map(|raw_argument| AnchorIdlArgument {
                        name: raw_argument.name,
                        arg_type: AnchorIdlType::from_type_json(&raw_argument.arg_type),
                    })
                    .collect(),
            })
            .collect();

        Ok(AnchorIdlDocument { name, instructions })
    }
}

/// Anchor's legacy discriminator fallback for IDLs that omit an explicit
/// one: the first 8 bytes of `sha256("global:<snake_cased_name>")`.
fn sighash(name: &str) -> Vec<u8> {
    let preimage = format!("global:{}", snake_cased(name));
    let digest = Sha256::digest(preimage.as_bytes());
    digest[..8].to_vec()
}

/// Converts a camelCase (or already snake_case) identifier to snake_case:
/// each uppercase character is lowercased and preceded by an underscore
/// (unless it's the first character).
fn snake_cased(name: &str) -> String {
    let mut result = String::new();
    for character in name.chars() {
        if character.is_uppercase() {
            if !result.is_empty() {
                result.push('_');
            }
            result.extend(character.to_lowercase());
        } else {
            result.push(character);
        }
    }
    result
}

/// An Anchor IDL document paired with where it came from, ready for
/// instruction interpretation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolvedProgramIdl {
    pub document: AnchorIdlDocument,
    pub provenance: crate::decode::DecodeProvenance,
}

/// Tier-2 decode: matches `instruction`'s raw data against a resolved
/// on-chain Anchor IDL by discriminator and renders its arguments. Field-for-
/// field port of `AnchorIDLInterpreter.interpret` + `renderArguments`. Any
/// mismatch (short data, no matching discriminator) falls through to `None`
/// rather than a partial or misaligned decode.
pub fn interpret_idl(
    instruction: &crate::types::DecodedInstruction,
    resolved: &ResolvedProgramIdl,
    accounts: &[String],
) -> Option<crate::decode::DecodedInstructionDisplay> {
    let bytes = crate::decode::primitives::bytes_from_hex(&instruction.raw_data_hex)?;
    if bytes.len() < 8 {
        return None;
    }

    let discriminator = &bytes[..8];
    let matched = resolved
        .document
        .instructions
        .iter()
        .find(|candidate| candidate.discriminator == discriminator)?;

    let arguments = render_arguments(&matched.arguments, &bytes);
    let label = if resolved.document.name.is_empty() {
        crate::decode::primitives::short_address(&instruction.program)
    } else {
        resolved.document.name.clone()
    };

    Some(crate::decode::DecodedInstructionDisplay {
        program_label: label,
        kind: matched.name.clone(),
        summary: format!("{}({})", matched.name, arguments.join(", ")),
        accounts: accounts.to_vec(),
        data_hex: instruction.raw_data_hex.clone(),
        provenance: Some(resolved.provenance.clone()),
        cross_check: None,
    })
}

/// Renders each argument in order starting at byte offset 8 (past the
/// 8-byte Anchor discriminator): a successfully read value becomes
/// `"name: value"`, a sized-but-unrendered value becomes just `"name"`, and
/// hitting an unknown type or running out of bytes stops the reader and
/// emits the *names only* of that argument and every argument after it —
/// their byte offsets can no longer be trusted.
fn render_arguments(arguments: &[AnchorIdlArgument], bytes: &[u8]) -> Vec<String> {
    use crate::decode::borsh::{BorshArgReader, BorshArgValue};

    let mut reader = BorshArgReader::new(bytes, 8);
    let mut rendered = Vec::with_capacity(arguments.len());

    for (index, argument) in arguments.iter().enumerate() {
        match reader.read(argument.arg_type) {
            BorshArgValue::Rendered(value) => rendered.push(format!("{}: {value}", argument.name)),
            BorshArgValue::Skipped => rendered.push(argument.name.clone()),
            BorshArgValue::Stop => {
                rendered.extend(arguments[index..].iter().map(|a| a.name.clone()));
                return rendered;
            }
        }
    }
    rendered
}

#[cfg(test)]
mod tests {
    use super::*;

    fn doc(json: &str) -> AnchorIdlDocument {
        serde_json::from_str(json).unwrap()
    }

    #[test]
    fn decodes_new_format_with_explicit_discriminator() {
        let d = doc(
            r#"{"address":"whirL","metadata":{"name":"whirlpool","version":"0.3.0"},
          "instructions":[{"name":"swap","discriminator":[248,198,158,145,225,117,135,200],
          "accounts":[],"args":[{"name":"amount","type":"u64"},{"name":"otherAmountThreshold","type":"u64"}]}]}"#,
        );
        assert_eq!(d.name, "whirlpool");
        assert_eq!(d.instructions.len(), 1);
        assert_eq!(d.instructions[0].name, "swap");
        assert_eq!(
            d.instructions[0].discriminator,
            vec![248, 198, 158, 145, 225, 117, 135, 200]
        );
        assert_eq!(
            d.instructions[0]
                .arguments
                .iter()
                .map(|a| a.name.as_str())
                .collect::<Vec<_>>(),
            vec!["amount", "otherAmountThreshold"]
        );
        assert!(
            d.instructions[0]
                .arguments
                .iter()
                .all(|a| a.arg_type == AnchorIdlType::U64)
        );
    }

    #[test]
    fn computes_legacy_discriminator_from_name() {
        let d = doc(
            r#"{"version":"0.1.0","name":"demo","instructions":[{"name":"initialize","accounts":[],"args":[]}]}"#,
        );
        // sha256("global:initialize")[0..8] — Anchor's well-known initialize sighash.
        assert_eq!(
            d.instructions[0].discriminator,
            vec![175, 175, 109, 31, 13, 152, 155, 237]
        );
    }

    #[test]
    fn snake_cases_camel_names_for_sighash() {
        assert_eq!(snake_cased("openPosition"), "open_position");
        assert_eq!(snake_cased("initialize"), "initialize");
        assert_eq!(snake_cased("swap"), "swap");
    }

    #[test]
    fn maps_primitive_and_composite_types() {
        let d = doc(r#"{"name":"demo","instructions":[{"name":"act","args":[
          {"name":"a","type":"u64"},{"name":"b","type":"publicKey"},
          {"name":"c","type":{"vec":"u8"}},{"name":"d","type":{"defined":"Config"}}]}]}"#);
        let types: Vec<_> = d.instructions[0]
            .arguments
            .iter()
            .map(|a| a.arg_type)
            .collect();
        assert_eq!(
            types,
            vec![
                AnchorIdlType::U64,
                AnchorIdlType::Pubkey,
                AnchorIdlType::Other,
                AnchorIdlType::Other
            ]
        );
    }

    #[test]
    fn name_falls_back_to_top_level_then_empty() {
        assert_eq!(doc(r#"{"name":"demo","instructions":[]}"#).name, "demo");
        assert_eq!(doc(r#"{"instructions":[]}"#).name, "");
    }
}

#[cfg(test)]
mod interpreter_tests {
    use super::*;
    use crate::decode::DecodeProvenance;
    use crate::types::DecodedInstruction;

    fn resolved(json: &str, slot: u64) -> ResolvedProgramIdl {
        let document: AnchorIdlDocument = serde_json::from_str(json).unwrap();
        let name = document.name.clone();
        ResolvedProgramIdl {
            document,
            provenance: DecodeProvenance::OnChainIdl {
                idl_name: name,
                hash: "deadbeefcafe".into(),
                slot,
            },
        }
    }

    fn ix(program: &str, hex: &str) -> DecodedInstruction {
        DecodedInstruction {
            program: program.into(),
            kind: "raw".into(),
            summary: String::new(),
            accounts: vec![],
            raw_data_hex: hex.into(),
            config_action: None,
        }
    }

    const SWAP_IDL: &str = r#"{"metadata":{"name":"whirlpool"},"instructions":[
      {"name":"swap","discriminator":[1,2,3,4,5,6,7,8],
       "args":[{"name":"amount","type":"u64"},{"name":"otherAmountThreshold","type":"u64"}]}]}"#;

    #[test]
    fn decodes_matching_instruction_with_args() {
        let d = interpret_idl(
            &ix("whirL", "010203040506070840420f0000000000f07e0e0000000000"),
            &resolved(SWAP_IDL, 100),
            &["a".into(), "b".into()],
        )
        .unwrap();
        assert_eq!(d.program_label, "whirlpool");
        assert_eq!(d.kind, "swap");
        assert_eq!(
            d.summary,
            "swap(amount: 1000000, otherAmountThreshold: 950000)"
        );
        assert_eq!(d.accounts, vec!["a".to_string(), "b".to_string()]);
        assert_eq!(
            d.provenance,
            Some(DecodeProvenance::OnChainIdl {
                idl_name: "whirlpool".into(),
                hash: "deadbeefcafe".into(),
                slot: 100
            })
        );
    }

    #[test]
    fn returns_none_when_no_discriminator_matches() {
        assert!(
            interpret_idl(
                &ix("whirL", "aaaaaaaaaaaaaaaa40420f0000000000"),
                &resolved(SWAP_IDL, 100),
                &[]
            )
            .is_none()
        );
    }

    #[test]
    fn returns_none_when_data_too_short() {
        assert!(interpret_idl(&ix("x", "0102"), &resolved(SWAP_IDL, 100), &[]).is_none());
    }

    #[test]
    fn renders_names_only_after_unknown_arg_type() {
        let idl = r#"{"name":"demo","instructions":[{"name":"act","discriminator":[9,9,9,9,9,9,9,9],
          "args":[{"name":"flag","type":"u8"},{"name":"config","type":{"defined":"Config"}},{"name":"tail","type":"u64"}]}]}"#;
        let d =
            interpret_idl(&ix("x", "090909090909090901ffff"), &resolved(idl, 100), &[]).unwrap();
        assert_eq!(d.summary, "act(flag: 1, config, tail)");
    }
}
