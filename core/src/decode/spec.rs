//! Tier-3 decode-spec model: the JSON shape of the bundled decode-spec
//! registry (`registry/specs/*.json`). Field-for-field port of the model
//! half of `Modules/Indexer/Sources/DecodeSpec.swift` — parsing only, no
//! interpretation. Tasks 8 and 10 append the template renderer and effect
//! interpreter to this same file.

use std::collections::HashMap;

use serde::{Deserialize, Deserializer};

use super::borsh::{DecodedArgValue, decode_arguments};
use super::crosscheck::{CrossCheckContext, build_expected_movement, cross_check_verdict};
use super::idl::{AnchorIdlType, ResolvedProgramIdl};
use super::primitives::{bytes_from_hex, decimal_amount, short_address, sol_amount};
use super::{DecodeProvenance, DecodedInstructionDisplay};
use crate::types::DecodedInstruction;

/// Whether a spec's fields are read off a resolved on-chain Anchor IDL
/// (`BindIdl`) or off its own `layout` (`Standalone`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum SpecMode {
    BindIdl,
    Standalone,
}

/// An [`Effect`]'s asset-flow direction, relative to the squad. Distinct
/// from `wire::Direction`, which is the relay's own inflow/outflow model —
/// this is the decode-spec JSON's `in`/`out` vocabulary.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SpecDirection {
    Out,
    In,
}

/// One `{name, type}` entry from a standalone spec's `layout` array.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SpecField {
    pub name: String,
    pub field_type: AnchorIdlType,
}

impl<'de> Deserialize<'de> for SpecField {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        struct Raw {
            name: String,
            #[serde(rename = "type")]
            field_type: serde_json::Value,
        }
        let raw = Raw::deserialize(deserializer)?;
        Ok(SpecField {
            name: raw.name,
            field_type: AnchorIdlType::from_type_json(&raw.field_type),
        })
    }
}

/// One rendering rule for a spec's `template`: `text`, shown when every
/// condition in `when` holds (an empty `when` is unconditional).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TemplateVariant {
    pub when: Vec<String>,
    pub text: String,
}

/// One expected asset movement a spec's instruction should produce, used to
/// cross-check the decode against the relay's simulated effects.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Effect {
    #[serde(default)]
    pub when: Vec<String>,
    pub direction: SpecDirection,
    pub asset: String,
    #[serde(default)]
    pub amount: Option<String>,
    #[serde(default)]
    pub amount_at_least: Option<String>,
    #[serde(default)]
    pub amount_at_most: Option<String>,
}

/// One entry from the bundled decode-spec registry: how to recognize an
/// instruction by `program` + `discriminator`, render a human-readable
/// summary from its `template`, and cross-check its `effects`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecodeSpec {
    pub program: String,
    pub discriminator: Vec<u8>,
    pub mode: SpecMode,
    pub binds_idl_hash: Option<String>,
    pub layout: Option<Vec<SpecField>>,
    pub action: String,
    /// Account role name → index into the instruction's accounts list.
    /// `i64`, not `usize`: the renderer/interpreter bounds-check this index
    /// against the accounts slice, so a negative or out-of-range value
    /// safely resolves to unresolved rather than panicking or wrapping.
    pub accounts: HashMap<String, i64>,
    pub template: Vec<TemplateVariant>,
    pub effects: Vec<Effect>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawDecodeSpec {
    program: String,
    discriminator: Vec<u8>,
    mode: SpecMode,
    #[serde(default)]
    binds_idl_hash: Option<String>,
    #[serde(default)]
    layout: Option<Vec<SpecField>>,
    action: String,
    accounts: HashMap<String, i64>,
    template: RawTemplate,
    effects: Vec<Effect>,
}

/// The `template` field is polymorphic: either a single JSON string (one
/// unconditional variant) or an array of `{when?, text}` objects.
#[derive(Deserialize)]
#[serde(untagged)]
enum RawTemplate {
    Text(String),
    Variants(Vec<RawTemplateVariant>),
}

#[derive(Deserialize)]
struct RawTemplateVariant {
    #[serde(default)]
    when: Vec<String>,
    text: String,
}

impl<'de> Deserialize<'de> for DecodeSpec {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let raw = RawDecodeSpec::deserialize(deserializer)?;
        let template = match raw.template {
            RawTemplate::Text(text) => vec![TemplateVariant {
                when: Vec::new(),
                text,
            }],
            RawTemplate::Variants(variants) => variants
                .into_iter()
                .map(|variant| TemplateVariant {
                    when: variant.when,
                    text: variant.text,
                })
                .collect(),
        };

