//! Instruction-decode output types: what a decoded instruction looks like
//! once the borsh/IDL/spec/cross-check stack (later modules in this tree)
//! has finished interpreting it. Field-for-field port of
//! `DecodedInstructionDisplay` / `DecodeProvenance` / `CrossCheckVerdict`
//! from `InstructionDecoder.swift`.

pub mod borsh;
pub mod crosscheck;
pub mod fetch;
pub mod idl;
pub mod manifest;
pub mod mints;
pub mod primitives;
pub mod registry;
pub mod spec;
pub mod wire;

#[cfg(test)]
mod golden_tests;

use std::collections::{HashMap, HashSet};

use idl::ResolvedProgramIdl;
use spec::{DecodeSpec, MintInfo};

use crate::decode::mints::ResolvedMint;
use crate::decode::wire::AssetMovement;
use crate::types::DecodedInstruction;

pub use crosscheck::CrossCheckContext;

/// Where a decoded instruction's interpretation came from: a resolved
/// on-chain Anchor IDL, or the bundled decode-spec registry.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DecodeProvenance {
    OnChainIdl {
        idl_name: String,
        hash: String,
        slot: u64,
    },
    Registry {
        action: String,
        source: String,
        bound_program: Option<String>,
    },
}

impl DecodeProvenance {
    pub fn source_description(&self) -> String {
        match self {
            DecodeProvenance::OnChainIdl {
                idl_name,
                hash,
                slot,
            } => {
                let hash_prefix: String = hash.chars().take(8).collect();
                format!("On-chain IDL · {idl_name} · slot {slot} · {hash_prefix}")
            }
            DecodeProvenance::Registry {
                action,
                source,
                bound_program,
            } => match bound_program {
                Some(bound_program) => {
                    format!("{action} · {source} registry, bound to {bound_program} IDL")
                }
                None => format!("{action} · {source} registry"),
            },
        }
    }
}

/// Whether a decoded instruction's expected effect matches the relay's
/// simulated effect for the same instruction.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CrossCheckVerdict {
    Confirmed,
    Unconfirmed,
    Contradicted,
}

/// The rendered form of a decoded instruction, ready for display.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecodedInstructionDisplay {
    pub program_label: String,
    pub kind: String,
    pub summary: String,
    pub accounts: Vec<String>,
    pub data_hex: String,
    pub provenance: Option<DecodeProvenance>,
    pub cross_check: Option<CrossCheckVerdict>,
}

/// Everything the app already holds and hands the core to decode a proposal:
/// the proposal's instructions and referenced accounts, the vault-relative
/// orientation for the cross-check, the relay coordinates for the IDL/spec/mint
/// augmentation the core fetches itself, and the relay's inspection effects
/// (fetched app-side, passed in) that the cross-check compares against.
#[derive(Debug, Clone)]
pub struct DecodeProposalRequest {
    pub relay_base_url: String,
    pub relay_capabilities: Vec<String>,
    pub instructions: Vec<DecodedInstruction>,
    pub accounts_referenced: Vec<String>,
    pub own_vault_accounts: Vec<String>,
    pub inspection_effects: Vec<crate::decode::wire::RelayInspectionEffect>,
    /// The last-accepted decode-registry manifest `issuedAt`, persisted by the
    /// app per relay, so a fresh fetch can't be rolled back to an older
    /// manifest. `None` (first run, or a relay switch) accepts any valid,
    /// non-expired manifest.
    pub last_accepted_manifest_issued_at: Option<String>,
}

/// The finished, render-ready decode of a proposal.
#[derive(Debug, Clone)]
pub struct DecodedProposal {
    pub instructions: Vec<DecodedInstructionDisplay>,
    pub has_contradiction: bool,
    /// The accepted decode-registry manifest `issuedAt`, for the app to
    /// persist and thread back in as `last_accepted_manifest_issued_at` on
    /// the next decode. `None` when no manifest verified (inert path).
    pub accepted_manifest_issued_at: Option<String>,
}

