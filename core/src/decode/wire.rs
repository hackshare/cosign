//! Relay JSON envelope + asset-movement models that the decode stack
//! consumes. Field-for-field port of `Modules/Indexer/Sources/AssetMovement.swift`
//! and the decode-relevant slices of `RelayModels+*.swift`.

use std::collections::HashSet;

use serde::Deserialize;

use super::idl::AnchorIdlDocument;

/// The direction of one leg of an [`AssetMovement`], relative to the
/// squad's own accounts. Distinct from `spec::Direction`, which is the
/// decode-spec JSON's `in`/`out`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Direction {
    Outflow,
    Inflow,
}

/// A single directional leg of an asset movement, derived from one decoded
/// effect classified against the squad's own accounts. An effect whose
/// source is an own account is an outflow whose counterparty is the
/// destination ("to"); an effect whose destination is an own account is an
/// inflow whose counterparty is the source ("from").
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AssetMovementLeg {
    pub direction: Direction,
    pub amount: String,
    pub asset: String,
    /// The other party: the destination for an outflow, the source for an inflow.
    pub counterparty: Option<String>,
}

/// The movement a transaction makes, built purely from decoded effects so
/// it is identical for a predicted (simulated) proposal and an executed
/// (traced) one. Direction is relative to the squad: an effect leaving an
/// own account is an outflow, one arriving at an own account is an inflow.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct AssetMovement {
    pub legs: Vec<AssetMovementLeg>,
}

impl AssetMovement {
    pub fn is_empty(&self) -> bool {
        self.legs.is_empty()
    }

    /// Classifies each effect against `own_accounts`: an effect missing
    /// `amount` or `asset` is skipped; otherwise a source that is an own
    /// account wins an outflow leg (counterparty = destination), else a
    /// destination that is an own account wins an inflow leg (counterparty
    /// = source), else the effect is skipped. Source-own is checked first,
    /// so an effect where both source and destination are own accounts
    /// produces an outflow.
    pub fn build(
        effects: &[RelayInspectionEffect],
        own_accounts: &HashSet<String>,
    ) -> AssetMovement {
        let mut legs = Vec::new();
        for effect in effects {
            let (Some(amount), Some(asset)) = (&effect.amount, &effect.asset) else {
                continue;
            };
            if effect
                .source
                .as_ref()
                .is_some_and(|source| own_accounts.contains(source))
            {
                legs.push(AssetMovementLeg {
                    direction: Direction::Outflow,
                    amount: amount.clone(),
                    asset: asset.clone(),
                    counterparty: effect.destination.clone(),
                });
            } else if effect
                .destination
                .as_ref()
                .is_some_and(|destination| own_accounts.contains(destination))
            {
                legs.push(AssetMovementLeg {
                    direction: Direction::Inflow,
                    amount: amount.clone(),
                    asset: asset.clone(),
                    counterparty: effect.source.clone(),
                });
            }
        }
        AssetMovement { legs }
    }
}

/// One decoded effect of a proposal or executed transaction, as emitted by
/// the relay's simulation/trace inspection. Port of Swift's
/// `RelayInspectionEffect`.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct RelayInspectionEffect {
    pub kind: String,
    pub summary: String,
    pub program: Option<String>,
    pub asset: Option<String>,
    pub amount: Option<String>,
    pub source: Option<String>,
    pub destination: Option<String>,
}

/// A warning attached to a relay-inspected action. Port of Swift's
/// `RelayInspectionWarning`.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct RelayInspectionWarning {
    pub severity: String,
    pub code: String,
    pub message: String,
}

/// The relay's classification of a proposal or executed transaction. Port
/// of Swift's `RelayInspectionAction`.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct RelayInspectionAction {
    pub classification: String,
    pub summary: String,
    pub confidence: String,
    pub effects: Vec<RelayInspectionEffect>,
    pub warnings: Vec<RelayInspectionWarning>,
}

/// The relay's simulated-execution result for a proposal. Port of Swift's
/// `ProposalInspectionSimulation`.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProposalSimulation {
    pub status: String,
    pub message: String,
    pub error: Option<String>,
    pub logs: Vec<String>,
    pub fee_payer: Option<String>,
    pub recent_blockhash: Option<String>,
}

/// The relay's program-IDL envelope: a resolved on-chain Anchor IDL plus
/// its provenance (hash, slot). Port of Swift's `ProgramIDLResponse`
/// (decode-relevant fields only; `kind`/`cluster`/`authority` are owned by
/// the Plan 2 transport layer).
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct ProgramIdlResponse {
    pub program: String,
    pub idl: AnchorIdlDocument,
    pub hash: String,
    pub slot: u64,
}