        Ok(DecodeSpec {
            program: raw.program,
            discriminator: raw.discriminator,
            mode: raw.mode,
            binds_idl_hash: raw.binds_idl_hash,
            layout: raw.layout,
            action: raw.action,
            accounts: raw.accounts,
            template,
            effects: raw.effects,
        })
    }
}

/// A resolved SPL mint's ticker symbol and decimal precision, keyed by mint
/// address in the renderer's `mints` map. `decimals` is `i64` (not `u8`)
/// because it is read from external/simulated mint data that must never be
/// trusted to be in-range before rendering.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MintInfo {
    pub symbol: String,
    pub decimals: i64,
}

/// Evaluates a spec's `when` literal list — each literal is `arg(NAME)` or
/// `!arg(NAME)` — against decoded instruction args. Holds only when every
/// literal is well-formed AND its referenced arg is a genuinely-decoded
/// [`DecodedArgValue::Bool`] matching the requested polarity. A missing arg,
/// or one decoded as a non-bool type, fails the predicate for BOTH
/// `arg(x)` and `!arg(x)` — a wrong-typed arg must never be coerced into
/// selecting either branch of a conditional template. An empty `literals`
/// list holds unconditionally.
pub fn when_predicate_holds(literals: &[String], args: &HashMap<String, DecodedArgValue>) -> bool {
    for literal in literals {
        let negated = literal.starts_with('!');
        let inner = if negated {
            &literal[1..]
        } else {
            literal.as_str()
        };
        if !(inner.starts_with("arg(") && inner.ends_with(')')) {
            return false;
        }
        let name = &inner[4..inner.len() - 1];
        let Some(DecodedArgValue::Bool(flag)) = args.get(name) else {
            return false;
        };
        if *flag == negated {
            return false;
        }
    }
    true
}

/// Renders a spec's `template`: picks the first variant whose `when` holds
/// (`None` if no variant matches) and interpolates its `text`.
pub fn render_template(
    variants: &[TemplateVariant],
    args: &HashMap<String, DecodedArgValue>,
    accounts: &[String],
    role_indexes: &HashMap<String, i64>,
    mints: &HashMap<String, MintInfo>,
) -> Option<String> {
    let variant = variants
        .iter()
        .find(|variant| when_predicate_holds(&variant.when, args))?;
    Some(interpolate(
        &variant.text,
        args,
        accounts,
        role_indexes,
        mints,
    ))
}

/// Scans `text` for `{token}` placeholders and replaces each with
/// `resolve`'s output. An unterminated `{` (no matching `}`) is the
/// crash-guard case: the rest of the string is appended verbatim rather
/// than treated as a token.
fn interpolate(
    text: &str,
    args: &HashMap<String, DecodedArgValue>,
    accounts: &[String],
    role_indexes: &HashMap<String, i64>,
    mints: &HashMap<String, MintInfo>,
) -> String {
    let mut result = String::new();
    let mut rest = text;
    while let Some(open) = rest.find('{') {
        result.push_str(&rest[..open]);
        let after_open = &rest[open + 1..];
        let Some(close) = after_open.find('}') else {
            result.push_str(&rest[open..]);
            return result;
        };
        let token = &after_open[..close];
        result.push_str(&resolve(token, args, accounts, role_indexes, mints));
        rest = &after_open[close + 1..];
    }
    result.push_str(rest);
    result
}

/// Splits `token` on its first `:` the same way Swift's
/// `token.split(separator: ":", maxSplits: 1)` does: leading colons (and an
/// all-colon or empty token) produce no leading empty piece, and once the
/// one allowed split is used the remainder is returned whole (including any
/// further colons) unless it is empty, in which case it is dropped. This
/// governs the `{}` / `{:}` crash guard: both yield no pieces at all.
fn split_first_colon(token: &str) -> Vec<&str> {
    let stripped = token.trim_start_matches(':');
    if stripped.is_empty() {
        return Vec::new();
    }
    match stripped.find(':') {
        None => vec![stripped],
        Some(index) => {
            let lhs = &stripped[..index];
            let rhs = &stripped[index + 1..];
            if rhs.is_empty() {
                vec![lhs]
            } else {
                vec![lhs, rhs]
            }
        }
    }
}