/// Decodes one instruction: the bundled family decoders (dispatched by
/// `is_*_program` predicate, in Swift's exact branch order) win immediately
/// over any spec or IDL; only a program with no bundled family falls to the
/// tier-3/tier-2/raw chain. Field-for-field port of
/// `InstructionDecoder.decode(_ instruction:)`.
///
/// `accounts` mirrors Swift's `overrideAccounts: [String]? = nil`: `None`
/// falls back to `instruction.accounts`.
pub fn decode_instruction(
    instruction: &DecodedInstruction,
    accounts: Option<&[String]>,
    idls: &HashMap<String, ResolvedProgramIdl>,
    specs: &HashMap<String, Vec<DecodeSpec>>,
    mints: &HashMap<String, MintInfo>,
    cross_check: Option<&CrossCheckContext>,
) -> DecodedInstructionDisplay {
    let accounts = accounts.unwrap_or(&instruction.accounts);

    let Some(data) = primitives::bytes_from_hex(&instruction.raw_data_hex) else {
        return primitives::fallback(instruction, accounts);
    };

    if primitives::is_system_program(&instruction.program) {
        return primitives::decode_system(instruction, &data, accounts);
    }
    if primitives::is_token_program(&instruction.program) {
        return primitives::decode_token(instruction, &data, accounts);
    }
    if primitives::is_stake_program(&instruction.program) {
        return primitives::decode_stake(instruction, &data, accounts);
    }
    if primitives::is_address_lookup_table_program(&instruction.program) {
        return primitives::decode_address_lookup_table(instruction, &data, accounts);
    }
    if primitives::is_associated_token_account_program(&instruction.program) {
        return primitives::decode_associated_token_account(instruction, &data, accounts);
    }
    if primitives::is_memo_program(&instruction.program) {
        return primitives::decode_memo(instruction, &data, accounts);
    }
    if primitives::is_compute_budget_program(&instruction.program) {
        return primitives::decode_compute_budget(instruction, &data, accounts);
    }
    if primitives::is_upgradeable_loader_program(&instruction.program) {
        return primitives::decode_upgradeable_loader(instruction, &data, accounts);
    }
    if primitives::is_squads_program(&instruction.program) {
        return primitives::decode_squads(instruction, accounts);
    }

    interpret_spec_candidates(instruction, accounts, idls, specs, mints, cross_check)
        .or_else(|| interpret_idl_for_program(instruction, accounts, idls))
        .unwrap_or_else(|| primitives::fallback(instruction, accounts))
}

/// Tier-3: tries every spec registered for `instruction.program`, in order,
/// returning the first that interprets successfully. Field-for-field port of
/// `InstructionDecoder.interpretSpec`.
fn interpret_spec_candidates(
    instruction: &DecodedInstruction,
    accounts: &[String],
    idls: &HashMap<String, ResolvedProgramIdl>,
    specs: &HashMap<String, Vec<DecodeSpec>>,
    mints: &HashMap<String, MintInfo>,
    cross_check: Option<&CrossCheckContext>,
) -> Option<DecodedInstructionDisplay> {
    let candidates = specs.get(&instruction.program)?;
    let resolved_idl = idls.get(&instruction.program);
    candidates.iter().find_map(|candidate| {
        spec::interpret_spec(
            instruction,
            candidate,
            resolved_idl,
            accounts,
            mints,
            cross_check,
        )
    })
}

/// Tier-2: interprets `instruction` against the on-chain IDL resolved for
/// its program, if any. Field-for-field port of
/// `InstructionDecoder.interpretIDL`.
fn interpret_idl_for_program(
    instruction: &DecodedInstruction,
    accounts: &[String],
    idls: &HashMap<String, ResolvedProgramIdl>,
) -> Option<DecodedInstructionDisplay> {
    let resolved = idls.get(&instruction.program)?;
    idl::interpret_idl(instruction, resolved, accounts)
}

