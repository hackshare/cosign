//! Expected-asset-movement builder and the cross-check verdict that
//! compares it against the relay's simulated [`AssetMovement`]. Field-for-
//! field port of `ExpectedAssetMovement.swift` and `EffectCrossCheck.swift`
//! — the trust core that decides what a human sees before signing.
//!
//! **Numeric model.** Swift represents base-unit amounts as `Decimal`
//! (exact base-10 arithmetic). Rust's std has no equivalent, and `f64`
//! risks binary-float drift at the golden-fixture amounts, so every
//! base-unit amount here is a plain `i128` integer count. All golden
//! fixtures use whole base-unit amounts, so this is lossless for every
//! case the trust core needs to reproduce. Tolerance is computed with
//! integer arithmetic — `max(1, (value * 5) / 1000)`, i.e. 0.5%
//! floor-rounded with a 1-base-unit floor — matching Swift's
//! `max(Decimal(1), value * Decimal(5) / Decimal(1000))` exactly at every
//! whole-number amount. A relay display amount like `"0.25821431"` is
//! scaled to base units by parsing its integer and fractional digit runs
//! directly and concatenating them (padding or truncating the fractional
//! run to exactly `decimals` digits), never by multiplying floats — see
//! [`decimal_string_to_base_units`].

use std::collections::{HashMap, HashSet};

use super::CrossCheckVerdict;
use super::borsh::DecodedArgValue;
use super::mints::ResolvedMint;
use super::spec::{DecodeSpec, Effect, SpecDirection, when_predicate_holds};
use super::wire::{AssetMovement, Direction};

/// An expected leg's asset, resolved from a spec effect's `asset` string.
/// Carries both identifiers the relay might emit for the leg — the mint
/// address (SPL-transfer CPIs) and the symbol (demo fixtures / well-known
/// tokens) — plus the decimals used to normalize the relay's display
/// amount.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ExpectedAsset {
    Sol,
    Token {
        mint: String,
        symbol: String,
        decimals: i64,
    },
    Unresolved,
}

/// An expected leg's amount, resolved from a spec effect's `amount` /
/// `amountAtLeast` / `amountAtMost` reference. Base-unit integers — see
/// the module-level numeric-model note.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExpectedAmount {
    Exact(i128),
    AtLeast(i128),
    AtMost(i128),
    Unresolved,
}

/// One leg of an [`ExpectedAssetMovement`].
#[derive(Debug, Clone, PartialEq)]
pub struct ExpectedAssetMovementLeg {
    pub direction: Direction,
    pub asset: ExpectedAsset,
    pub amount: ExpectedAmount,
}

/// The asset movement a decode spec's applicable effects declare, ready to
/// be cross-checked against the relay's simulated [`AssetMovement`].
#[derive(Debug, Clone, PartialEq)]
pub struct ExpectedAssetMovement {
    pub legs: Vec<ExpectedAssetMovementLeg>,
}

/// The inputs a caller assembles once per proposal to cross-check every
/// instruction's expected movement against a single simulated outcome and
/// the mints resolved for it.
#[derive(Debug, Clone, PartialEq)]
pub struct CrossCheckContext {
    pub simulated: AssetMovement,
    pub resolved_mints: HashMap<String, ResolvedMint>,
}

/// Builds the [`ExpectedAssetMovement`] a spec's applicable effects declare
/// (port of `ExpectedAssetMovementBuilder.build`). An effect is applicable
/// only when `when_predicate_holds` its `when` literals against `args`;
/// effects that don't apply (e.g. the inactive branch of a conditional
/// swap) are skipped entirely, not degraded to unresolved legs.
pub fn build_expected_movement(
    spec: &DecodeSpec,
    args: &HashMap<String, DecodedArgValue>,
    accounts: &[String],
    resolved_mints: &HashMap<String, ResolvedMint>,
) -> ExpectedAssetMovement {
    let mut legs = Vec::new();
    for effect in &spec.effects {
        if !when_predicate_holds(&effect.when, args) {
            continue;
        }
        let direction = match effect.direction {
            SpecDirection::Out => Direction::Outflow,
            SpecDirection::In => Direction::Inflow,
        };
        let asset = resolve_asset(&effect.asset, &spec.accounts, accounts, resolved_mints);
        let amount = resolve_amount(effect, args);
        legs.push(ExpectedAssetMovementLeg {
            direction,
            asset,
            amount,
        });
    }
    ExpectedAssetMovement { legs }
}