/// Resolves one `{token}` placeholder to its rendered string. A token with
/// no left-hand side (from `split_first_colon` returning nothing, i.e. an
/// empty or colon-only token) fails open to `"?"` rather than indexing into
/// an empty slice.
fn resolve(
    token: &str,
    args: &HashMap<String, DecodedArgValue>,
    accounts: &[String],
    role_indexes: &HashMap<String, i64>,
    mints: &HashMap<String, MintInfo>,
) -> String {
    let parts = split_first_colon(token);
    let Some(&lhs) = parts.first() else {
        return "?".to_string();
    };
    let formatter = parts.get(1).copied().unwrap_or("");

    if formatter == "token" {
        return mint_symbol(lhs, accounts, role_indexes, mints);
    }
    if formatter == "sol" {
        return render_sol_amount(args.get(lhs).copied());
    }
    if let Some(role) = formatter
        .strip_prefix("token(")
        .and_then(|rest| rest.strip_suffix(')'))
    {
        return render_token_amount(args.get(lhs).copied(), role, accounts, role_indexes, mints);
    }
    args.get(lhs)
        .and_then(DecodedArgValue::rendered)
        .unwrap_or_else(|| "?".to_string())
}

/// Resolves a spec's account `role` to its address and (if known) mint
/// info. Fails open to `("?", None)` when the role is unmapped or the
/// mapped index is out of bounds for `accounts` — never a wrong account,
/// never a panic on attacker-influenceable indices.
fn resolve_mint<'a>(
    role: &str,
    accounts: &[String],
    role_indexes: &HashMap<String, i64>,
    mints: &'a HashMap<String, MintInfo>,
) -> (String, Option<&'a MintInfo>) {
    let Some(&index) = role_indexes.get(role) else {
        return ("?".to_string(), None);
    };
    if index < 0 || index as usize >= accounts.len() {
        return ("?".to_string(), None);
    }
    let address = accounts[index as usize].clone();
    let info = mints.get(&address);
    (address, info)
}

/// The `{role:token}` formatter: the mint's ticker symbol, or the mint
/// address shortened when the mint isn't in the resolved-mints map.
fn mint_symbol(
    role: &str,
    accounts: &[String],
    role_indexes: &HashMap<String, i64>,
    mints: &HashMap<String, MintInfo>,
) -> String {
    let (address, info) = resolve_mint(role, accounts, role_indexes, mints);
    match info {
        Some(info) => info.symbol.clone(),
        None => short_address(&address),
    }
}

/// The `{arg:token(role)}` formatter. A non-`Uint` arg falls open to its own
/// `rendered()` (or `"?"`). An unresolved mint falls open to the raw base
/// units alongside the shortened mint address. `MintInfo.decimals` is
/// clamped to `[0, 255]` before it reaches `decimal_amount`'s `u8`
/// parameter — external mint data must never trap on an out-of-range value.
fn render_token_amount(
    value: Option<DecodedArgValue>,
    role: &str,
    accounts: &[String],
    role_indexes: &HashMap<String, i64>,
    mints: &HashMap<String, MintInfo>,
) -> String {
    let Some(DecodedArgValue::Uint(raw)) = value else {
        return value
            .and_then(|value| value.rendered())
            .unwrap_or_else(|| "?".to_string());
    };
    let (address, info) = resolve_mint(role, accounts, role_indexes, mints);
    match info {
        None => format!("{raw} ({})", short_address(&address)),
        Some(info) => {
            let decimals = info.decimals.clamp(0, 255) as u8;
            format!("{} {}", decimal_amount(raw, decimals), info.symbol)
        }
    }
}

/// The `{arg:sol}` formatter. A non-`Uint` arg falls open to its own
/// `rendered()` (or `"?"`).
fn render_sol_amount(value: Option<DecodedArgValue>) -> String {
    match value {
        Some(DecodedArgValue::Uint(lamports)) => sol_amount(lamports),
        other => other
            .and_then(|value| value.rendered())
            .unwrap_or_else(|| "?".to_string()),
    }
}

/// Names referenced by `{name}` / `{name:sol}` / `{name:token(role)}` tokens
/// in a template variant's text — the args the M1 guard in [`interpret_spec`]
/// requires to be present before rendering. A `{role:token}` token
/// (formatter exactly `"token"`) names an account role, not a decoded arg,
/// so it is excluded. An unterminated `{` (no matching `}`) stops scanning
/// rather than misreading the remainder of the text as a token.
fn referenced_arg_names(text: &str) -> Vec<String> {
    let mut names = Vec::new();
    let mut rest = text;
    while let Some(open) = rest.find('{') {
        let after_open = &rest[open + 1..];
        let Some(close) = after_open.find('}') else {
            break;
        };
        let token = &after_open[..close];
        let mut parts = token.splitn(2, ':');
        let lhs = parts.next().unwrap_or("");
        let formatter = parts.next();
        if formatter != Some("token") {
            names.push(lhs.to_string());
        }
        rest = &after_open[close + 1..];
    }
    names
}