/// Decodes every instruction in a proposal. Field-for-field port of
/// `InstructionDecoder.decode(_ proposal:)`: an instruction with no accounts
/// of its own falls back to the proposal's `accounts_referenced`.
pub fn decode_all(
    instructions: &[DecodedInstruction],
    accounts_referenced: &[String],
    idls: &HashMap<String, ResolvedProgramIdl>,
    specs: &HashMap<String, Vec<DecodeSpec>>,
    mints: &HashMap<String, MintInfo>,
    cross_check: Option<&CrossCheckContext>,
) -> Vec<DecodedInstructionDisplay> {
    instructions
        .iter()
        .map(|instruction| {
            let accounts = if instruction.accounts.is_empty() {
                accounts_referenced
            } else {
                &instruction.accounts
            };
            decode_instruction(instruction, Some(accounts), idls, specs, mints, cross_check)
        })
        .collect()
}

/// Programs whose instructions do not decode from a bundled family and so need
/// an on-chain IDL fetched. Port of `InstructionDecoder.programsNeedingIDL`:
/// an instruction that decodes to `kind == "raw"` with empty inputs needs one.
pub fn programs_needing_idl(instructions: &[DecodedInstruction]) -> Vec<String> {
    let empty_idls = HashMap::new();
    let empty_specs = HashMap::new();
    let empty_mints = HashMap::new();
    let mut seen = HashSet::new();
    let mut result = Vec::new();
    for instruction in instructions {
        let decoded = decode_instruction(
            instruction,
            None,
            &empty_idls,
            &empty_specs,
            &empty_mints,
            None,
        );
        if decoded.kind == "raw" && seen.insert(instruction.program.clone()) {
            result.push(instruction.program.clone());
        }
    }
    result
}

/// Decodes a proposal's instructions: fetches the IDL/spec/mint augmentation
/// from the relay (fail-open to empty when the relay is unusable or any
/// individual fetch fails), projects mints, builds the cross-check context
/// under the single-instruction gate, and decodes. Fail-safe: never panics,
/// never throws.
pub fn run_decode_proposal(request: &DecodeProposalRequest) -> DecodedProposal {
    let programs = programs_needing_idl(&request.instructions);
    let mut accounts: Vec<String> = request.accounts_referenced.clone();
    for instruction in &request.instructions {
        accounts.extend(instruction.accounts.iter().cloned());
    }

    let augmentation = match crate::decode::fetch::shared_client(
        &request.relay_base_url,
        &request.relay_capabilities,
    ) {
        Some(client) => client.fetch_decode_augmentation(
            &programs,
            &accounts,
            request.last_accepted_manifest_issued_at.as_deref(),
        ),
        None => crate::decode::fetch::DecodeAugmentation {
            idls: HashMap::new(),
            specs: HashMap::new(),
            resolved_mints: HashMap::new(),
            accepted_manifest_issued_at: None,
        },
    };

    let mints: HashMap<String, MintInfo> = augmentation
        .resolved_mints
        .iter()
        .map(|(account, resolved)| {
            (
                account.clone(),
                MintInfo {
                    symbol: resolved
                        .symbol
                        .clone()
                        .unwrap_or_else(|| primitives::short_address(&resolved.mint)),
                    decimals: resolved.decimals,
                },
            )
        })
        .collect();

    let cross_check = build_cross_check(request, &augmentation.resolved_mints);
    let instructions = decode_all(
        &request.instructions,
        &request.accounts_referenced,
        &augmentation.idls,
        &augmentation.specs,
        &mints,
        cross_check.as_ref(),
    );
    let has_contradiction = instructions
        .iter()
        .any(|i| i.cross_check == Some(CrossCheckVerdict::Contradicted));
    DecodedProposal {
        instructions,
        has_contradiction,
        accepted_manifest_issued_at: augmentation.accepted_manifest_issued_at,
    }
}