/// Resolves an effect's `asset` string: `"SOL"`, `"token(ROLE)"` (via
/// `role_indexes` → bounds-checked `accounts` → `resolved_mints`), or
/// anything else falls open to `Unresolved` rather than guessing.
fn resolve_asset(
    asset: &str,
    role_indexes: &HashMap<String, i64>,
    accounts: &[String],
    resolved_mints: &HashMap<String, ResolvedMint>,
) -> ExpectedAsset {
    if asset == "SOL" {
        return ExpectedAsset::Sol;
    }
    let Some(role) = asset
        .strip_prefix("token(")
        .and_then(|rest| rest.strip_suffix(')'))
    else {
        return ExpectedAsset::Unresolved;
    };
    let Some(&index) = role_indexes.get(role) else {
        return ExpectedAsset::Unresolved;
    };
    if index < 0 || index as usize >= accounts.len() {
        return ExpectedAsset::Unresolved;
    }
    let Some(resolved) = resolved_mints.get(&accounts[index as usize]) else {
        return ExpectedAsset::Unresolved;
    };
    ExpectedAsset::Token {
        mint: resolved.mint.clone(),
        symbol: resolved.symbol.clone().unwrap_or_default(),
        decimals: resolved.decimals,
    }
}

/// Resolves an effect's amount: `amount` → `Exact`, else `amountAtLeast` →
/// `AtLeast`, else `amountAtMost` → `AtMost`, else `Unresolved`. A present
/// reference that fails to resolve (unknown/wrong-typed arg, unparsable
/// literal) also degrades to `Unresolved` — it never silently falls
/// through to a different field.
fn resolve_amount(effect: &Effect, args: &HashMap<String, DecodedArgValue>) -> ExpectedAmount {
    if let Some(reference) = &effect.amount {
        return base_units_reference(reference, args)
            .map_or(ExpectedAmount::Unresolved, ExpectedAmount::Exact);
    }
    if let Some(reference) = &effect.amount_at_least {
        return base_units_reference(reference, args)
            .map_or(ExpectedAmount::Unresolved, ExpectedAmount::AtLeast);
    }
    if let Some(reference) = &effect.amount_at_most {
        return base_units_reference(reference, args)
            .map_or(ExpectedAmount::Unresolved, ExpectedAmount::AtMost);
    }
    ExpectedAmount::Unresolved
}

/// A reference is `arg(NAME)` — requiring `args[NAME]` to be a genuinely
/// decoded `Uint` — or a literal non-negative integer. Anything else
/// (missing arg, wrong-typed arg, malformed literal) is unresolvable.
fn base_units_reference(reference: &str, args: &HashMap<String, DecodedArgValue>) -> Option<i128> {
    if let Some(name) = reference
        .strip_prefix("arg(")
        .and_then(|rest| rest.strip_suffix(')'))
    {
        let Some(DecodedArgValue::Uint(value)) = args.get(name) else {
            return None;
        };
        return Some(*value as i128);
    }
    reference.parse::<u64>().ok().map(i128::from)
}

/// The three outcomes of comparing one expected leg against the simulated
/// movement.
enum LegOutcome {
    Match,
    NotComparable,
    Contradiction,
}