/// Selects a bind-idl spec's decode fields from the matching instruction on
/// `resolved_idl`'s document, enforcing the hash pin: the IDL must carry
/// `OnChainIdl` provenance whose `hash` equals `spec.binds_idl_hash`
/// exactly. A spec bound to a since-drifted on-chain IDL (program upgraded,
/// discriminator preserved) must never render against a layout its author
/// never validated against — any failure here (no IDL, wrong provenance,
/// unpinned/mismatched hash, no matching instruction) drops the spec
/// entirely rather than guessing.
fn bind_idl_fields(
    spec: &DecodeSpec,
    resolved_idl: Option<&ResolvedProgramIdl>,
) -> Option<Vec<(String, AnchorIdlType)>> {
    let resolved_idl = resolved_idl?;
    let DecodeProvenance::OnChainIdl { hash, .. } = &resolved_idl.provenance else {
        return None;
    };
    if spec.binds_idl_hash.as_deref() != Some(hash.as_str()) {
        return None;
    }
    let matched = resolved_idl
        .document
        .instructions
        .iter()
        .find(|instruction| instruction.discriminator == spec.discriminator)?;
    Some(
        matched
            .arguments
            .iter()
            .map(|argument| (argument.name.clone(), argument.arg_type))
            .collect(),
    )
}

/// Selects a spec's decode fields by mode: `Standalone` reads its own
/// `layout` (an absent layout is treated as empty); `BindIdl` requires the
/// hash-pinned on-chain IDL match (see [`bind_idl_fields`]).
fn fields_for_spec(
    spec: &DecodeSpec,
    resolved_idl: Option<&ResolvedProgramIdl>,
) -> Option<Vec<(String, AnchorIdlType)>> {
    match spec.mode {
        SpecMode::Standalone => Some(
            spec.layout
                .as_deref()
                .unwrap_or(&[])
                .iter()
                .map(|field| (field.name.clone(), field.field_type))
                .collect(),
        ),
        SpecMode::BindIdl => bind_idl_fields(spec, resolved_idl),
    }
}