/// The fail-safe single-instruction cross-check gate: a context is built only
/// for a single-instruction proposal with non-empty inspection effects. Port of
/// Swift's `proposalCrossCheckContext`.
fn build_cross_check(
    request: &DecodeProposalRequest,
    resolved_mints: &HashMap<String, ResolvedMint>,
) -> Option<CrossCheckContext> {
    if request.instructions.len() != 1 || request.inspection_effects.is_empty() {
        return None;
    }
    let own: HashSet<String> = request.own_vault_accounts.iter().cloned().collect();
    Some(CrossCheckContext {
        simulated: AssetMovement::build(&request.inspection_effects, &own),
        resolved_mints: resolved_mints.clone(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn on_chain_idl_source_description_truncates_hash_to_eight_chars() {
        let provenance = DecodeProvenance::OnChainIdl {
            idl_name: "kamino_lending".to_string(),
            hash: "abcdef0123456789".to_string(),
            slot: 42,
        };
        assert_eq!(
            provenance.source_description(),
            "On-chain IDL · kamino_lending · slot 42 · abcdef01"
        );
    }

    #[test]
    fn registry_source_description_with_bound_program() {
        let provenance = DecodeProvenance::Registry {
            action: "Deposit".to_string(),
            source: "community".to_string(),
            bound_program: Some("kamino_lending".to_string()),
        };
        assert_eq!(
            provenance.source_description(),
            "Deposit · community registry, bound to kamino_lending IDL"
        );
    }

    #[test]
    fn registry_source_description_without_bound_program() {
        let provenance = DecodeProvenance::Registry {
            action: "Deposit".to_string(),
            source: "community".to_string(),
            bound_program: None,
        };
        assert_eq!(
            provenance.source_description(),
            "Deposit · community registry"
        );
    }
}

#[cfg(test)]
mod orchestration_tests {
    use super::*;
    use crate::decode::idl::{
        AnchorIdlArgument, AnchorIdlDocument, AnchorIdlInstruction, AnchorIdlType,
        ResolvedProgramIdl,
    };
    use crate::decode::spec::DecodeSpec;
    use crate::decode::wire::{AssetMovement, AssetMovementLeg, Direction, RelayInspectionEffect};
    use crate::types::DecodedInstruction;
    use std::collections::HashMap;

    const STAKE_PROGRAM: &str = "SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy";
    const SYSTEM_PROGRAM: &str = primitives::SYSTEM_PROGRAM_ID;

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
    fn stake_spec() -> DecodeSpec {
        serde_json::from_str(&format!(
            r#"{{"program":"{STAKE_PROGRAM}","discriminator":[14],"mode":"standalone",
          "layout":[{{"name":"lamports","type":"u64"}}],"action":"Stake","accounts":{{}},
          "template":"Stake {{lamports:sol}}","effects":[]}}"#
        ))
        .unwrap()
    }

    #[test]
    fn tier3_spec_wins_over_fallback() {
        let specs: HashMap<_, _> = [(STAKE_PROGRAM.to_string(), vec![stake_spec()])]
            .into_iter()
            .collect();
        let d = decode_instruction(
            &ix(STAKE_PROGRAM, "0e0094357700000000"),
            Some(&[]),
            &HashMap::new(),
            &specs,
            &HashMap::new(),
            None,
        );
        assert_eq!(d.kind, "Stake");
        assert_eq!(d.summary, "Stake 2 SOL");
    }

    #[test]
    fn falls_back_when_no_spec_provided() {
        let d = decode_instruction(
            &ix(STAKE_PROGRAM, "0e0094357700000000"),
            Some(&[]),
            &HashMap::new(),
            &HashMap::new(),
            &HashMap::new(),
            None,
        );
        assert_eq!(d.kind, "raw");
        assert_eq!(d.provenance, None);
    }

    #[test]
    fn decode_all_applies_referenced_accounts_fallback() {
        let insts = vec![ix(
            "11111111111111111111111111111111",
            "020000000100000000000000",
        )];
        let out = decode_all(
            &insts,
            &["from".into(), "to".into()],
            &HashMap::new(),
            &HashMap::new(),
            &HashMap::new(),
            None,
        );
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].accounts, vec!["from".to_string(), "to".to_string()]);
        assert_eq!(out[0].summary, "Transfer 0.000000001 SOL");
    }

    /// A bundled primitive family must win immediately — before tier-3 spec
    /// or tier-2 IDL are ever consulted — even when both are registered for
    /// the same program and would render a completely different statement.
    #[test]
    fn primitive_family_wins_over_spec_and_idl() {
        let specs: HashMap<_, _> = [(
            SYSTEM_PROGRAM.to_string(),
            vec![
                serde_json::from_str::<DecodeSpec>(&format!(
                    r#"{{"program":"{SYSTEM_PROGRAM}","discriminator":[2,0,0,0],"mode":"standalone",
                    "layout":[{{"name":"lamports","type":"u64"}}],"action":"NotThis","accounts":{{}},
                    "template":"Should never render","effects":[]}}"#
                ))
                .unwrap(),
            ],
        )]
        .into_iter()
        .collect();
        let idls: HashMap<_, _> = [(
            SYSTEM_PROGRAM.to_string(),
            ResolvedProgramIdl {
                document: AnchorIdlDocument {
                    name: "should-not-be-used".into(),
                    instructions: vec![],
                },
                provenance: DecodeProvenance::OnChainIdl {
                    idl_name: "should-not-be-used".into(),
                    hash: "h".into(),
                    slot: 1,
                },
            },
        )]
        .into_iter()
        .collect();

        let d = decode_instruction(
            &ix(SYSTEM_PROGRAM, "020000008813000000000000"),
            Some(&["from".into(), "to".into()]),
            &idls,
            &specs,
            &HashMap::new(),
            None,
        );
        assert_eq!(d.program_label, "System Program");
        assert_eq!(d.kind, "transfer");
        assert_eq!(d.summary, "Transfer 0.000005 SOL");
        assert_eq!(d.provenance, None);
    }

    /// With no spec matching, the tier-2 on-chain IDL still wins over the
    /// raw fallback.
    #[test]
    fn tier2_idl_wins_over_raw_fallback_when_no_spec_matches() {
        let program = "UnknownProgram1111111111111111111111111111";
        let idls: HashMap<_, _> = [(
            program.to_string(),
            ResolvedProgramIdl {
                document: AnchorIdlDocument {
                    name: "demo".into(),
                    instructions: vec![AnchorIdlInstruction {
                        name: "swap".into(),
                        discriminator: vec![1, 2, 3, 4, 5, 6, 7, 8],
                        arguments: vec![AnchorIdlArgument {
                            name: "amount".into(),
                            arg_type: AnchorIdlType::U64,
                        }],
                    }],
                },
                provenance: DecodeProvenance::OnChainIdl {
                    idl_name: "demo".into(),
                    hash: "deadbeef".into(),
                    slot: 7,
                },
            },
        )]
        .into_iter()
        .collect();

        let d = decode_instruction(
            &ix(program, "010203040506070840420f0000000000"),
            Some(&[]),
            &idls,
            &HashMap::new(),
            &HashMap::new(),
            None,
        );
        assert_eq!(d.kind, "swap");
        assert_eq!(d.summary, "swap(amount: 1000000)");
        assert!(matches!(
            d.provenance,
            Some(DecodeProvenance::OnChainIdl { .. })
        ));
    }

    #[test]
    fn unknown_program_with_no_spec_or_idl_falls_back_to_raw() {
        let program = "TotallyUnknownProgram11111111111111111111";
        let d = decode_instruction(
            &ix(program, "ff"),
            Some(&[]),
            &HashMap::new(),
            &HashMap::new(),
            &HashMap::new(),
            None,
        );
        assert_eq!(d.kind, "raw");
        assert_eq!(d.program_label, program);
        assert_eq!(d.provenance, None);
    }

    #[test]
    fn decode_carries_verdict_through_interpret_spec() {
        let spec = serde_json::from_str::<DecodeSpec>(&format!(
            r#"{{"program":"{STAKE_PROGRAM}","discriminator":[14],"mode":"standalone",
            "layout":[{{"name":"lamports","type":"u64"}}],"action":"Stake","accounts":{{"vault":0}},
            "template":"Stake {{lamports:sol}}",
            "effects":[{{"direction":"out","asset":"SOL","amount":"arg(lamports)"}}]}}"#
        ))
        .unwrap();
        let specs: HashMap<_, _> = [(STAKE_PROGRAM.to_string(), vec![spec])]
            .into_iter()
            .collect();
        let context = CrossCheckContext {
            simulated: AssetMovement {
                legs: vec![AssetMovementLeg {
                    direction: Direction::Outflow,
                    amount: "2 SOL".into(),
                    asset: "SOL".into(),
                    counterparty: None,
                }],
            },
            resolved_mints: HashMap::new(),
        };
        let d = decode_instruction(
            &ix(STAKE_PROGRAM, "0e0094357700000000"),
            Some(&["vaultAddr".into()]),
            &HashMap::new(),
            &specs,
            &HashMap::new(),
            Some(&context),
        );
        assert_eq!(d.kind, "Stake");
        assert_eq!(d.cross_check, Some(CrossCheckVerdict::Confirmed));
    }

    #[test]
    fn defaulted_cross_check_leaves_verdict_nil() {
        let specs: HashMap<_, _> = [(STAKE_PROGRAM.to_string(), vec![stake_spec()])]
            .into_iter()
            .collect();
        let d = decode_instruction(
            &ix(STAKE_PROGRAM, "0e0094357700000000"),
            Some(&[]),
            &HashMap::new(),
            &specs,
            &HashMap::new(),
            None,
        );
        assert_eq!(d.cross_check, None);
    }

    #[test]
    fn defaulted_empty_inputs_leave_decode_at_raw() {
        let d = decode_instruction(
            &ix(STAKE_PROGRAM, "0e0094357700000000"),
            None,
            &HashMap::new(),
            &HashMap::new(),
            &HashMap::new(),
            None,
        );
        assert_eq!(d.kind, "raw");
        assert_eq!(d.provenance, None);
    }

    #[test]
    fn run_decode_proposal_decodes_passed_instructions_with_no_augmentation() {
        // Empty relay_base_url ⇒ no client ⇒ no fetch ⇒ tier-1 primitive + raw only.
        let request = DecodeProposalRequest {
            relay_base_url: String::new(),
            relay_capabilities: vec![],
            instructions: vec![ix(SYSTEM_PROGRAM, "020000008813000000000000")],
            accounts_referenced: vec!["from".into(), "to".into()],
            own_vault_accounts: vec![],
            inspection_effects: vec![],
            last_accepted_manifest_issued_at: None,
        };
        let result = run_decode_proposal(&request);
        assert_eq!(result.instructions.len(), 1);
        assert_eq!(result.instructions[0].program_label, "System Program");
        assert_eq!(result.instructions[0].summary, "Transfer 0.000005 SOL");
        assert_eq!(result.instructions[0].cross_check, None);
        assert!(!result.has_contradiction);
        // No relay ⇒ no manifest ever fetched ⇒ inert: nothing accepted.
        assert_eq!(result.accepted_manifest_issued_at, None);
    }

    #[test]
    fn programs_needing_idl_lists_only_unrecognized_programs() {
        let insts = vec![
            ix(SYSTEM_PROGRAM, "020000008813000000000000"), // bundled → not needed
            ix("UnknownProg1111111111111111111111111111111", "01020304"), // raw → needed
            ix("UnknownProg1111111111111111111111111111111", "aabb"), // dup → once
        ];
        assert_eq!(
            programs_needing_idl(&insts),
            vec!["UnknownProg1111111111111111111111111111111".to_string()]
        );
    }

    // The new gate logic, tested directly (key-independent). `build_cross_check`
    // is a private sibling fn, reachable from this `use super::*` test module. The
    // context→verdict wiring is already covered by
    // `decode_carries_verdict_through_interpret_spec` (which injects specs), so this
    // test asserts only the gate: single instruction + non-empty effects ⇒ Some,
    // with the simulated movement built from the effects; anything else ⇒ None.
    #[test]
    fn build_cross_check_gate_builds_context_only_for_single_instruction_with_effects() {
        let effect = RelayInspectionEffect {
            kind: "transfer".into(),
            summary: "s".into(),
            program: None,
            asset: Some("SOL".into()),
            amount: Some("2 SOL".into()),
            source: Some("vaultAddr".into()),
            destination: Some("dest".into()),
        };
        let base = DecodeProposalRequest {
            relay_base_url: String::new(),
            relay_capabilities: vec![],
            instructions: vec![ix(STAKE_PROGRAM, "0e0094357700000000")],
            accounts_referenced: vec!["vaultAddr".into()],
            own_vault_accounts: vec!["vaultAddr".into()],
            inspection_effects: vec![effect.clone()],
            last_accepted_manifest_issued_at: None,
        };
        // Single instruction + effects ⇒ Some, with an outflow leg (source is own).
        let context = build_cross_check(&base, &HashMap::new()).expect("context built");
        assert_eq!(context.simulated.legs.len(), 1);
        assert_eq!(context.simulated.legs[0].direction, Direction::Outflow);

        // No effects ⇒ None.
        let no_effects = DecodeProposalRequest {
            inspection_effects: vec![],
            ..base.clone()
        };
        assert!(build_cross_check(&no_effects, &HashMap::new()).is_none());

        // Two instructions ⇒ None (the fail-safe multi-instruction gate).
        let multi = DecodeProposalRequest {
            instructions: vec![
                ix(STAKE_PROGRAM, "0e0094357700000000"),
                ix(STAKE_PROGRAM, "0e0094357700000000"),
            ],
            ..base
        };
        assert!(build_cross_check(&multi, &HashMap::new()).is_none());
    }

    #[test]
    fn multi_instruction_proposal_never_cross_checks() {
        let request = DecodeProposalRequest {
            relay_base_url: String::new(),
            relay_capabilities: vec![],
            instructions: vec![
                ix(SYSTEM_PROGRAM, "020000008813000000000000"),
                ix(SYSTEM_PROGRAM, "020000008813000000000000"),
            ],
            accounts_referenced: vec!["a".into(), "b".into()],
            own_vault_accounts: vec!["a".into()],
            inspection_effects: vec![RelayInspectionEffect {
                kind: "transfer".into(),
                summary: "s".into(),
                program: None,
                asset: Some("SOL".into()),
                amount: Some("1 SOL".into()),
                source: Some("a".into()),
                destination: Some("b".into()),
            }],
            last_accepted_manifest_issued_at: None,
        };
        let result = run_decode_proposal(&request);
        assert_eq!(result.instructions.len(), 2);
        assert!(result.instructions.iter().all(|i| i.cross_check.is_none()));
        assert!(!result.has_contradiction);
    }

    #[test]
    fn empty_relay_url_fails_open_to_tier1_and_raw() {
        let request = DecodeProposalRequest {
            relay_base_url: String::new(),
            relay_capabilities: vec![],
            instructions: vec![ix("UnknownProg1111111111111111111111111111111", "01020304")],
            accounts_referenced: vec![],
            own_vault_accounts: vec![],
            inspection_effects: vec![],
            last_accepted_manifest_issued_at: None,
        };
        let result = run_decode_proposal(&request);
        assert_eq!(result.instructions[0].kind, "raw");
        assert_eq!(result.instructions[0].provenance, None);
    }
}