/// Computes the [`CrossCheckVerdict`] for `expected` against `simulated`
/// (port of `EffectCrossCheck.verdict`). Fail-safe by construction: a
/// verdict is only ever `Contradicted` when an asset's identity is
/// recognizable in the simulation and its amount or direction genuinely
/// disagrees; anything the simulation can't be lined up against degrades
/// to `Unconfirmed`, never a false `Contradicted` or a false `Confirmed`.
pub fn cross_check_verdict(
    expected: &ExpectedAssetMovement,
    simulated: &AssetMovement,
) -> CrossCheckVerdict {
    if expected.legs.is_empty() || simulated.legs.is_empty() {
        return CrossCheckVerdict::Unconfirmed;
    }

    // The union of every expected leg's identifiers (plus "SOL"). A
    // simulated leg is "comparable" only if its asset is in this set —
    // otherwise we cannot line its representation up with anything the
    // spec declares.
    let comparable_assets = canonical_asset_set(expected);
    let sim_has_comparable_leg = simulated
        .legs
        .iter()
        .any(|leg| comparable_assets.contains(&leg.asset));

    let mut saw_not_comparable = false;
    for leg in &expected.legs {
        match evaluate(leg, simulated, sim_has_comparable_leg) {
            LegOutcome::Match => continue,
            LegOutcome::NotComparable => saw_not_comparable = true,
            LegOutcome::Contradiction => return CrossCheckVerdict::Contradicted,
        }
    }
    if saw_not_comparable {
        CrossCheckVerdict::Unconfirmed
    } else {
        CrossCheckVerdict::Confirmed
    }
}

/// Every asset identifier the expected movement could match, so the
/// comparator can tell "the simulation has recognizable legs but not this
/// one" (a contradiction) from "we can't canonicalize the simulation at
/// all" (not comparable).
fn canonical_asset_set(expected: &ExpectedAssetMovement) -> HashSet<String> {
    let mut set = HashSet::from(["SOL".to_string()]);
    for leg in &expected.legs {
        set.extend(identifiers(&leg.asset));
    }
    set
}

/// The asset identifiers a simulated leg could use to refer to `asset`:
/// `"SOL"` for SOL, the mint address and/or symbol for a token (empty
/// strings filtered out), nothing for an unresolved asset.
fn identifiers(asset: &ExpectedAsset) -> HashSet<String> {
    match asset {
        ExpectedAsset::Sol => HashSet::from(["SOL".to_string()]),
        ExpectedAsset::Token { mint, symbol, .. } => [mint.clone(), symbol.clone()]
            .into_iter()
            .filter(|value| !value.is_empty())
            .collect(),
        ExpectedAsset::Unresolved => HashSet::new(),
    }
}

fn evaluate(
    leg: &ExpectedAssetMovementLeg,
    simulated: &AssetMovement,
    sim_has_comparable_leg: bool,
) -> LegOutcome {
    if leg.amount == ExpectedAmount::Unresolved {
        return LegOutcome::NotComparable;
    }
    let decimals = match &leg.asset {
        ExpectedAsset::Sol => 9,
        ExpectedAsset::Token { decimals, .. } => *decimals,
        ExpectedAsset::Unresolved => return LegOutcome::NotComparable,
    };
    let ids = identifiers(&leg.asset);
    if ids.is_empty() {
        return LegOutcome::NotComparable;
    }

    // 1. Same-direction leg whose asset matches by mint OR symbol.
    let directional: Vec<_> = simulated
        .legs
        .iter()
        .filter(|sim_leg| sim_leg.direction == leg.direction && ids.contains(&sim_leg.asset))
        .collect();
    if !directional.is_empty() {
        for candidate in directional {
            let Some(simulated_base_units) = base_units(&candidate.amount, decimals) else {
                continue;
            };
            if satisfies(leg.amount, simulated_base_units) {
                return LegOutcome::Match;
            }
        }
        return LegOutcome::Contradiction; // asset moved this direction but no amount agrees
    }

    // 2. The asset moved, but not in the expected direction → genuine disagreement.
    if simulated
        .legs
        .iter()
        .any(|sim_leg| ids.contains(&sim_leg.asset))
    {
        return LegOutcome::Contradiction;
    }

    // 3. This asset is absent from the simulation. Contradiction only if
    //    the simulation is otherwise comparable (has a recognizable leg);
    //    if we cannot canonicalize the simulation at all, fail safe to
    //    not-comparable.
    if sim_has_comparable_leg {
        LegOutcome::Contradiction
    } else {
        LegOutcome::NotComparable
    }
}