/// Interprets `instruction` against a tier-3 decode spec: the trust-critical
/// step that renders the action statement + cross-check verdict a human
/// signs against. Field-for-field port of `DecodeSpecInterpreter.interpret`.
///
/// Every failure mode falls through to `None` (tier-2/raw) rather than risk
/// a wrong or partial statement: an empty discriminator (which would
/// otherwise match every instruction of a program), a byte-count or prefix
/// mismatch against the raw data, a bind-idl spec whose `binds_idl_hash`
/// doesn't pin the resolved IDL's hash exactly, and the M1 guard — the
/// chosen template variant's referenced args must ALL be genuinely decoded
/// before rendering, so a short or misaligned buffer never surfaces a `"?"`
/// at registry provenance.
pub fn interpret_spec(
    instruction: &DecodedInstruction,
    spec: &DecodeSpec,
    resolved_idl: Option<&ResolvedProgramIdl>,
    accounts: &[String],
    mints: &HashMap<String, MintInfo>,
    cross_check: Option<&CrossCheckContext>,
) -> Option<DecodedInstructionDisplay> {
    if spec.discriminator.is_empty() {
        return None;
    }

    let bytes = bytes_from_hex(&instruction.raw_data_hex)?;
    let disc_len = spec.discriminator.len();
    if bytes.len() < disc_len || bytes[..disc_len] != spec.discriminator[..] {
        return None;
    }

    let fields = fields_for_spec(spec, resolved_idl)?;
    let args = decode_arguments(&bytes, disc_len, &fields);

    // M1: the chosen variant's referenced args must all be present, else fall through.
    let variant = spec
        .template
        .iter()
        .find(|variant| when_predicate_holds(&variant.when, &args))?;
    if !referenced_arg_names(&variant.text)
        .iter()
        .all(|name| args.contains_key(name))
    {
        return None;
    }
    let statement = render_template(&spec.template, &args, accounts, &spec.accounts, mints)?;

    let verdict = cross_check.map(|context| {
        let expected = build_expected_movement(spec, &args, accounts, &context.resolved_mints);
        cross_check_verdict(&expected, &context.simulated)
    });

    let resolved_name = resolved_idl
        .map(|resolved| resolved.document.name.clone())
        .filter(|name| !name.is_empty());
    let bound_program = if spec.mode == SpecMode::BindIdl {
        resolved_name.clone()
    } else {
        None
    };
    let program_label = resolved_name.unwrap_or_else(|| short_address(&instruction.program));

    Some(DecodedInstructionDisplay {
        program_label,
        kind: spec.action.clone(),
        summary: statement,
        accounts: accounts.to_vec(),
        data_hex: instruction.raw_data_hex.clone(),
        provenance: Some(DecodeProvenance::Registry {
            action: spec.action.clone(),
            source: "Cosign".to_string(),
            bound_program,
        }),
        cross_check: verdict,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::decode::idl::AnchorIdlType;

    fn spec(json: &str) -> DecodeSpec {
        serde_json::from_str(json).unwrap()
    }

    #[test]
    fn parses_string_template_as_single_unconditional_variant() {
        let s = spec(
            r#"{"program":"P","discriminator":[14],"mode":"standalone",
          "layout":[{"name":"lamports","type":"u64"}],"action":"Stake","accounts":{"vault":0},
          "template":"Stake {lamports:sol}","effects":[]}"#,
        );
        assert_eq!(s.mode, SpecMode::Standalone);
        assert_eq!(s.discriminator, vec![14]);
        assert_eq!(s.template.len(), 1);
        assert!(s.template[0].when.is_empty());
        assert_eq!(s.template[0].text, "Stake {lamports:sol}");
        assert_eq!(s.layout.as_ref().unwrap()[0].field_type, AnchorIdlType::U64);
        assert_eq!(s.accounts["vault"], 0);
    }

    #[test]
    fn parses_array_template_with_conditions() {
        let s = spec(
            r#"{"program":"P","discriminator":[248],"mode":"bind-idl","bindsIdlHash":"h",
          "action":"Swap","accounts":{"a":3},
          "template":[{"when":["arg(a_to_b)"],"text":"A to B"},{"text":"B to A"}],
          "effects":[{"when":["arg(a_to_b)"],"direction":"out","asset":"token(a)","amountAtMost":"arg(amount)"}]}"#,
        );
        assert_eq!(s.mode, SpecMode::BindIdl);
        assert_eq!(s.binds_idl_hash.as_deref(), Some("h"));
        assert_eq!(s.template.len(), 2);
        assert_eq!(s.template[0].when, vec!["arg(a_to_b)".to_string()]);
        assert!(s.template[1].when.is_empty());
        assert_eq!(s.effects[0].direction, SpecDirection::Out);
        assert_eq!(s.effects[0].amount_at_most.as_deref(), Some("arg(amount)"));
    }

    #[test]
    fn parses_all_four_committed_golden_specs() {
        for name in [
            "kamino-deposit",
            "orca-swap",
            "raydium-swap",
            "stakepool-depositsol",
        ] {
            let path = format!("registry/specs/{name}.json");
            let json = std::fs::read_to_string(&path).unwrap_or_else(|_| panic!("read {path}"));
            let s: DecodeSpec =
                serde_json::from_str(&json).unwrap_or_else(|e| panic!("parse {name}: {e}"));
            assert!(!s.discriminator.is_empty());
            assert!(!s.template.is_empty());
        }
    }
}

#[cfg(test)]
mod rendering_tests {
    use super::*;
    use crate::decode::borsh::DecodedArgValue;
    use std::collections::HashMap;

    fn args(pairs: &[(&str, DecodedArgValue)]) -> HashMap<String, DecodedArgValue> {
        pairs.iter().map(|(k, v)| (k.to_string(), *v)).collect()
    }
    fn variant(when: &[&str], text: &str) -> TemplateVariant {
        TemplateVariant {
            when: when.iter().map(|s| s.to_string()).collect(),
            text: text.into(),
        }
    }
    fn roles(pairs: &[(&str, i64)]) -> HashMap<String, i64> {
        pairs.iter().map(|(k, v)| (k.to_string(), *v)).collect()
    }
    fn mints(pairs: &[(&str, &str, i64)]) -> HashMap<String, MintInfo> {
        pairs
            .iter()
            .map(|(a, sym, d)| {
                (
                    a.to_string(),
                    MintInfo {
                        symbol: sym.to_string(),
                        decimals: *d,
                    },
                )
            })
            .collect()
    }

    #[test]
    fn predicate_holds_for_matching_bools() {
        let a = args(&[
            ("aToB", DecodedArgValue::Bool(true)),
            ("x", DecodedArgValue::Bool(false)),
        ]);
        assert!(when_predicate_holds(&[], &a));
        assert!(when_predicate_holds(&["arg(aToB)".into()], &a));
        assert!(when_predicate_holds(&["!arg(x)".into()], &a));
        assert!(when_predicate_holds(
            &["arg(aToB)".into(), "!arg(x)".into()],
            &a
        ));
        assert!(!when_predicate_holds(&["!arg(aToB)".into()], &a));
        assert!(!when_predicate_holds(&["arg(missing)".into()], &a));
    }