/// The relay's decode-spec registry bundle: a signed blob of decode specs.
/// Not `Deserialize` — the Plan 2 transport layer fills this from a raw
/// HTTP response; decode only needs the shape to exist.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecodeRegistryResponse {
    pub bundle_data: Vec<u8>,
    pub signature_base64: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn effect(
        kind: &str,
        asset: Option<&str>,
        amount: Option<&str>,
        source: Option<&str>,
        destination: Option<&str>,
    ) -> RelayInspectionEffect {
        RelayInspectionEffect {
            kind: kind.into(),
            summary: String::new(),
            program: None,
            asset: asset.map(Into::into),
            amount: amount.map(Into::into),
            source: source.map(Into::into),
            destination: destination.map(Into::into),
        }
    }
    fn own(a: &[&str]) -> HashSet<String> {
        a.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn outflow_from_own_goes_to_destination() {
        let m = AssetMovement::build(
            &[effect(
                "transfer",
                Some("SOL"),
                Some("250"),
                Some("VAULT"),
                Some("Pool"),
            )],
            &own(&["VAULT"]),
        );
        assert_eq!(m.legs.len(), 1);
        assert_eq!(m.legs[0].direction, Direction::Outflow);
        assert_eq!(m.legs[0].counterparty.as_deref(), Some("Pool"));
        assert_eq!(m.legs[0].amount, "250");
        assert_eq!(m.legs[0].asset, "SOL");
    }

    #[test]
    fn inflow_to_own_comes_from_source() {
        let m = AssetMovement::build(
            &[effect(
                "transfer",
                Some("USDC"),
                Some("18000"),
                Some("Jupiter"),
                Some("VAULT"),
            )],
            &own(&["VAULT"]),
        );
        assert_eq!(m.legs[0].direction, Direction::Inflow);
        assert_eq!(m.legs[0].counterparty.as_deref(), Some("Jupiter"));
    }

    #[test]
    fn swap_produces_one_outflow_one_inflow() {
        let m = AssetMovement::build(
            &[
                effect(
                    "transfer",
                    Some("SOL"),
                    Some("250"),
                    Some("VAULT"),
                    Some("Pool"),
                ),
                effect(
                    "transfer",
                    Some("USDC"),
                    Some("18000"),
                    Some("Pool"),
                    Some("VAULT"),
                ),
            ],
            &own(&["VAULT"]),
        );
        assert_eq!(m.legs.len(), 2);
        assert_eq!(m.legs[0].direction, Direction::Outflow);
        assert_eq!(m.legs[1].direction, Direction::Inflow);
    }

    #[test]
    fn touching_no_own_account_is_skipped() {
        assert!(
            AssetMovement::build(
                &[effect(
                    "transfer",
                    Some("USDC"),
                    Some("1"),
                    Some("X"),
                    Some("Y")
                )],
                &own(&["VAULT"])
            )
            .is_empty()
        );
    }

    #[test]
    fn burn_and_mint_have_no_counterparty() {
        let burn = AssetMovement::build(
            &[effect("burn", Some("JTO"), Some("5"), Some("VAULT"), None)],
            &own(&["VAULT"]),
        );
        assert_eq!(burn.legs[0].direction, Direction::Outflow);
        assert_eq!(burn.legs[0].counterparty, None);
        let mint = AssetMovement::build(
            &[effect("mint", Some("JTO"), Some("5"), None, Some("VAULT"))],
            &own(&["VAULT"]),
        );
        assert_eq!(mint.legs[0].direction, Direction::Inflow);
        assert_eq!(mint.legs[0].counterparty, None);
    }

    #[test]
    fn source_own_takes_precedence_and_missing_fields_skip() {
        let both = AssetMovement::build(
            &[effect(
                "transfer",
                Some("SOL"),
                Some("1"),
                Some("VAULT"),
                Some("VAULT"),
            )],
            &own(&["VAULT"]),
        );
        assert_eq!(both.legs[0].direction, Direction::Outflow);
        let missing = AssetMovement::build(
            &[
                effect("transfer", None, Some("100"), Some("VAULT"), Some("B")),
                effect("transfer", Some("USDC"), None, Some("VAULT"), Some("B")),
            ],
            &own(&["VAULT"]),
        );
        assert!(missing.is_empty());
    }

    #[test]
    fn relay_action_and_simulation_parse() {
        let a: RelayInspectionAction = serde_json::from_str(
            r#"{"classification":"transfer","summary":"s","confidence":"high",
                "effects":[{"kind":"token_transfer","summary":"t","program":"SPL Token","asset":"M","amount":"1.5","source":"a","destination":"b"}],
                "warnings":[{"severity":"info","code":"c","message":"m"}]}"#,
        )
        .unwrap();
        assert_eq!(a.effects.len(), 1);
        assert_eq!(a.effects[0].amount.as_deref(), Some("1.5"));
        assert_eq!(a.warnings[0].code, "c");
        let s: ProposalSimulation = serde_json::from_str(
            r#"{"status":"ok","message":"m","error":null,"logs":["l1"],"feePayer":"f","recentBlockhash":"h"}"#,
        )
        .unwrap();
        assert_eq!(s.logs, vec!["l1".to_string()]);
        assert_eq!(s.fee_payer.as_deref(), Some("f"));
    }
}