fn satisfies(expected: ExpectedAmount, simulated: i128) -> bool {
    match expected {
        ExpectedAmount::Unresolved => false,
        // Checked, so any overflow degrades to not-satisfied rather than
        // panicking (debug) or wrapping into a false match (release). With
        // `base_units` rejecting negatives, `simulated` is non-negative and
        // this can't actually overflow — but the relay's simulated amounts
        // are unsigned wire data, not signed like the registry bundle, so
        // the trust core stays fail-safe against future gaps too.
        ExpectedAmount::Exact(value) => simulated
            .checked_sub(value)
            .and_then(i128::checked_abs)
            .is_some_and(|diff| diff <= tolerance(value)),
        ExpectedAmount::AtLeast(value) => simulated >= value - tolerance(value),
        ExpectedAmount::AtMost(value) => simulated <= value + tolerance(value),
    }
}

/// 0.5% relative tolerance plus a 1-base-unit floor for exact-amount
/// matches, absorbing decimal-formatting round-trips and dust. Integer
/// arithmetic, rounding down — `max(1, value * 5 / 1000)`.
fn tolerance(value: i128) -> i128 {
    (value * 5 / 1000).max(1)
}

/// Normalizes a relay display amount to base units. `"… base units"` is
/// already base units (the leading token is parsed as a plain integer,
/// unscaled); `"… SOL"` and bare decimals are display values scaled by
/// `10^decimals`. Relay amounts are non-negative magnitudes, so a negative
/// value is rejected (`None`) — the candidate is skipped, keeping a hostile
/// near-`i128::MIN` amount out of the tolerance comparison. Parse failure
/// of any kind likewise returns `None`, never a coerced wrong amount.
fn base_units(amount: &str, decimals: i64) -> Option<i128> {
    let leading = amount.split_whitespace().next()?;
    if amount.contains("base unit") {
        return leading.parse::<i128>().ok().filter(|value| *value >= 0);
    }
    decimal_string_to_base_units(leading, decimals)
}