    #[test]
    fn non_bool_when_arg_selects_no_variant_regardless_of_negation() {
        let v = [
            variant(&["arg(side)"], "A to B"),
            variant(&["!arg(side)"], "B to A"),
        ];
        assert_eq!(
            render_template(
                &v,
                &args(&[("side", DecodedArgValue::Uint(1))]),
                &[],
                &roles(&[]),
                &mints(&[])
            ),
            None
        );
        assert_eq!(
            render_template(
                &v,
                &args(&[("side", DecodedArgValue::Uint(0))]),
                &[],
                &roles(&[]),
                &mints(&[])
            ),
            None
        );
    }

    #[test]
    fn selects_conditional_variant() {
        let v = [
            variant(&["arg(aToB)"], "A to B"),
            variant(&["!arg(aToB)"], "B to A"),
        ];
        assert_eq!(
            render_template(
                &v,
                &args(&[("aToB", DecodedArgValue::Bool(false))]),
                &[],
                &roles(&[]),
                &mints(&[])
            )
            .as_deref(),
            Some("B to A")
        );
    }

    #[test]
    fn renders_token_amount_when_mint_resolved() {
        let out = render_template(
            &[variant(&[], "Deposit {amount:token(mint)}")],
            &args(&[("amount", DecodedArgValue::Uint(1_000_000))]),
            &["prog".into(), "MINTADDR".into()],
            &roles(&[("mint", 1)]),
            &mints(&[("MINTADDR", "USDC", 6)]),
        );
        assert_eq!(out.as_deref(), Some("Deposit 1 USDC"));
    }

    #[test]
    fn fails_open_to_raw_when_mint_unresolved() {
        let out = render_template(
            &[variant(&[], "Deposit {amount:token(mint)}")],
            &args(&[("amount", DecodedArgValue::Uint(1_000_000))]),
            &[
                "prog".into(),
                "SoMeLongMintAddress1111111111111111111111111".into(),
            ],
            &roles(&[("mint", 1)]),
            &mints(&[]),
        );
        assert!(out.unwrap().contains("1000000"));
    }

    #[test]
    fn renders_sol_and_raw_arg() {
        assert_eq!(
            render_template(
                &[variant(&[], "Stake {lamports:sol}")],
                &args(&[("lamports", DecodedArgValue::Uint(2_000_000_000))]),
                &[],
                &roles(&[]),
                &mints(&[])
            )
            .as_deref(),
            Some("Stake 2 SOL")
        );
        assert_eq!(
            render_template(
                &[variant(&[], "n={count}")],
                &args(&[("count", DecodedArgValue::Uint(3))]),
                &[],
                &roles(&[]),
                &mints(&[])
            )
            .as_deref(),
            Some("n=3")
        );
    }

    #[test]
    fn negative_decimals_fail_open_without_panicking() {
        let out = render_template(
            &[variant(&[], "Deposit {amount:token(mint)}")],
            &args(&[("amount", DecodedArgValue::Uint(5))]),
            &["prog".into(), "MINTX".into()],
            &roles(&[("mint", 1)]),
            &mints(&[("MINTX", "X", -5)]),
        );
        assert_eq!(out.as_deref(), Some("Deposit 5 X"));
    }

    #[test]
    fn empty_or_colon_only_token_fails_open() {
        assert_eq!(
            render_template(
                &[variant(&[], "Send {} now")],
                &args(&[]),
                &[],
                &roles(&[]),
                &mints(&[])
            )
            .as_deref(),
            Some("Send ? now")
        );
        assert_eq!(
            render_template(
                &[variant(&[], "x {:} y")],
                &args(&[]),
                &[],
                &roles(&[]),
                &mints(&[])
            )
            .as_deref(),
            Some("x ? y")
        );
    }

    #[test]
    fn renders_mint_symbol_for_role_token_formatter() {
        let out = render_template(
            &[variant(&[], "pool {poolMint:token}")],
            &args(&[]),
            &["prog".into(), "MINTY".into()],
            &roles(&[("poolMint", 1)]),
            &mints(&[("MINTY", "mSOL", 9)]),
        );
        assert_eq!(out.as_deref(), Some("pool mSOL"));
    }
}

#[cfg(test)]
mod interpreter_tests {
    use super::*;
    use crate::decode::idl::{
        AnchorIdlArgument, AnchorIdlDocument, AnchorIdlInstruction, ResolvedProgramIdl,
    };
    use crate::decode::mints::ResolvedMint;
    use crate::decode::wire::{AssetMovement, AssetMovementLeg, Direction};
    use crate::decode::{CrossCheckContext, CrossCheckVerdict, DecodeProvenance};
    use crate::types::DecodedInstruction;
    use std::collections::HashMap;

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

    fn spec(json: &str) -> DecodeSpec {
        serde_json::from_str(json).unwrap()
    }

    /// A single-instruction ("deposit") IDL document, named `name`, used by
    /// the bind-idl tests below.
    fn deposit_idl(name: &str) -> AnchorIdlDocument {
        AnchorIdlDocument {
            name: name.to_string(),
            instructions: vec![AnchorIdlInstruction {
                name: "deposit".into(),
                discriminator: vec![1, 2, 3, 4, 5, 6, 7, 8],
                arguments: vec![AnchorIdlArgument {
                    name: "amount".into(),
                    arg_type: AnchorIdlType::U64,
                }],
            }],
        }
    }

    fn resolved(document: AnchorIdlDocument, hash: &str) -> ResolvedProgramIdl {
        let idl_name = document.name.clone();
        ResolvedProgramIdl {
            document,
            provenance: DecodeProvenance::OnChainIdl {
                idl_name,
                hash: hash.into(),
                slot: 1,
            },
        }
    }