/// Scales a non-negative decimal string (digits, optional `.` + digits,
/// optional leading `+`) to an exact `i128` base-unit count at `decimals`
/// (clamped to `[0, 255]`), without floating point: the integer and
/// fractional digit runs are validated, the fractional run is padded with
/// trailing zeros or truncated to exactly `decimals` digits, and the two
/// runs are concatenated into one integer string before parsing. E.g.
/// `"0.25821431"` at `decimals = 9` → fractional run `"25821431"` (8
/// digits) padded to `"258214310"` → `258214310`, exactly. A negative
/// amount, negative `decimals` (SPL decimals is a `u8`; a negative value is
/// not a coherent scale), non-digit characters, a bare sign, or more than
/// one `.` all return `None`.
fn decimal_string_to_base_units(text: &str, decimals: i64) -> Option<i128> {
    if decimals < 0 || text.starts_with('-') {
        return None;
    }
    let scale = decimals.min(255) as usize;
    let unsigned = text.strip_prefix('+').unwrap_or(text);
    let (int_part, frac_part) = match unsigned.split_once('.') {
        Some((whole, fraction)) => (whole, fraction),
        None => (unsigned, ""),
    };
    if int_part.is_empty() && frac_part.is_empty() {
        return None;
    }
    if !int_part.bytes().all(|byte| byte.is_ascii_digit())
        || !frac_part.bytes().all(|byte| byte.is_ascii_digit())
    {
        return None;
    }
    let int_part = if int_part.is_empty() { "0" } else { int_part };

    let mut frac_digits = frac_part.to_string();
    if frac_digits.len() > scale {
        frac_digits.truncate(scale);
    } else {
        frac_digits.push_str(&"0".repeat(scale - frac_digits.len()));
    }

    format!("{int_part}{frac_digits}").parse::<i128>().ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::decode::wire::{AssetMovement, AssetMovementLeg, Direction};

    fn sim(legs: &[(Direction, &str, &str)]) -> AssetMovement {
        AssetMovement {
            legs: legs
                .iter()
                .map(|(direction, amount, asset)| AssetMovementLeg {
                    direction: *direction,
                    amount: (*amount).to_string(),
                    asset: (*asset).to_string(),
                    counterparty: None,
                })
                .collect(),
        }
    }

    fn usdc_out() -> ExpectedAssetMovementLeg {
        ExpectedAssetMovementLeg {
            direction: Direction::Outflow,
            asset: ExpectedAsset::Token {
                mint: "USDCMINT".into(),
                symbol: "USDC".into(),
                decimals: 6,
            },
            amount: ExpectedAmount::Exact(1_500_000),
        }
    }

    // -- EffectCrossCheckTests --

    #[test]
    fn confirmed_when_asset_direction_and_amount_match() {
        // Relay renders 1.5 USDC (display decimal) keyed by the MINT address; expected is 1_500_000 base units.
        let verdict = cross_check_verdict(
            &ExpectedAssetMovement {
                legs: vec![usdc_out()],
            },
            &sim(&[(Direction::Outflow, "1.5", "USDCMINT")]),
        );
        assert_eq!(verdict, CrossCheckVerdict::Confirmed);
    }

    #[test]
    fn confirmed_when_simulated_leg_uses_the_symbol() {
        // The relay leg surfaces the SYMBOL ("USDC") rather than the mint address — the
        // identifier set matches either representation, so this still confirms.
        assert_eq!(
            cross_check_verdict(
                &ExpectedAssetMovement {
                    legs: vec![usdc_out()],
                },
                &sim(&[(Direction::Outflow, "1.5", "USDC")]),
            ),
            CrossCheckVerdict::Confirmed
        );
    }

    #[test]
    fn unconfirmed_when_simulated_assets_cannot_be_canonicalized() {
        // The simulated leg's asset is neither the mint, the symbol, nor SOL: we cannot
        // line the representations up, so fail safe to unconfirmed (never false-contradict).
        assert_eq!(
            cross_check_verdict(
                &ExpectedAssetMovement {
                    legs: vec![usdc_out()],
                },
                &sim(&[(Direction::Outflow, "1.5", "SomeUnrecognizedAccount")]),
            ),
            CrossCheckVerdict::Unconfirmed
        );
    }

    #[test]
    fn unconfirmed_when_simulation_absent() {
        assert_eq!(
            cross_check_verdict(
                &ExpectedAssetMovement {
                    legs: vec![usdc_out()],
                },
                &AssetMovement { legs: vec![] },
            ),
            CrossCheckVerdict::Unconfirmed
        );
    }

    #[test]
    fn unconfirmed_when_asset_unresolved() {
        let leg = ExpectedAssetMovementLeg {
            direction: Direction::Outflow,
            asset: ExpectedAsset::Unresolved,
            amount: ExpectedAmount::Exact(1),
        };
        assert_eq!(
            cross_check_verdict(
                &ExpectedAssetMovement { legs: vec![leg] },
                &sim(&[(Direction::Outflow, "1.5", "USDCMINT")]),
            ),
            CrossCheckVerdict::Unconfirmed
        );
    }

    #[test]
    fn contradicted_wrong_direction_and_wrong_amount() {
        assert_eq!(
            cross_check_verdict(
                &ExpectedAssetMovement {
                    legs: vec![usdc_out()],
                },
                &sim(&[(Direction::Inflow, "1.5", "USDCMINT")]), // wrong direction
            ),
            CrossCheckVerdict::Contradicted
        );
        assert_eq!(
            cross_check_verdict(
                &ExpectedAssetMovement {
                    legs: vec![usdc_out()],
                },
                &sim(&[(Direction::Outflow, "9.0", "USDCMINT")]), // wrong amount
            ),
            CrossCheckVerdict::Contradicted
        );
    }

    #[test]
    fn sol_at_least_and_suffix_parsing() {
        let sol_out = ExpectedAssetMovementLeg {
            direction: Direction::Outflow,
            asset: ExpectedAsset::Sol,
            amount: ExpectedAmount::Exact(2_000_000_000),
        };
        let pool_in = ExpectedAssetMovementLeg {
            direction: Direction::Inflow,
            asset: ExpectedAsset::Token {
                mint: "JITO".into(),
                symbol: "JitoSOL".into(),
                decimals: 9,
            },
            amount: ExpectedAmount::AtLeast(0),
        };
        let verdict = cross_check_verdict(
            &ExpectedAssetMovement {
                legs: vec![sol_out, pool_in],
            },
            &sim(&[
                (Direction::Outflow, "2 SOL", "SOL"),
                (Direction::Inflow, "1.93", "JITO"),
            ]),
        );
        assert_eq!(verdict, CrossCheckVerdict::Confirmed);
    }

    #[test]
    fn at_most_confirms_at_or_below_bound_and_within_tolerance() {
        // Price-limited partial-fill swap: the input leg moves at most the stated amount.
        let input_at_most = ExpectedAssetMovementLeg {
            direction: Direction::Outflow,
            asset: ExpectedAsset::Token {
                mint: "USDCMINT".into(),
                symbol: "USDC".into(),
                decimals: 6,
            },
            amount: ExpectedAmount::AtMost(1_500_000),
        };
        // Below the bound (partial fill), exactly at the bound (full fill), and just within
        // tolerance above the bound (rounding/dust) all confirm.
        for amount in ["1.0", "1.5", "1.5001"] {
            assert_eq!(
                cross_check_verdict(
                    &ExpectedAssetMovement {
                        legs: vec![input_at_most.clone()],
                    },
                    &sim(&[(Direction::Outflow, amount, "USDCMINT")]),
                ),
                CrossCheckVerdict::Confirmed,
                "amount {amount}"
            );
        }
        // Well above the bound contradicts.
        assert_eq!(
            cross_check_verdict(
                &ExpectedAssetMovement {
                    legs: vec![input_at_most],
                },
                &sim(&[(Direction::Outflow, "9.0", "USDCMINT")]),
            ),
            CrossCheckVerdict::Contradicted
        );
    }

    #[test]
    fn conditional_only_checks_applicable_legs() {
        // aToB true: only the A-out / B-in legs are built by the builder, so a simulation
        // that moves A→B confirms even though the spec also declares the !aToB legs.
        let a_out = ExpectedAssetMovementLeg {
            direction: Direction::Outflow,
            asset: ExpectedAsset::Token {
                mint: "A".into(),
                symbol: "TKA".into(),
                decimals: 6,
            },
            amount: ExpectedAmount::Exact(1_000_000),
        };
        let b_in = ExpectedAssetMovementLeg {
            direction: Direction::Inflow,
            asset: ExpectedAsset::Token {
                mint: "B".into(),
                symbol: "TKB".into(),
                decimals: 9,
            },
            amount: ExpectedAmount::AtLeast(950_000_000),
        };
        let verdict = cross_check_verdict(
            &ExpectedAssetMovement {
                legs: vec![a_out, b_in],
            },
            &sim(&[
                (Direction::Outflow, "1", "A"),
                (Direction::Inflow, "0.96", "B"),
            ]),
        );
        assert_eq!(verdict, CrossCheckVerdict::Confirmed);
    }

    #[test]
    fn base_units_scales_fractional_display_amounts_exactly() {
        assert_eq!(base_units("0.25821431", 9), Some(258_214_310));
        assert_eq!(base_units("1.5", 6), Some(1_500_000));
        assert_eq!(base_units("161277 base units", 6), Some(161_277));
        assert_eq!(base_units("not-a-number", 6), None);
    }

    // -- Adversarial relay amounts (fail-safe, no panic under overflow-checks) --

    #[test]
    fn base_units_rejects_negative_and_out_of_range_magnitudes() {
        // A leading '-' is nonsensical for a non-negative relay magnitude:
        // reject rather than let a near-i128::MIN value reach `satisfies`.
        assert_eq!(
            base_units(&format!("{} base units", i128::MIN + 1_500_000), 6),
            None
        );
        assert_eq!(base_units("-1.5", 6), None);
        assert_eq!(
            base_units("-99999999999999999999999999999999999999", 6),
            None
        );
        // A magnitude that overflows i128 fails to parse → None (not a panic).
        assert_eq!(
            base_units("9999999999999999999999999999999999999999 base units", 6),
            None
        );
        // A negative `decimals` is not a coherent scale → None.
        assert_eq!(base_units("1.5", -3), None);
    }

    #[test]
    fn adversarial_min_base_unit_amount_does_not_confirm_or_panic() {
        // A hostile simulated leg reports amount `i128::MIN + V` base units,
        // same direction and matching asset as an Exact(V) expected leg.
        // Pre-fix: base_units returned i128::MIN + V, `(sim - V).abs()`
        // hit .abs() on i128::MIN → panic (debug) / false Confirm (release).
        let amount = format!("{} base units", i128::MIN + 1_500_000);
        let verdict = cross_check_verdict(
            &ExpectedAssetMovement {
                legs: vec![usdc_out()],
            },
            &sim(&[(Direction::Outflow, &amount, "USDCMINT")]),
        );
        assert_ne!(verdict, CrossCheckVerdict::Confirmed);
    }

    #[test]
    fn adversarial_large_negative_decimal_amount_does_not_confirm_or_panic() {
        let verdict = cross_check_verdict(
            &ExpectedAssetMovement {
                legs: vec![usdc_out()],
            },
            &sim(&[(
                Direction::Outflow,
                "-99999999999999999999999999999999999999",
                "USDCMINT",
            )]),
        );
        assert_ne!(verdict, CrossCheckVerdict::Confirmed);
    }

    #[test]
    fn adversarial_huge_positive_amount_does_not_confirm_or_panic() {
        // A representable-but-huge base-unit amount exercises the checked
        // subtraction path with a valid (non-overflowing) large `simulated`.
        let amount = format!("{} base units", i128::MAX);
        let verdict = cross_check_verdict(
            &ExpectedAssetMovement {
                legs: vec![usdc_out()],
            },
            &sim(&[(Direction::Outflow, &amount, "USDCMINT")]),
        );
        assert_ne!(verdict, CrossCheckVerdict::Confirmed);
    }

    #[test]
    fn adversarial_negative_mint_decimals_does_not_confirm_or_panic() {
        // A hostile MintMetadataResponse reports negative decimals; base_units
        // treats it as unresolvable rather than scaling by a nonsense power.
        let leg = ExpectedAssetMovementLeg {
            direction: Direction::Outflow,
            asset: ExpectedAsset::Token {
                mint: "USDCMINT".into(),
                symbol: "USDC".into(),
                decimals: -5,
            },
            amount: ExpectedAmount::Exact(1_500_000),
        };
        let verdict = cross_check_verdict(
            &ExpectedAssetMovement { legs: vec![leg] },
            &sim(&[(Direction::Outflow, "1.5", "USDCMINT")]),
        );
        assert_ne!(verdict, CrossCheckVerdict::Confirmed);
    }

    // -- ExpectedAssetMovementTests --

    fn spec(json: &str) -> DecodeSpec {
        serde_json::from_str(json).unwrap()
    }

    #[test]
    fn builds_single_outflow_from_arg_and_resolved_mint() {
        let decoded = spec(
            r#"{ "program":"P","discriminator":[1],"mode":"standalone","layout":[],"action":"Deposit",
              "accounts":{"src":0},"template":"x",
              "effects":[{"direction":"out","asset":"token(src)","amount":"arg(amt)"}] }"#,
        );
        let args = HashMap::from([("amt".to_string(), DecodedArgValue::Uint(1_500_000))]);
        let accounts = vec!["USDCACC".to_string()];
        let resolved_mints = HashMap::from([(
            "USDCACC".to_string(),
            ResolvedMint {
                mint: "USDCMINT".to_string(),
                decimals: 6,
                symbol: Some("USDC".to_string()),
            },
        )]);
        let movement = build_expected_movement(&decoded, &args, &accounts, &resolved_mints);
        assert_eq!(movement.legs.len(), 1);
        assert_eq!(movement.legs[0].direction, Direction::Outflow);
        assert_eq!(
            movement.legs[0].asset,
            ExpectedAsset::Token {
                mint: "USDCMINT".into(),
                symbol: "USDC".into(),
                decimals: 6
            }
        );
        assert_eq!(movement.legs[0].amount, ExpectedAmount::Exact(1_500_000));
    }

    #[test]
    fn excludes_when_false_effects_and_flips_sol_at_least() {
        let decoded = spec(
            r#"{ "program":"P","discriminator":[14],"mode":"standalone","layout":[],"action":"Stake",
              "accounts":{"poolMint":2},"template":"x",
              "effects":[
                {"direction":"out","asset":"SOL","amount":"arg(lamports)"},
                {"direction":"in","asset":"token(poolMint)","amountAtLeast":"0"},
                {"when":["arg(never)"],"direction":"out","asset":"SOL","amount":"arg(lamports)"}
              ] }"#,
        );
        let args = HashMap::from([("lamports".to_string(), DecodedArgValue::Uint(2_000_000_000))]);
        let accounts = vec!["v".to_string(), "x".to_string(), "POOLMINT".to_string()];
        let resolved_mints = HashMap::from([(
            "POOLMINT".to_string(),
            ResolvedMint {
                mint: "POOLMINT".to_string(),
                decimals: 9,
                symbol: Some("JitoSOL".to_string()),
            },
        )]);
        let movement = build_expected_movement(&decoded, &args, &accounts, &resolved_mints);
        assert_eq!(movement.legs.len(), 2);
        assert_eq!(
            movement.legs[0],
            ExpectedAssetMovementLeg {
                direction: Direction::Outflow,
                asset: ExpectedAsset::Sol,
                amount: ExpectedAmount::Exact(2_000_000_000),
            }
        );
        assert_eq!(
            movement.legs[1].asset,
            ExpectedAsset::Token {
                mint: "POOLMINT".into(),
                symbol: "JitoSOL".into(),
                decimals: 9
            }
        );
        assert_eq!(movement.legs[1].amount, ExpectedAmount::AtLeast(0));
    }

    #[test]
    fn amount_at_most_resolves_from_arg_and_literal() {
        let decoded = spec(
            r#"{ "program":"P","discriminator":[1],"mode":"standalone","layout":[],"action":"Swap",
              "accounts":{"src":0,"dst":1},"template":"x",
              "effects":[
                {"direction":"out","asset":"token(src)","amountAtMost":"arg(maxIn)"},
                {"direction":"in","asset":"token(dst)","amountAtMost":"0"}
              ] }"#,
        );
        let args = HashMap::from([("maxIn".to_string(), DecodedArgValue::Uint(1_500_000))]);
        let accounts = vec!["USDCACC".to_string(), "SOLACC".to_string()];
        let resolved_mints = HashMap::from([
            (
                "USDCACC".to_string(),
                ResolvedMint {
                    mint: "USDCMINT".to_string(),
                    decimals: 6,
                    symbol: Some("USDC".to_string()),
                },
            ),
            (
                "SOLACC".to_string(),
                ResolvedMint {
                    mint: "SOLMINT".to_string(),
                    decimals: 9,
                    symbol: Some("SOL".to_string()),
                },
            ),
        ]);
        let movement = build_expected_movement(&decoded, &args, &accounts, &resolved_mints);
        assert_eq!(movement.legs.len(), 2);
        assert_eq!(movement.legs[0].amount, ExpectedAmount::AtMost(1_500_000));
        assert_eq!(movement.legs[1].amount, ExpectedAmount::AtMost(0));
    }

    #[test]
    fn unresolved_mint_and_missing_arg_degrade_gracefully() {
        let decoded = spec(
            r#"{ "program":"P","discriminator":[1],"mode":"standalone","layout":[],"action":"Deposit",
              "accounts":{"src":0},"template":"x",
              "effects":[{"direction":"out","asset":"token(src)","amount":"arg(missing)"}] }"#,
        );
        let movement = build_expected_movement(
            &decoded,
            &HashMap::new(),
            &["ACC".to_string()],
            &HashMap::new(),
        );
        assert_eq!(movement.legs[0].asset, ExpectedAsset::Unresolved);
        assert_eq!(movement.legs[0].amount, ExpectedAmount::Unresolved);
    }
}