    fn stake_spec() -> DecodeSpec {
        spec(
            r#"{"program":"SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy","discriminator":[14],"mode":"standalone",
          "layout":[{"name":"lamports","type":"u64"}],"action":"Stake","accounts":{"vault":0,"poolMint":2},
          "template":"Stake {lamports:sol}",
          "effects":[{"direction":"out","asset":"SOL","amount":"arg(lamports)"},{"direction":"in","asset":"token(poolMint)","amountAtLeast":"0"}]}"#,
        )
    }

    #[test]
    fn interprets_standalone_spec() {
        let s = spec(
            r#"{"program":"SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy","discriminator":[14],"mode":"standalone",
          "layout":[{"name":"lamports","type":"u64"}],"action":"Stake","accounts":{"vault":0},
          "template":"Stake {lamports:sol}","effects":[]}"#,
        );
        let d = interpret_spec(
            &ix(
                "SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy",
                "0e0094357700000000",
            ),
            &s,
            None,
            &["vaultAddr".into()],
            &HashMap::new(),
            None,
        )
        .unwrap();
        assert_eq!(d.kind, "Stake");
        assert_eq!(d.summary, "Stake 2 SOL");
        assert!(
            matches!(d.provenance, Some(DecodeProvenance::Registry { ref action, ref bound_program, .. }) if action == "Stake" && bound_program.is_none())
        );
    }

    #[test]
    fn interprets_bind_idl_spec_using_idl_args() {
        let resolved_idl = resolved(deposit_idl("kamino"), "h");
        let s = spec(
            r#"{"program":"K","discriminator":[1,2,3,4,5,6,7,8],"mode":"bind-idl","bindsIdlHash":"h",
          "action":"Deposit","accounts":{},"template":"Deposit {amount}","effects":[]}"#,
        );
        let d = interpret_spec(
            &ix("K", "010203040506070840420f0000000000"),
            &s,
            Some(&resolved_idl),
            &[],
            &HashMap::new(),
            None,
        )
        .unwrap();
        assert_eq!(d.summary, "Deposit 1000000");
        assert_eq!(d.kind, "Deposit");
    }

    #[test]
    fn bind_idl_with_empty_name_falls_back_to_short_address() {
        let resolved_idl = resolved(deposit_idl(""), "h");
        let s = spec(
            r#"{"program":"K","discriminator":[1,2,3,4,5,6,7,8],"mode":"bind-idl","bindsIdlHash":"h",
          "action":"Deposit","accounts":{},"template":"Deposit {amount}","effects":[]}"#,
        );
        let program = "SoMeLongProgramAddress111111111111111111111";
        let d = interpret_spec(
            &ix(program, "010203040506070840420f0000000000"),
            &s,
            Some(&resolved_idl),
            &[],
            &HashMap::new(),
            None,
        )
        .unwrap();
        assert_eq!(d.program_label, short_address(program));
        assert!(!d.program_label.is_empty());
        assert!(
            matches!(d.provenance, Some(DecodeProvenance::Registry { ref bound_program, .. }) if bound_program.is_none())
        );
    }

    #[test]
    fn bind_idl_drops_spec_when_hash_mismatch() {
        let resolved_idl = resolved(deposit_idl("kamino"), "h");
        let s = spec(
            r#"{"program":"K","discriminator":[1,2,3,4,5,6,7,8],"mode":"bind-idl","bindsIdlHash":"stale",
          "action":"Deposit","accounts":{},"template":"Deposit {amount}","effects":[]}"#,
        );
        assert!(
            interpret_spec(
                &ix("K", "010203040506070840420f0000000000"),
                &s,
                Some(&resolved_idl),
                &[],
                &HashMap::new(),
                None,
            )
            .is_none()
        );
    }

    #[test]
    fn empty_discriminator_never_matches() {
        let s = spec(
            r#"{"program":"P","discriminator":[],"mode":"standalone","layout":[],
          "action":"X","accounts":{},"template":"x","effects":[]}"#,
        );
        assert!(interpret_spec(&ix("P", "0e"), &s, None, &[], &HashMap::new(), None).is_none());
    }

    #[test]
    fn returns_none_when_discriminator_does_not_match() {
        let s = spec(
            r#"{"program":"P","discriminator":[99],"mode":"standalone","layout":[],
          "action":"X","accounts":{},"template":"x","effects":[]}"#,
        );
        assert!(interpret_spec(&ix("P", "0e"), &s, None, &[], &HashMap::new(), None).is_none());
    }

    #[test]
    fn m1_partial_arg_falls_through() {
        let s = spec(
            r#"{"program":"P","discriminator":[14],"mode":"standalone",
          "layout":[{"name":"amount","type":"u64"}],"action":"X","accounts":{},"template":"Send {amount}","effects":[]}"#,
        );
        assert!(interpret_spec(&ix("P", "0e"), &s, None, &[], &HashMap::new(), None).is_none());
    }

    #[test]
    fn confirmed_verdict_is_carried() {
        let ctx = CrossCheckContext {
            simulated: AssetMovement {
                legs: vec![
                    AssetMovementLeg {
                        direction: Direction::Outflow,
                        amount: "2 SOL".into(),
                        asset: "SOL".into(),
                        counterparty: None,
                    },
                    AssetMovementLeg {
                        direction: Direction::Inflow,
                        amount: "1.9".into(),
                        asset: "POOLMINT".into(),
                        counterparty: None,
                    },
                ],
            },
            resolved_mints: [(
                "POOLMINTACC".to_string(),
                ResolvedMint {
                    mint: "POOLMINT".into(),
                    decimals: 9,
                    symbol: Some("JitoSOL".into()),
                },
            )]
            .into_iter()
            .collect(),
        };
        let d = interpret_spec(
            &ix(
                "SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy",
                "0e0094357700000000",
            ),
            &stake_spec(),
            None,
            &["vaultAddr".into(), "x".into(), "POOLMINTACC".into()],
            &HashMap::new(),
            Some(&ctx),
        )
        .unwrap();
        assert_eq!(d.summary, "Stake 2 SOL");
        assert_eq!(d.cross_check, Some(CrossCheckVerdict::Confirmed));
    }

    #[test]
    fn contradicted_verdict_is_carried() {
        let ctx = CrossCheckContext {
            simulated: AssetMovement {
                legs: vec![AssetMovementLeg {
                    direction: Direction::Outflow,
                    amount: "9 SOL".into(),
                    asset: "SOL".into(),
                    counterparty: None,
                }],
            },
            resolved_mints: HashMap::new(),
        };
        let d = interpret_spec(
            &ix(
                "SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy",
                "0e0094357700000000",
            ),
            &stake_spec(),
            None,
            &["vaultAddr".into(), "x".into(), "POOLMINTACC".into()],
            &HashMap::new(),
            Some(&ctx),
        )
        .unwrap();
        assert_eq!(d.cross_check, Some(CrossCheckVerdict::Contradicted));
    }

    #[test]
    fn no_context_leaves_verdict_nil() {
        let d = interpret_spec(
            &ix(
                "SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy",
                "0e0094357700000000",
            ),
            &stake_spec(),
            None,
            &["vaultAddr".into(), "x".into(), "POOLMINTACC".into()],
            &HashMap::new(),
            None,
        )
        .unwrap();
        assert_eq!(d.cross_check, None);
    }

    #[test]
    fn referenced_arg_names_excludes_role_token_formatter_but_includes_others() {
        assert_eq!(
            referenced_arg_names(
                "Stake {lamports:sol}, pool {poolMint:token}, raw {count}, amt {amount:token(mint)}"
            ),
            vec![
                "lamports".to_string(),
                "count".to_string(),
                "amount".to_string()
            ]
        );
    }
}
