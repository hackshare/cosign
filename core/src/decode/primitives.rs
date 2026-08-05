//! Shared value-formatting and program-classification helpers for the
//! instruction-decode stack: hex parsing, bounds-checked little-endian
//! integer reads, decimal/SOL amount rendering, address shortening, and
//! well-known program-id lookup. Ported field-for-field from
//! `InstructionDecoder.swift` and its extensions.

use crate::types::DecodedInstruction;

use super::DecodedInstructionDisplay;

pub const SYSTEM_PROGRAM_ID: &str = "11111111111111111111111111111111";
pub const TOKEN_PROGRAM_ID: &str = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA";
pub const TOKEN_2022_PROGRAM_ID: &str = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb";
pub const STAKE_PROGRAM_ID: &str = "Stake11111111111111111111111111111111111111";
pub const ADDRESS_LOOKUP_TABLE_PROGRAM_ID: &str = "AddressLookupTab1e1111111111111111111111111";
pub const SQUADS_PROGRAM_ID: &str = "SQDS4ep65T869zMMBKyuUq6aD6EgTu8psMjkvj52pCf";
pub const ASSOCIATED_TOKEN_ACCOUNT_PROGRAM_ID: &str =
    "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL";
pub const MEMO_PROGRAM_ID: &str = "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr";
pub const MEMO_LEGACY_PROGRAM_ID: &str = "Memo1UhkJRfHyvLMcVucJwxXeuD728EqVDDwQDxFMNo";
pub const COMPUTE_BUDGET_PROGRAM_ID: &str = "ComputeBudget111111111111111111111111111111";
pub const BPF_UPGRADEABLE_LOADER_PROGRAM_ID: &str = "BPFLoaderUpgradeab1e11111111111111111111111";

const KNOWN_PROGRAM_LABELS: &[(&str, &str)] = &[
    (SYSTEM_PROGRAM_ID, "System Program"),
    (TOKEN_PROGRAM_ID, "SPL Token Program"),
    (TOKEN_2022_PROGRAM_ID, "Token-2022 Program"),
    (STAKE_PROGRAM_ID, "Stake Program"),
    (
        ADDRESS_LOOKUP_TABLE_PROGRAM_ID,
        "Address Lookup Table Program",
    ),
    (
        ASSOCIATED_TOKEN_ACCOUNT_PROGRAM_ID,
        "Associated Token Account Program",
    ),
    (MEMO_PROGRAM_ID, "Memo Program"),
    (MEMO_LEGACY_PROGRAM_ID, "Memo Program"),
    (COMPUTE_BUDGET_PROGRAM_ID, "Compute Budget Program"),
    (SQUADS_PROGRAM_ID, "Squads"),
    (BPF_UPGRADEABLE_LOADER_PROGRAM_ID, "BPF Upgradeable Loader"),
];

pub fn is_system_program(program: &str) -> bool {
    program == SYSTEM_PROGRAM_ID || program == "System Program"
}

pub fn is_token_program(program: &str) -> bool {
    program == TOKEN_PROGRAM_ID
        || program == TOKEN_2022_PROGRAM_ID
        || program == "SPL Token Program"
        || program == "Token-2022 Program"
}

pub fn is_stake_program(program: &str) -> bool {
    program == STAKE_PROGRAM_ID || program == "Stake Program" || program == "stake"
}

pub fn is_address_lookup_table_program(program: &str) -> bool {
    program == ADDRESS_LOOKUP_TABLE_PROGRAM_ID
        || program == "Address Lookup Table Program"
        || program == "address-lookup-table"
}

pub fn is_associated_token_account_program(program: &str) -> bool {
    program == ASSOCIATED_TOKEN_ACCOUNT_PROGRAM_ID || program == "Associated Token Account Program"
}

pub fn is_memo_program(program: &str) -> bool {
    program == MEMO_PROGRAM_ID || program == MEMO_LEGACY_PROGRAM_ID || program == "Memo Program"
}

pub fn is_compute_budget_program(program: &str) -> bool {
    program == COMPUTE_BUDGET_PROGRAM_ID || program == "Compute Budget Program"
}

pub fn is_upgradeable_loader_program(program: &str) -> bool {
    program == BPF_UPGRADEABLE_LOADER_PROGRAM_ID
        || program == "BPF Upgradeable Loader"
        || program == "bpf-upgradeable-loader"
}

pub fn is_squads_program(program: &str) -> bool {
    program == SQUADS_PROGRAM_ID || program == "Squads"
}

/// Maps a program id (or one of its known display-label aliases) to its
/// human-readable label. Unknown programs pass through unchanged.
pub fn program_label(program: &str) -> String {
    KNOWN_PROGRAM_LABELS
        .iter()
        .find(|(id, _)| *id == program)
        .map(|(_, label)| (*label).to_string())
        .unwrap_or_else(|| program.to_string())
}

/// Parses a hex string into bytes. Whitespace is stripped and case is
/// ignored; an odd-length or non-hex string returns `None`.
pub fn bytes_from_hex(hex: &str) -> Option<Vec<u8>> {
    let normalized: Vec<char> = hex
        .chars()
        .filter(|c| !c.is_whitespace())
        .map(|c| c.to_ascii_lowercase())
        .collect();
    if !normalized.len().is_multiple_of(2) {
        return None;
    }
    normalized
        .chunks(2)
        .map(|pair| u8::from_str_radix(&pair.iter().collect::<String>(), 16).ok())
        .collect()
}

/// Reads a bounds-checked little-endian `u32` starting at `offset`.
pub fn read_u32_le(bytes: &[u8], offset: usize) -> Option<u32> {
    let end = offset.checked_add(4)?;
    let slice = bytes.get(offset..end)?;
    Some(u32::from_le_bytes(
        slice.try_into().expect("slice has exactly 4 bytes"),
    ))
}

/// Reads a bounds-checked little-endian `u64` starting at `offset`.
pub fn read_u64_le(bytes: &[u8], offset: usize) -> Option<u64> {
    let end = offset.checked_add(8)?;
    let slice = bytes.get(offset..end)?;
    Some(u64::from_le_bytes(
        slice.try_into().expect("slice has exactly 8 bytes"),
    ))
}

/// Base58-encodes the 32 bytes at `offset`. Returns `None` if the slice is
/// too short.
fn pubkey_base58(bytes: &[u8], offset: usize) -> Option<String> {
    let end = offset.checked_add(32)?;
    let slice = bytes.get(offset..end)?;
    Some(bs58::encode(slice).into_string())
}

/// Renders `amount` (an integer in base units) as a decimal string with
/// `decimals` fractional digits, trimming trailing zeros. `decimals == 0`
/// returns the raw integer.
pub fn decimal_amount(amount: u64, decimals: u8) -> String {
    if decimals == 0 {
        return amount.to_string();
    }

    let decimal_count = decimals as usize;
    let digits = amount.to_string();
    let padded = if digits.len() <= decimal_count {
        "0".repeat(decimal_count - digits.len() + 1) + &digits
    } else {
        digits
    };

    let split_index = padded.len() - decimal_count;
    let whole = &padded[..split_index];
    let fractional = padded[split_index..].trim_end_matches('0');
    if fractional.is_empty() {
        whole.to_string()
    } else {
        format!("{whole}.{fractional}")
    }
}

/// Renders `lamports` as a `"<amount> SOL"` string. No thousands-grouping
/// is applied, matching the relay's own formatter.
pub fn sol_amount(lamports: u64) -> String {
    format!("{} SOL", decimal_amount(lamports, 9))
}

/// Shortens `address` to `"<first 6>...<last 6>"` when longer than 16
/// (Unicode scalar) characters; passes shorter addresses through unchanged.
pub fn short_address(address: &str) -> String {
    let chars: Vec<char> = address.chars().collect();
    if chars.len() <= 16 {
        return address.to_string();
    }
    let first: String = chars[..6].iter().collect();
    let last: String = chars[chars.len() - 6..].iter().collect();
    format!("{first}...{last}")
}

// ---------------------------------------------------------------------------
// Bundled family decoders
//
// Straight port of `InstructionDecoder+{SystemProgramExtras,KnownPrograms,
// StakeAndLookup,TokenProgram,AdminPrograms}.swift`: each `decode_*`
// function matches an instruction's discriminator against its program's
// known instruction set and renders the same (kind, summary) strings as the
// Swift decoder, or falls through to `fallback` when the bytes don't parse
// or the discriminator is unrecognized. These are bundled/built-in decodes
// (no IDL or registry involved), so `provenance`/`cross_check` are always
// `None`.

/// A decoded instruction's static `kind` tag paired with its rendered
/// summary string.
type Metadata = (&'static str, String);

fn display(
    program_label: &str,
    kind: &str,
    summary: String,
    accounts: &[String],
    data_hex: &str,
) -> DecodedInstructionDisplay {
    DecodedInstructionDisplay {
        program_label: program_label.to_string(),
        kind: kind.to_string(),
        summary,
        accounts: accounts.to_vec(),
        data_hex: data_hex.to_string(),
        provenance: None,
        cross_check: None,
    }
}

/// The decode result when a program-specific decoder can't interpret an
/// instruction: passes the instruction's own `kind`/`summary` through if
/// set, otherwise renders `"Instruction for {program_label}"` under a
/// `"raw"` kind. Shared by every family decoder below and by the `mod.rs`
/// orchestrator for programs with no bundled decoder at all.
pub fn fallback(
    instruction: &DecodedInstruction,
    accounts: &[String],
) -> DecodedInstructionDisplay {
    let label = program_label(&instruction.program);
    let kind = if instruction.kind.is_empty() {
        "raw"
    } else {
        instruction.kind.as_str()
    };
    let summary = if instruction.summary.is_empty() {
        format!("Instruction for {label}")
    } else {
        instruction.summary.clone()
    };
    display(&label, kind, summary, accounts, &instruction.raw_data_hex)
}

/// Finishes a family decode: renders the decoder's `(kind, summary)` under
/// `label` when the bytes parsed, otherwise falls back to the instruction's
/// own `kind`/`summary`. Every family decoder ends with this same tail.
fn finish(
    instruction: &DecodedInstruction,
    accounts: &[String],
    label: &str,
    metadata: Option<Metadata>,
) -> DecodedInstructionDisplay {
    match metadata {
        Some((kind, summary)) => display(label, kind, summary, accounts, &instruction.raw_data_hex),
        None => fallback(instruction, accounts),
    }
}

/// Returns `accounts[index]` if present, `None` otherwise (never panics on
/// out-of-range indices).
fn account_at(accounts: &[String], index: usize) -> Option<&str> {
    accounts.get(index).map(String::as_str)
}

/// `"{prefix}{accounts[index]}"` if that account is present, `""` otherwise.
fn account_suffix(accounts: &[String], index: usize, prefix: &str) -> String {
    match account_at(accounts, index) {
        Some(account) => format!("{prefix}{account}"),
        None => String::new(),
    }
}

/// Reads a bincode-encoded (Borsh-style) length-prefixed UTF-8 string:
/// an 8-byte little-endian length followed by that many bytes. Returns the
/// decoded string and the offset immediately after it, or `None` if the
/// length/bytes are out of range or not valid UTF-8.
fn bincode_string(bytes: &[u8], offset: usize) -> Option<(String, usize)> {
    let byte_count = usize::try_from(read_u64_le(bytes, offset)?).ok()?;
    let value_offset = offset.checked_add(8)?;
    let end = value_offset.checked_add(byte_count)?;
    let slice = bytes.get(value_offset..end)?;
    let value = std::str::from_utf8(slice).ok()?.to_string();
    Some((value, end))
}

/// Reads an SPL Token `COption<Pubkey>`: a `u32` tag at `offset` (`0` =
/// none, `1` = some) followed, when present, by a 32-byte pubkey. The outer
/// `Option` is `None` when the bytes don't parse at all (any tag other than
/// 0 or 1, or a truncated pubkey); the inner `Option` carries the decoded
/// value.
fn coption_pubkey(bytes: &[u8], offset: usize) -> Option<Option<String>> {
    match read_u32_le(bytes, offset)? {
        0 => Some(None),
        1 => Some(Some(pubkey_base58(bytes, offset.checked_add(4)?)?)),
        _ => None,
    }
}

/// A `TransferChecked`/`ApproveChecked`/`MintToChecked`/`BurnChecked`
/// amount: requires at least 10 bytes (`u64` amount at offset 1, decimals
/// at offset 9), rendered as `"{decimal_amount} tokens"`.
fn checked_token_amount(data: &[u8]) -> Option<String> {
    if data.len() < 10 {
        return None;
    }
    let amount = read_u64_le(data, 1)?;
    Some(format!("{} tokens", decimal_amount(amount, data[9])))
}

fn is_nonce_account_creation(space: u64, owner: &str) -> bool {
    space == 80 && owner == SYSTEM_PROGRAM_ID
}

fn token_authority_type_label(value: u8) -> &'static str {
    match value {
        0 => "mint authority",
        1 => "freeze authority",
        2 => "account owner",
        3 => "close authority",
        _ => "authority",
    }
}

fn token_account_action_summary(action: &str, account: Option<&str>) -> String {
    match account {
        Some(account) => format!("{action} {}", short_address(account)),
        None => action.to_string(),
    }
}

fn token_recipient_summary(
    amount: &str,
    verb: &str,
    preposition: &str,
    recipient: Option<&str>,
) -> String {
    match recipient {
        Some(recipient) => format!("{verb} {amount} {preposition} {}", short_address(recipient)),
        None => format!("{verb} {amount}"),
    }
}

fn stake_authority_label(value: u32) -> &'static str {
    match value {
        1 => "withdraw",
        _ => "staker",
    }
}

fn address_count_label(count: u64) -> String {
    if count == 1 {
        "1 address".to_string()
    } else {
        format!("{count} addresses")
    }
}

fn lookup_table_slot_summary(data: &[u8]) -> String {
    match read_u64_le(data, 4) {
        Some(slot) => format!(" using recent slot {slot}"),
        None => String::new(),
    }
}

fn program_admin_summary(prefix: &str, address: Option<&str>) -> String {
    match address {
        Some(address) => format!("{prefix} {address}"),
        None => prefix.to_string(),
    }
}

fn upgrade_authority_summary(accounts: &[String], checked: bool) -> String {
    if let Some(authority) = account_at(accounts, 2) {
        format!("Set upgrade authority to {authority}")
    } else if checked {
        "Set upgrade authority".to_string()
    } else {
        "Clear upgrade authority".to_string()
    }
}

fn program_extend_summary(data: &[u8]) -> String {
    match read_u32_le(data, 4) {
        Some(additional_bytes) => format!("Extend program by {additional_bytes} bytes"),
        None => "Extend program".to_string(),
    }
}

fn short_text(value: &str, max_characters: usize) -> String {
    if value.chars().count() <= max_characters {
        value.to_string()
    } else {
        let prefix: String = value.chars().take(max_characters).collect();
        format!("{prefix}...")
    }
}

fn squads_summary(kind: &str) -> &'static str {
    match kind {
        "add_member" => "Add member",
        "remove_member" => "Remove member",
        "change_threshold" => "Change threshold",
        "set_time_lock" => "Set time lock",
        "add_spending_limit" => "Add spending limit",
        "remove_spending_limit" => "Remove spending limit",
        "set_rent_collector" => "Set rent collector",
        _ => "Squads config action",
    }
}

// --- System Program ---------------------------------------------------

pub fn decode_system(
    instruction: &DecodedInstruction,
    data: &[u8],
    accounts: &[String],
) -> DecodedInstructionDisplay {
    let Some(discriminator) = read_u32_le(data, 0) else {
        return fallback(instruction, accounts);
    };
    finish(
        instruction,
        accounts,
        "System Program",
        system_metadata(discriminator, data),
    )
}

fn system_metadata(discriminator: u32, data: &[u8]) -> Option<Metadata> {
    match discriminator {
        0 => system_create_account_metadata(data),
        1 => system_assign_metadata(data),
        2 => system_transfer_metadata(data),
        3 => system_create_account_with_seed_metadata(data),
        4 => Some(("advance_nonce_account", "Advance nonce".to_string())),
        5 => system_withdraw_nonce_metadata(data),
        6 => system_nonce_authority_metadata(
            data,
            "initialize_nonce_account",
            "Initialize nonce authority",
        ),
        7 => system_nonce_authority_metadata(
            data,
            "authorize_nonce_account",
            "Authorize nonce authority",
        ),
        8 => system_allocate_metadata(data),
        9 => system_allocate_with_seed_metadata(data),
        10 => system_assign_with_seed_metadata(data),
        11 => system_transfer_with_seed_metadata(data),
        12 => Some(("upgrade_nonce_account", "Upgrade nonce account".to_string())),
        _ => None,
    }
}

fn system_create_account_metadata(data: &[u8]) -> Option<Metadata> {
    let lamports = read_u64_le(data, 4)?;
    let space = read_u64_le(data, 12)?;
    let owner = pubkey_base58(data, 20)?;
    Some(if is_nonce_account_creation(space, &owner) {
        (
            "create_nonce_account",
            format!("Create nonce account with {}", sol_amount(lamports)),
        )
    } else {
        (
            "create_account",
            format!(
                "Create account with {}, {space} bytes, owner {owner}",
                sol_amount(lamports)
            ),
        )
    })
}

fn system_assign_metadata(data: &[u8]) -> Option<Metadata> {
    let owner = pubkey_base58(data, 4)?;
    Some(("assign", format!("Assign account owner to {owner}")))
}

fn system_transfer_metadata(data: &[u8]) -> Option<Metadata> {
    let lamports = read_u64_le(data, 4)?;
    Some(("transfer", format!("Transfer {}", sol_amount(lamports))))
}

fn system_create_account_with_seed_metadata(data: &[u8]) -> Option<Metadata> {
    let (_, next) = bincode_string(data, 36)?;
    let lamports = read_u64_le(data, next)?;
    let space = read_u64_le(data, next.checked_add(8)?)?;
    let owner = pubkey_base58(data, next.checked_add(16)?)?;
    Some(if is_nonce_account_creation(space, &owner) {
        (
            "create_nonce_account_with_seed",
            format!("Create seeded nonce account with {}", sol_amount(lamports)),
        )
    } else {
        (
            "create_account_with_seed",
            format!(
                "Create seeded account with {}, {space} bytes, owner {owner}",
                sol_amount(lamports)
            ),
        )
    })
}

fn system_withdraw_nonce_metadata(data: &[u8]) -> Option<Metadata> {
    let lamports = read_u64_le(data, 4)?;
    Some((
        "withdraw_nonce_account",
        format!("Withdraw {} from nonce account", sol_amount(lamports)),
    ))
}

fn system_nonce_authority_metadata(
    data: &[u8],
    kind: &'static str,
    summary_prefix: &str,
) -> Option<Metadata> {
    let authority = pubkey_base58(data, 4)?;
    Some((kind, format!("{summary_prefix} {authority}")))
}

fn system_allocate_metadata(data: &[u8]) -> Option<Metadata> {
    let space = read_u64_le(data, 4)?;
    Some((
        "allocate",
        format!("Allocate {space} bytes for system account"),
    ))
}

fn system_allocate_with_seed_metadata(data: &[u8]) -> Option<Metadata> {
    let (_, next) = bincode_string(data, 36)?;
    let space = read_u64_le(data, next)?;
    let owner = pubkey_base58(data, next.checked_add(8)?)?;
    Some((
        "allocate_with_seed",
        format!("Allocate {space} bytes for seeded account owned by {owner}"),
    ))
}

fn system_assign_with_seed_metadata(data: &[u8]) -> Option<Metadata> {
    let (_, next) = bincode_string(data, 36)?;
    let owner = pubkey_base58(data, next)?;
    Some((
        "assign_with_seed",
        format!("Assign seeded account owner to {owner}"),
    ))
}

fn system_transfer_with_seed_metadata(data: &[u8]) -> Option<Metadata> {
    let lamports = read_u64_le(data, 4)?;
    Some((
        "transfer_with_seed",
        format!("Transfer {} from seeded account", sol_amount(lamports)),
    ))
}

// --- SPL Token / Token-2022 ---------------------------------------------

pub fn decode_token(
    instruction: &DecodedInstruction,
    data: &[u8],
    accounts: &[String],
) -> DecodedInstructionDisplay {
    finish(
        instruction,
        accounts,
        &program_label(&instruction.program),
        token_instruction_metadata(data, accounts),
    )
}

/// Dispatch order mirrors the Swift `tokenInstructionMetadata`: base
/// instructions, then the `*Checked` variants, then initialization.
fn token_instruction_metadata(data: &[u8], accounts: &[String]) -> Option<Metadata> {
    let discriminator = *data.first()?;
    token_base_instruction_metadata(discriminator, data, accounts)
        .or_else(|| token_checked_instruction_metadata(discriminator, data, accounts))
        .or_else(|| token_initialization_metadata(discriminator, data))
}

fn token_base_instruction_metadata(
    discriminator: u8,
    data: &[u8],
    accounts: &[String],
) -> Option<Metadata> {
    match discriminator {
        3 => token_transfer_metadata(data, accounts),
        4 => token_approve_metadata(data, accounts),
        5 => Some(("revoke", "Revoke token delegate".to_string())),
        6 => token_set_authority_metadata(data),
        7 => token_mint_metadata(data, accounts),
        8 => token_burn_metadata(data, accounts),
        9 => Some((
            "close_account",
            token_account_action_summary("Close token account", account_at(accounts, 0)),
        )),
        10 => Some((
            "freeze_account",
            token_account_action_summary("Freeze token account", account_at(accounts, 0)),
        )),
        11 => Some((
            "thaw_account",
            token_account_action_summary("Thaw token account", account_at(accounts, 0)),
        )),
        _ => None,
    }
}

fn token_checked_instruction_metadata(
    discriminator: u8,
    data: &[u8],
    accounts: &[String],
) -> Option<Metadata> {
    match discriminator {
        12 => token_checked_transfer_metadata(data, accounts),
        13 => token_checked_approve_metadata(data, accounts),
        14 => token_checked_mint_metadata(data, accounts),
        15 => token_checked_burn_metadata(data, accounts),
        _ => None,
    }
}

fn token_initialization_metadata(discriminator: u8, data: &[u8]) -> Option<Metadata> {
    match discriminator {
        0 => initialize_mint_metadata(data, "initialize_mint"),
        16 => token_account_owner_metadata("initialize_account2", data),
        18 => token_account_owner_metadata("initialize_account3", data),
        20 => initialize_mint_metadata(data, "initialize_mint2"),
        22 => Some((
            "initialize_immutable_owner",
            "Initialize immutable token account owner".to_string(),
        )),
        _ => None,
    }
}

fn token_transfer_metadata(data: &[u8], accounts: &[String]) -> Option<Metadata> {
    let amount = read_u64_le(data, 1)?;
    let amount = format!("{amount} base units");
    Some((
        "transfer",
        token_recipient_summary(&amount, "Transfer", "to", account_at(accounts, 1)),
    ))
}

fn token_checked_transfer_metadata(data: &[u8], accounts: &[String]) -> Option<Metadata> {
    let amount = checked_token_amount(data)?;
    Some((
        "transfer_checked",
        token_recipient_summary(&amount, "Transfer", "to", account_at(accounts, 2)),
    ))
}

fn token_approve_metadata(data: &[u8], accounts: &[String]) -> Option<Metadata> {
    let amount = read_u64_le(data, 1)?;
    let amount = format!("{amount} base units");
    Some((
        "approve",
        token_recipient_summary(&amount, "Approve", "for", account_at(accounts, 1)),
    ))
}

fn token_checked_approve_metadata(data: &[u8], accounts: &[String]) -> Option<Metadata> {
    let amount = checked_token_amount(data)?;
    Some((
        "approve_checked",
        token_recipient_summary(&amount, "Approve", "for", account_at(accounts, 2)),
    ))
}

fn token_set_authority_metadata(data: &[u8]) -> Option<Metadata> {
    if data.len() < 6 {
        return None;
    }
    let authority_type = token_authority_type_label(data[1]);
    let new_authority = coption_pubkey(data, 2)?;
    let summary = match new_authority {
        Some(authority) => format!("Set token {authority_type} to {authority}"),
        None => format!("Clear token {authority_type}"),
    };
    Some(("set_authority", summary))
}

fn token_mint_metadata(data: &[u8], accounts: &[String]) -> Option<Metadata> {
    let amount = read_u64_le(data, 1)?;
    let amount = format!("{amount} base units");
    Some((
        "mint_to",
        token_recipient_summary(&amount, "Mint", "to", account_at(accounts, 1)),
    ))
}

fn token_checked_mint_metadata(data: &[u8], accounts: &[String]) -> Option<Metadata> {
    let amount = checked_token_amount(data)?;
    Some((
        "mint_to_checked",
        token_recipient_summary(&amount, "Mint", "to", account_at(accounts, 1)),
    ))
}

fn token_burn_metadata(data: &[u8], accounts: &[String]) -> Option<Metadata> {
    let amount = read_u64_le(data, 1)?;
    let amount = format!("{amount} base units");
    Some((
        "burn",
        token_recipient_summary(&amount, "Burn", "from", account_at(accounts, 0)),
    ))
}

fn token_checked_burn_metadata(data: &[u8], accounts: &[String]) -> Option<Metadata> {
    let amount = checked_token_amount(data)?;
    Some((
        "burn_checked",
        token_recipient_summary(&amount, "Burn", "from", account_at(accounts, 0)),
    ))
}

fn initialize_mint_metadata(data: &[u8], kind: &'static str) -> Option<Metadata> {
    if data.len() < 34 {
        return None;
    }
    let mint_authority = pubkey_base58(data, 2)?;
    let freeze_authority = coption_pubkey(data, 34)?;
    let freeze_summary = match freeze_authority {
        Some(address) => format!(", freeze authority {address}"),
        None => ", no freeze authority".to_string(),
    };
    let decimals = data[1];
    Some((
        kind,
        format!(
            "Initialize mint with {decimals} decimals, mint authority {mint_authority}{freeze_summary}"
        ),
    ))
}

fn token_account_owner_metadata(kind: &'static str, data: &[u8]) -> Option<Metadata> {
    let owner = pubkey_base58(data, 1)?;
    Some((kind, format!("Initialize token account for owner {owner}")))
}

// --- Stake Program -------------------------------------------------------

pub fn decode_stake(
    instruction: &DecodedInstruction,
    data: &[u8],
    accounts: &[String],
) -> DecodedInstructionDisplay {
    let Some(discriminator) = read_u32_le(data, 0) else {
        return fallback(instruction, accounts);
    };
    let metadata = stake_authority_metadata(discriminator, data, accounts)
        .or_else(|| stake_movement_metadata(discriminator, data, accounts))
        .or_else(|| stake_lifecycle_metadata(discriminator, data, accounts));
    finish(instruction, accounts, "Stake Program", metadata)
}

fn stake_authority_metadata(
    discriminator: u32,
    data: &[u8],
    accounts: &[String],
) -> Option<Metadata> {
    match discriminator {
        1 | 8 => stake_authorize_metadata(data),
        10 | 11 => stake_authorize_checked_metadata(data, accounts),
        _ => None,
    }
}

fn stake_authorize_metadata(data: &[u8]) -> Option<Metadata> {
    let authority = pubkey_base58(data, 4)?;
    let authority_type = read_u32_le(data, 36)?;
    Some((
        "stake_authority_change",
        format!(
            "Set stake {} authority to {authority}",
            stake_authority_label(authority_type)
        ),
    ))
}

fn stake_authorize_checked_metadata(data: &[u8], accounts: &[String]) -> Option<Metadata> {
    let authority_type = read_u32_le(data, 4)?;
    let target = account_at(accounts, 3).unwrap_or("new authority");
    Some((
        "stake_authority_change",
        format!(
            "Set stake {} authority to {target}",
            stake_authority_label(authority_type)
        ),
    ))
}

fn stake_movement_metadata(
    discriminator: u32,
    data: &[u8],
    accounts: &[String],
) -> Option<Metadata> {
    match discriminator {
        2 => Some((
            "stake_delegate",
            format!("Delegate stake{}", account_suffix(accounts, 1, " to ")),
        )),
        3 => stake_lamports_metadata(data, "stake_split", "Split", " stake"),
        4 => stake_lamports_metadata(data, "stake_withdraw", "Withdraw", " from stake"),
        7 => Some(("stake_merge", "Merge stake accounts".to_string())),
        15 => Some((
            "stake_redelegate",
            format!("Redelegate stake{}", account_suffix(accounts, 2, " to ")),
        )),
        _ => None,
    }
}

fn stake_lamports_metadata(
    data: &[u8],
    kind: &'static str,
    verb: &str,
    suffix: &str,
) -> Option<Metadata> {
    let lamports = read_u64_le(data, 4)?;
    Some((kind, format!("{verb} {}{suffix}", sol_amount(lamports))))
}

fn stake_lifecycle_metadata(
    discriminator: u32,
    data: &[u8],
    accounts: &[String],
) -> Option<Metadata> {
    match discriminator {
        0 => stake_initialize_metadata(data, accounts),
        5 => Some(("stake_deactivate", "Deactivate stake".to_string())),
        6 | 12 => Some(("stake_lockup_change", "Set stake lockup".to_string())),
        9 => Some(checked_stake_initialize_metadata(accounts)),
        13 => Some((
            "stake_minimum_delegation",
            "Get minimum stake delegation".to_string(),
        )),
        14 => Some((
            "stake_deactivate",
            format!(
                "Deactivate delinquent stake{}",
                account_suffix(accounts, 1, " for vote account ")
            ),
        )),
        _ => None,
    }
}

fn stake_initialize_metadata(data: &[u8], accounts: &[String]) -> Option<Metadata> {
    let staker = pubkey_base58(data, 4)?;
    let withdrawer = pubkey_base58(data, 36)?;
    Some((
        "stake_initialize",
        format!(
            "Initialize stake account{} with staker {staker} and withdrawer {withdrawer}",
            account_suffix(accounts, 0, " ")
        ),
    ))
}

fn checked_stake_initialize_metadata(accounts: &[String]) -> Metadata {
    let staker = account_at(accounts, 2).unwrap_or("stake authority");
    let withdrawer = account_at(accounts, 3).unwrap_or("withdraw authority");
    (
        "stake_initialize",
        format!("Initialize stake account with staker {staker} and withdrawer {withdrawer}"),
    )
}

// --- Address Lookup Table Program -----------------------------------------

pub fn decode_address_lookup_table(
    instruction: &DecodedInstruction,
    data: &[u8],
    accounts: &[String],
) -> DecodedInstructionDisplay {
    let Some(discriminator) = read_u32_le(data, 0) else {
        return fallback(instruction, accounts);
    };
    let metadata = match discriminator {
        0 => Some((
            "lookup_table_create",
            format!(
                "Create address lookup table{}",
                lookup_table_slot_summary(data)
            ),
        )),
        1 => Some((
            "lookup_table_freeze",
            "Freeze address lookup table".to_string(),
        )),
        2 => lookup_table_extend_metadata(data),
        3 => Some((
            "lookup_table_deactivate",
            "Deactivate address lookup table".to_string(),
        )),
        4 => Some((
            "lookup_table_close",
            "Close address lookup table".to_string(),
        )),
        _ => None,
    };
    finish(
        instruction,
        accounts,
        "Address Lookup Table Program",
        metadata,
    )
}

fn lookup_table_extend_metadata(data: &[u8]) -> Option<Metadata> {
    let address_count = read_u64_le(data, 4)?;
    Some((
        "lookup_table_extend",
        format!(
            "Extend address lookup table with {}",
            address_count_label(address_count)
        ),
    ))
}

// --- Associated Token Account Program -------------------------------------

pub fn decode_associated_token_account(
    instruction: &DecodedInstruction,
    data: &[u8],
    accounts: &[String],
) -> DecodedInstructionDisplay {
    let (kind, summary) = match data.first().copied() {
        None | Some(0) => ("create", "Create associated token account"),
        Some(1) => (
            "create_idempotent",
            "Create associated token account if needed",
        ),
        Some(2) => ("recover_nested", "Recover nested associated token account"),
        _ => return fallback(instruction, accounts),
    };
    display(
        "Associated Token Account Program",
        kind,
        summary.to_string(),
        accounts,
        &instruction.raw_data_hex,
    )
}

// --- Memo Program ----------------------------------------------------------

pub fn decode_memo(
    instruction: &DecodedInstruction,
    data: &[u8],
    accounts: &[String],
) -> DecodedInstructionDisplay {
    let Ok(decoded) = std::str::from_utf8(data) else {
        return fallback(instruction, accounts);
    };
    let memo = decoded.trim();
    let summary = if memo.is_empty() {
        "Memo".to_string()
    } else {
        format!("Memo: {}", short_text(memo, 80))
    };
    display(
        "Memo Program",
        "memo",
        summary,
        accounts,
        &instruction.raw_data_hex,
    )
}

// --- Compute Budget Program --------------------------------------------

pub fn decode_compute_budget(
    instruction: &DecodedInstruction,
    data: &[u8],
    accounts: &[String],
) -> DecodedInstructionDisplay {
    let Some(discriminator) = data.first().copied() else {
        return fallback(instruction, accounts);
    };
    let metadata = match discriminator {
        0 => compute_budget_request_units_metadata(data),
        1 => compute_budget_heap_frame_metadata(data),
        2 => compute_budget_unit_limit_metadata(data),
        3 => compute_budget_unit_price_metadata(data),
        _ => None,
    };
    finish(instruction, accounts, "Compute Budget Program", metadata)
}

fn compute_budget_request_units_metadata(data: &[u8]) -> Option<Metadata> {
    let units = read_u32_le(data, 1)?;
    let additional_fee = read_u32_le(data, 5)?;
    Some((
        "request_units_deprecated",
        format!("Request {units} compute units with {additional_fee} additional fee"),
    ))
}

fn compute_budget_heap_frame_metadata(data: &[u8]) -> Option<Metadata> {
    let bytes = read_u32_le(data, 1)?;
    Some((
        "request_heap_frame",
        format!("Request {bytes} byte heap frame"),
    ))
}

fn compute_budget_unit_limit_metadata(data: &[u8]) -> Option<Metadata> {
    let units = read_u32_le(data, 1)?;
    Some((
        "set_compute_unit_limit",
        format!("Set compute unit limit to {units}"),
    ))
}

fn compute_budget_unit_price_metadata(data: &[u8]) -> Option<Metadata> {
    let micro_lamports = read_u64_le(data, 1)?;
    Some((
        "set_compute_unit_price",
        format!("Set compute unit price to {micro_lamports} micro-lamports"),
    ))
}

// --- BPF Upgradeable Loader ----------------------------------------------

pub fn decode_upgradeable_loader(
    instruction: &DecodedInstruction,
    data: &[u8],
    accounts: &[String],
) -> DecodedInstructionDisplay {
    finish(
        instruction,
        accounts,
        "BPF Upgradeable Loader",
        upgradeable_loader_metadata(data, accounts),
    )
}

fn upgradeable_loader_metadata(data: &[u8], accounts: &[String]) -> Option<Metadata> {
    let discriminator = data.first().copied()?;
    match discriminator {
        0 => Some((
            "program_buffer_initialize",
            "Initialize program buffer".to_string(),
        )),
        1 => program_buffer_write_metadata(data),
        2 => Some((
            "program_deploy",
            program_admin_summary("Deploy upgradeable program", account_at(accounts, 2)),
        )),
        3 => Some((
            "program_upgrade",
            program_admin_summary("Upgrade program", account_at(accounts, 1)),
        )),
        4 => Some((
            "program_upgrade_authority_change",
            upgrade_authority_summary(accounts, false),
        )),
        5 => Some((
            "program_close",
            "Close upgradeable loader account".to_string(),
        )),
        6 => Some(("program_extend", program_extend_summary(data))),
        7 => Some((
            "program_upgrade_authority_change",
            upgrade_authority_summary(accounts, true),
        )),
        _ => None,
    }
}

fn program_buffer_write_metadata(data: &[u8]) -> Option<Metadata> {
    let offset = read_u32_le(data, 4)?;
    Some((
        "program_buffer_write",
        format!("Write program buffer at offset {offset}"),
    ))
}

// --- Squads ----------------------------------------------------------------

pub fn decode_squads(
    instruction: &DecodedInstruction,
    accounts: &[String],
) -> DecodedInstructionDisplay {
    let kind = if instruction.kind.is_empty() {
        "config".to_string()
    } else {
        instruction.kind.clone()
    };
    let summary = if instruction.summary.is_empty() {
        squads_summary(&kind).to_string()
    } else {
        instruction.summary.clone()
    };
    display(
        "Squads",
        &kind,
        summary,
        accounts,
        &instruction.raw_data_hex,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hex_round_trips_and_rejects_odd_length() {
        assert_eq!(bytes_from_hex("0e00").unwrap(), vec![0x0e, 0x00]);
        assert_eq!(bytes_from_hex("0E 00").unwrap(), vec![0x0e, 0x00]); // whitespace stripped, case-insensitive
        assert!(bytes_from_hex("abc").is_none()); // odd length
        assert!(bytes_from_hex("zz").is_none()); // non-hex
    }

    #[test]
    fn little_endian_reads_bounds_check() {
        let b = [0x88, 0x13, 0, 0, 0, 0, 0, 0];
        assert_eq!(read_u64_le(&b, 0), Some(5000));
        assert_eq!(read_u32_le(&b, 0), Some(5000));
        assert_eq!(read_u64_le(&b, 1), None); // only 7 bytes left
    }

    #[test]
    fn pubkey_base58_requires_32_bytes() {
        let bytes = [7u8; 32];
        let encoded = pubkey_base58(&bytes, 0).unwrap();
        assert_eq!(encoded, bs58::encode(&bytes[..]).into_string());
        assert!(pubkey_base58(&[0u8; 31], 0).is_none());
    }

    #[test]
    fn decimal_amount_matches_swift() {
        assert_eq!(decimal_amount(5000, 9), "0.000005");
        assert_eq!(decimal_amount(1, 9), "0.000000001");
        assert_eq!(decimal_amount(42, 9), "0.000000042");
        assert_eq!(decimal_amount(2_000_000_000, 9), "2");
        assert_eq!(decimal_amount(50_000_000_000, 9), "50");
        assert_eq!(decimal_amount(124_309_938_021, 9), "124.309938021");
        assert_eq!(decimal_amount(100, 0), "100"); // decimals 0 → raw
    }

    #[test]
    fn sol_amount_matches_swift() {
        assert_eq!(sol_amount(5000), "0.000005 SOL");
        assert_eq!(sol_amount(2_000_000_000), "2 SOL");
        assert_eq!(sol_amount(50_000_000_000), "50 SOL");
    }

    #[test]
    fn short_address_only_shortens_when_long() {
        assert_eq!(short_address("abc"), "abc");
        assert_eq!(
            short_address("SoMeLongMintAddress1111111111111111111111111"),
            "SoMeLo...111111"
        );
    }

    #[test]
    fn program_label_maps_known_and_passes_through_unknown() {
        assert_eq!(
            program_label("11111111111111111111111111111111"),
            "System Program"
        );
        assert_eq!(program_label("Unknown111"), "Unknown111");
    }

    #[test]
    fn program_predicates_accept_id_and_label_aliases() {
        assert!(is_system_program(SYSTEM_PROGRAM_ID));
        assert!(is_system_program("System Program"));
        assert!(!is_system_program("something else"));

        assert!(is_token_program(TOKEN_PROGRAM_ID));
        assert!(is_token_program(TOKEN_2022_PROGRAM_ID));
        assert!(is_token_program("SPL Token Program"));
        assert!(is_token_program("Token-2022 Program"));

        assert!(is_stake_program(STAKE_PROGRAM_ID));
        assert!(is_stake_program("stake"));

        assert!(is_address_lookup_table_program(
            ADDRESS_LOOKUP_TABLE_PROGRAM_ID
        ));
        assert!(is_address_lookup_table_program("address-lookup-table"));

        assert!(is_associated_token_account_program(
            ASSOCIATED_TOKEN_ACCOUNT_PROGRAM_ID
        ));
        assert!(is_memo_program(MEMO_PROGRAM_ID));
        assert!(is_memo_program(MEMO_LEGACY_PROGRAM_ID));
        assert!(is_compute_budget_program(COMPUTE_BUDGET_PROGRAM_ID));

        assert!(is_upgradeable_loader_program(
            BPF_UPGRADEABLE_LOADER_PROGRAM_ID
        ));
        assert!(is_upgradeable_loader_program("bpf-upgradeable-loader"));

        assert!(is_squads_program(SQUADS_PROGRAM_ID));
        assert!(is_squads_program("Squads"));
    }
}

#[cfg(test)]
mod family_tests {
    use super::*;
    use crate::types::DecodedInstruction;

    fn ix(program: &str, hex: &str, accounts: &[&str]) -> DecodedInstruction {
        DecodedInstruction {
            program: program.into(),
            kind: "raw".into(),
            summary: String::new(),
            accounts: accounts.iter().map(|s| s.to_string()).collect(),
            raw_data_hex: hex.into(),
            config_action: None,
        }
    }

    fn ix_full(
        program: &str,
        kind: &str,
        summary: &str,
        hex: &str,
        accounts: &[&str],
    ) -> DecodedInstruction {
        DecodedInstruction {
            program: program.into(),
            kind: kind.into(),
            summary: summary.into(),
            accounts: accounts.iter().map(|s| s.to_string()).collect(),
            raw_data_hex: hex.into(),
            config_action: None,
        }
    }

    fn data_of(i: &DecodedInstruction) -> Vec<u8> {
        bytes_from_hex(&i.raw_data_hex).unwrap()
    }

    // --- fallback ----------------------------------------------------

    #[test]
    fn fallback_for_unknown_program() {
        let i = ix("Unknown111111111111111111111111111111111", "ff", &[]);
        let d = fallback(&i, &i.accounts);
        assert_eq!(d.program_label, "Unknown111111111111111111111111111111111");
        assert_eq!(d.kind, "raw");
        assert_eq!(
            d.summary,
            "Instruction for Unknown111111111111111111111111111111111"
        );
        assert_eq!(d.data_hex, "ff");
    }

    #[test]
    fn fallback_passes_through_existing_kind_and_summary() {
        let i = ix_full("SomeProgram", "custom_kind", "Custom summary", "", &["a"]);
        let d = fallback(&i, &i.accounts);
        assert_eq!(d.kind, "custom_kind");
        assert_eq!(d.summary, "Custom summary");
    }

    // --- System Program ------------------------------------------------

    #[test]
    fn decodes_system_transfer() {
        let i = ix(
            SYSTEM_PROGRAM_ID,
            "020000008813000000000000",
            &["from", "to"],
        );
        let data = data_of(&i);
        let d = decode_system(&i, &data, &i.accounts);
        assert_eq!(d.program_label, "System Program");
        assert_eq!(d.kind, "transfer");
        assert_eq!(d.summary, "Transfer 0.000005 SOL");
        assert_eq!(d.accounts, vec!["from".to_string(), "to".to_string()]);
    }

    #[test]
    fn decodes_system_create_account() {
        let i = ix(
            SYSTEM_PROGRAM_ID,
            "000000002a00000000000000a50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            &[],
        );
        let data = data_of(&i);
        let d = decode_system(&i, &data, &i.accounts);
        assert_eq!(d.kind, "create_account");
        assert_eq!(
            d.summary,
            format!("Create account with 0.000000042 SOL, 165 bytes, owner {SYSTEM_PROGRAM_ID}")
        );
    }

    #[test]
    fn decodes_system_owner_and_nonce_authority_changes() {
        let zero = "00".repeat(32);
        let assign = ix(SYSTEM_PROGRAM_ID, &format!("01000000{zero}"), &["account"]);
        let nonce = ix(
            SYSTEM_PROGRAM_ID,
            &format!("07000000{zero}"),
            &["nonce", "authority"],
        );

        let decoded_assign = decode_system(&assign, &data_of(&assign), &assign.accounts);
        let decoded_nonce = decode_system(&nonce, &data_of(&nonce), &nonce.accounts);

        assert_eq!(decoded_assign.kind, "assign");
        assert_eq!(
            decoded_assign.summary,
            format!("Assign account owner to {SYSTEM_PROGRAM_ID}")
        );
        assert_eq!(decoded_nonce.kind, "authorize_nonce_account");
        assert_eq!(
            decoded_nonce.summary,
            format!("Authorize nonce authority {SYSTEM_PROGRAM_ID}")
        );
    }

    #[test]
    fn decodes_nonce_creation_and_system_admin_actions() {
        let zero = "00".repeat(32);
        let create_nonce = ix(
            SYSTEM_PROGRAM_ID,
            &format!("0000000040420f00000000005000000000000000{zero}"),
            &[],
        );
        let initialize_nonce = ix(SYSTEM_PROGRAM_ID, &format!("06000000{zero}"), &[]);
        let withdraw_nonce = ix(SYSTEM_PROGRAM_ID, "0500000040420f0000000000", &[]);
        let advance_nonce = ix(SYSTEM_PROGRAM_ID, "04000000", &[]);

        let decoded_create = decode_system(
            &create_nonce,
            &data_of(&create_nonce),
            &create_nonce.accounts,
        );
        let decoded_initialize = decode_system(
            &initialize_nonce,
            &data_of(&initialize_nonce),
            &initialize_nonce.accounts,
        );
        let decoded_withdraw = decode_system(
            &withdraw_nonce,
            &data_of(&withdraw_nonce),
            &withdraw_nonce.accounts,
        );
        let decoded_advance = decode_system(
            &advance_nonce,
            &data_of(&advance_nonce),
            &advance_nonce.accounts,
        );

        assert_eq!(decoded_create.kind, "create_nonce_account");
        assert_eq!(
            decoded_create.summary,
            "Create nonce account with 0.001 SOL"
        );
        assert_eq!(decoded_initialize.kind, "initialize_nonce_account");
        assert_eq!(
            decoded_initialize.summary,
            format!("Initialize nonce authority {SYSTEM_PROGRAM_ID}")
        );
        assert_eq!(decoded_withdraw.kind, "withdraw_nonce_account");
        assert_eq!(
            decoded_withdraw.summary,
            "Withdraw 0.001 SOL from nonce account"
        );
        assert_eq!(decoded_advance.kind, "advance_nonce_account");
        assert_eq!(decoded_advance.summary, "Advance nonce");
    }

    #[test]
    fn decodes_system_seeded_instructions() {
        let nonce = ix(
            SYSTEM_PROGRAM_ID,
            "030000000000000000000000000000000000000000000000000000000000000000000000030000000000000061626300ca9a3b0000000050000000000000000000000000000000000000000000000000000000000000000000000000000000",
            &[],
        );
        let plain = ix(
            SYSTEM_PROGRAM_ID,
            "030000000000000000000000000000000000000000000000000000000000000000000000030000000000000061626300ca9a3b000000000a000000000000000000000000000000000000000000000000000000000000000000000000000000",
            &[],
        );
        let allocate_with_seed = ix(
            SYSTEM_PROGRAM_ID,
            "0900000000000000000000000000000000000000000000000000000000000000000000000300000000000000616263c8000000000000000000000000000000000000000000000000000000000000000000000000000000",
            &[],
        );
        let assign_with_seed = ix(
            SYSTEM_PROGRAM_ID,
            "0a000000000000000000000000000000000000000000000000000000000000000000000003000000000000006162630000000000000000000000000000000000000000000000000000000000000000",
            &[],
        );
        let transfer_with_seed = ix(SYSTEM_PROGRAM_ID, "0b0000000094357700000000", &[]);
        let allocate = ix(SYSTEM_PROGRAM_ID, "080000008000000000000000", &[]);
        let upgrade_nonce = ix(SYSTEM_PROGRAM_ID, "0c000000", &[]);

        let decoded_nonce = decode_system(&nonce, &data_of(&nonce), &nonce.accounts);
        let decoded_plain = decode_system(&plain, &data_of(&plain), &plain.accounts);
        let decoded_allocate_with_seed = decode_system(
            &allocate_with_seed,
            &data_of(&allocate_with_seed),
            &allocate_with_seed.accounts,
        );
        let decoded_assign_with_seed = decode_system(
            &assign_with_seed,
            &data_of(&assign_with_seed),
            &assign_with_seed.accounts,
        );
        let decoded_transfer_with_seed = decode_system(
            &transfer_with_seed,
            &data_of(&transfer_with_seed),
            &transfer_with_seed.accounts,
        );
        let decoded_allocate = decode_system(&allocate, &data_of(&allocate), &allocate.accounts);
        let decoded_upgrade_nonce = decode_system(
            &upgrade_nonce,
            &data_of(&upgrade_nonce),
            &upgrade_nonce.accounts,
        );

        assert_eq!(decoded_nonce.kind, "create_nonce_account_with_seed");
        assert_eq!(
            decoded_nonce.summary,
            "Create seeded nonce account with 1 SOL"
        );
        assert_eq!(decoded_plain.kind, "create_account_with_seed");
        assert_eq!(
            decoded_plain.summary,
            format!("Create seeded account with 1 SOL, 10 bytes, owner {SYSTEM_PROGRAM_ID}")
        );
        assert_eq!(decoded_allocate_with_seed.kind, "allocate_with_seed");
        assert_eq!(
            decoded_allocate_with_seed.summary,
            format!("Allocate 200 bytes for seeded account owned by {SYSTEM_PROGRAM_ID}")
        );
        assert_eq!(decoded_assign_with_seed.kind, "assign_with_seed");
        assert_eq!(
            decoded_assign_with_seed.summary,
            format!("Assign seeded account owner to {SYSTEM_PROGRAM_ID}")
        );
        assert_eq!(decoded_transfer_with_seed.kind, "transfer_with_seed");
        assert_eq!(
            decoded_transfer_with_seed.summary,
            "Transfer 2 SOL from seeded account"
        );
        assert_eq!(decoded_allocate.kind, "allocate");
        assert_eq!(
            decoded_allocate.summary,
            "Allocate 128 bytes for system account"
        );
        assert_eq!(decoded_upgrade_nonce.kind, "upgrade_nonce_account");
        assert_eq!(decoded_upgrade_nonce.summary, "Upgrade nonce account");
    }

    #[test]
    fn system_falls_back_for_unknown_discriminator_and_truncated_data() {
        let unknown = ix(SYSTEM_PROGRAM_ID, "63000000", &[]);
        let truncated = ix(SYSTEM_PROGRAM_ID, "02000000", &[]); // transfer with no lamports
        let empty = ix(SYSTEM_PROGRAM_ID, "", &[]);

        assert_eq!(
            decode_system(&unknown, &data_of(&unknown), &unknown.accounts).kind,
            "raw"
        );
        assert_eq!(
            decode_system(&truncated, &data_of(&truncated), &truncated.accounts).kind,
            "raw"
        );
        assert_eq!(
            decode_system(&empty, &data_of(&empty), &empty.accounts).kind,
            "raw"
        );
    }

    // --- SPL Token / Token-2022 -----------------------------------------

    #[test]
    fn decodes_spl_token_transfer() {
        let i = ix(
            TOKEN_PROGRAM_ID,
            "03e803000000000000",
            &["source-token-account", "destination-token-account", "owner"],
        );
        let d = decode_token(&i, &data_of(&i), &i.accounts);
        assert_eq!(d.program_label, "SPL Token Program");
        assert_eq!(d.kind, "transfer");
        assert_eq!(d.summary, "Transfer 1000 base units to destin...ccount");
        assert_eq!(
            d.accounts,
            vec![
                "source-token-account".to_string(),
                "destination-token-account".to_string(),
                "owner".to_string()
            ]
        );
    }

    #[test]
    fn decodes_spl_token_transfer_checked() {
        let i = ix(
            TOKEN_PROGRAM_ID,
            "0c44d612000000000006",
            &[
                "source-token-account",
                "mint",
                "recipient-token-account",
                "owner",
            ],
        );
        let d = decode_token(&i, &data_of(&i), &i.accounts);
        assert_eq!(d.kind, "transfer_checked");
        assert_eq!(d.summary, "Transfer 1.2345 tokens to recipi...ccount");
    }

    #[test]
    fn decodes_token2022_transfer_checked() {
        let i = ix(
            TOKEN_2022_PROGRAM_ID,
            "0c40420f000000000006",
            &[
                "source-token-account",
                "mint",
                "recipient-token-account",
                "owner",
            ],
        );
        let d = decode_token(&i, &data_of(&i), &i.accounts);
        assert_eq!(d.program_label, "Token-2022 Program");
        assert_eq!(d.kind, "transfer_checked");
        assert_eq!(d.summary, "Transfer 1 tokens to recipi...ccount");
    }

    #[test]
    fn decodes_token_delegate_and_authority_changes() {
        let zero = "00".repeat(32);
        let approve = ix(
            TOKEN_PROGRAM_ID,
            "04e803000000000000",
            &["source", "delegate", "owner"],
        );
        let set_authority = ix(TOKEN_PROGRAM_ID, &format!("060001000000{zero}"), &[]);
        let clear_authority = ix(TOKEN_2022_PROGRAM_ID, "060300000000", &[]);

        let decoded_approve = decode_token(&approve, &data_of(&approve), &approve.accounts);
        let decoded_set_authority = decode_token(
            &set_authority,
            &data_of(&set_authority),
            &set_authority.accounts,
        );
        let decoded_clear_authority = decode_token(
            &clear_authority,
            &data_of(&clear_authority),
            &clear_authority.accounts,
        );

        assert_eq!(decoded_approve.kind, "approve");
        assert_eq!(
            decoded_approve.summary,
            "Approve 1000 base units for delegate"
        );
        assert_eq!(decoded_set_authority.kind, "set_authority");
        assert_eq!(
            decoded_set_authority.summary,
            format!("Set token mint authority to {SYSTEM_PROGRAM_ID}")
        );
        assert_eq!(decoded_clear_authority.program_label, "Token-2022 Program");
        assert_eq!(
            decoded_clear_authority.summary,
            "Clear token close authority"
        );
    }

    #[test]
    fn decodes_token_mint_burn_and_account_controls() {
        let mint = ix(
            TOKEN_PROGRAM_ID,
            "0e40420f000000000006",
            &["mint", "destination", "authority"],
        );
        let burn = ix(
            TOKEN_PROGRAM_ID,
            "0f40420f000000000006",
            &["source", "mint", "authority"],
        );
        let close = ix(
            TOKEN_PROGRAM_ID,
            "09",
            &["token-account", "destination", "owner"],
        );
        let freeze = ix(
            TOKEN_PROGRAM_ID,
            "0a",
            &["token-account", "mint", "authority"],
        );

        let decoded_mint = decode_token(&mint, &data_of(&mint), &mint.accounts);
        let decoded_burn = decode_token(&burn, &data_of(&burn), &burn.accounts);
        let decoded_close = decode_token(&close, &data_of(&close), &close.accounts);
        let decoded_freeze = decode_token(&freeze, &data_of(&freeze), &freeze.accounts);

        assert_eq!(decoded_mint.kind, "mint_to_checked");
        assert_eq!(decoded_mint.summary, "Mint 1 tokens to destination");
        assert_eq!(decoded_burn.kind, "burn_checked");
        assert_eq!(decoded_burn.summary, "Burn 1 tokens from source");
        assert_eq!(decoded_close.kind, "close_account");
        assert_eq!(decoded_close.summary, "Close token account token-account");
        assert_eq!(decoded_freeze.kind, "freeze_account");
        assert_eq!(decoded_freeze.summary, "Freeze token account token-account");
    }

    #[test]
    fn decodes_token_mint_initialization() {
        let zero = "00".repeat(32);
        let i = ix(TOKEN_PROGRAM_ID, &format!("0006{zero}00000000"), &[]);
        let d = decode_token(&i, &data_of(&i), &i.accounts);
        assert_eq!(d.kind, "initialize_mint");
        assert_eq!(
            d.summary,
            format!(
                "Initialize mint with 6 decimals, mint authority {SYSTEM_PROGRAM_ID}, no freeze authority"
            )
        );
    }

    #[test]
    fn decodes_token_mint_initialization_with_freeze_authority() {
        let i = ix(
            TOKEN_PROGRAM_ID,
            "00060000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000",
            &[],
        );
        let d = decode_token(&i, &data_of(&i), &i.accounts);
        assert_eq!(d.kind, "initialize_mint");
        assert_eq!(
            d.summary,
            format!(
                "Initialize mint with 6 decimals, mint authority {SYSTEM_PROGRAM_ID}, freeze authority {SYSTEM_PROGRAM_ID}"
            )
        );
    }

    #[test]
    fn decodes_token_base_mint_and_burn() {
        let mint = ix(
            TOKEN_PROGRAM_ID,
            "07f401000000000000",
            &["mint", "destination", "authority"],
        );
        let burn = ix(
            TOKEN_PROGRAM_ID,
            "08fa00000000000000",
            &["source", "mint", "authority"],
        );

        let decoded_mint = decode_token(&mint, &data_of(&mint), &mint.accounts);
        let decoded_burn = decode_token(&burn, &data_of(&burn), &burn.accounts);

        assert_eq!(decoded_mint.kind, "mint_to");
        assert_eq!(decoded_mint.summary, "Mint 500 base units to destination");
        assert_eq!(decoded_burn.kind, "burn");
        assert_eq!(decoded_burn.summary, "Burn 250 base units from source");
    }

    #[test]
    fn decodes_token_revoke_and_thaw() {
        let revoke = ix(TOKEN_PROGRAM_ID, "05", &["source", "owner"]);
        let thaw = ix(
            TOKEN_PROGRAM_ID,
            "0b",
            &["token-account", "mint", "authority"],
        );

        let decoded_revoke = decode_token(&revoke, &data_of(&revoke), &revoke.accounts);
        let decoded_thaw = decode_token(&thaw, &data_of(&thaw), &thaw.accounts);

        assert_eq!(decoded_revoke.kind, "revoke");
        assert_eq!(decoded_revoke.summary, "Revoke token delegate");
        assert_eq!(decoded_thaw.kind, "thaw_account");
        assert_eq!(decoded_thaw.summary, "Thaw token account token-account");
    }

    #[test]
    fn decodes_token_approve_checked() {
        let i = ix(
            TOKEN_PROGRAM_ID,
            "0d40e201000000000002",
            &["source", "mint", "delegate", "owner"],
        );
        let d = decode_token(&i, &data_of(&i), &i.accounts);
        assert_eq!(d.kind, "approve_checked");
        assert_eq!(d.summary, "Approve 1234.56 tokens for delegate");
    }

    #[test]
    fn decodes_token_account_initialization_variants() {
        let zero = "00".repeat(32);
        let account2 = ix(TOKEN_PROGRAM_ID, &format!("10{zero}"), &[]);
        let account3 = ix(TOKEN_PROGRAM_ID, &format!("12{zero}"), &[]);
        let mint2 = ix(TOKEN_PROGRAM_ID, &format!("1409{zero}00000000"), &[]);
        let immutable_owner = ix(TOKEN_PROGRAM_ID, "16", &[]);

        let decoded_account2 = decode_token(&account2, &data_of(&account2), &account2.accounts);
        let decoded_account3 = decode_token(&account3, &data_of(&account3), &account3.accounts);
        let decoded_mint2 = decode_token(&mint2, &data_of(&mint2), &mint2.accounts);
        let decoded_immutable_owner = decode_token(
            &immutable_owner,
            &data_of(&immutable_owner),
            &immutable_owner.accounts,
        );

        assert_eq!(decoded_account2.kind, "initialize_account2");
        assert_eq!(
            decoded_account2.summary,
            format!("Initialize token account for owner {SYSTEM_PROGRAM_ID}")
        );
        assert_eq!(decoded_account3.kind, "initialize_account3");
        assert_eq!(
            decoded_account3.summary,
            format!("Initialize token account for owner {SYSTEM_PROGRAM_ID}")
        );
        assert_eq!(decoded_mint2.kind, "initialize_mint2");
        assert_eq!(
            decoded_mint2.summary,
            format!(
                "Initialize mint with 9 decimals, mint authority {SYSTEM_PROGRAM_ID}, no freeze authority"
            )
        );
        assert_eq!(decoded_immutable_owner.kind, "initialize_immutable_owner");
        assert_eq!(
            decoded_immutable_owner.summary,
            "Initialize immutable token account owner"
        );
    }

    #[test]
    fn token_falls_back_for_unknown_discriminator_and_truncated_data() {
        let unknown = ix(TOKEN_PROGRAM_ID, "63", &[]);
        let truncated = ix(TOKEN_PROGRAM_ID, "03", &[]); // transfer with no amount
        let empty = ix(TOKEN_PROGRAM_ID, "", &[]);

        assert_eq!(
            decode_token(&unknown, &data_of(&unknown), &unknown.accounts).kind,
            "raw"
        );
        assert_eq!(
            decode_token(&truncated, &data_of(&truncated), &truncated.accounts).kind,
            "raw"
        );
        assert_eq!(
            decode_token(&empty, &data_of(&empty), &empty.accounts).kind,
            "raw"
        );
    }

    // --- Stake Program ---------------------------------------------------

    #[test]
    fn decodes_stake_program_actions() {
        let zero = "00".repeat(32);
        let authorize = ix(STAKE_PROGRAM_ID, &format!("01000000{zero}01000000"), &[]);
        let delegate = ix(
            STAKE_PROGRAM_ID,
            "02000000",
            &["stake", "vote", "clock", "history", "config", "authority"],
        );
        let withdraw = ix(STAKE_PROGRAM_ID, "0400000040420f0000000000", &[]);

        let decoded_authorize = decode_stake(&authorize, &data_of(&authorize), &authorize.accounts);
        let decoded_delegate = decode_stake(&delegate, &data_of(&delegate), &delegate.accounts);
        let decoded_withdraw = decode_stake(&withdraw, &data_of(&withdraw), &withdraw.accounts);

        assert_eq!(decoded_authorize.program_label, "Stake Program");
        assert_eq!(decoded_authorize.kind, "stake_authority_change");
        assert_eq!(
            decoded_authorize.summary,
            format!("Set stake withdraw authority to {SYSTEM_PROGRAM_ID}")
        );
        assert_eq!(decoded_delegate.kind, "stake_delegate");
        assert_eq!(decoded_delegate.summary, "Delegate stake to vote");
        assert_eq!(decoded_withdraw.kind, "stake_withdraw");
        assert_eq!(decoded_withdraw.summary, "Withdraw 0.001 SOL from stake");
    }

    #[test]
    fn decodes_stake_initialize_and_checked_variants() {
        let zero = "00".repeat(32);
        let initialize = ix(
            STAKE_PROGRAM_ID,
            &format!("00000000{zero}{zero}"),
            &["stake-account"],
        );
        let initialize_no_accounts = ix(STAKE_PROGRAM_ID, &format!("00000000{zero}{zero}"), &[]);
        let initialize_checked = ix(
            STAKE_PROGRAM_ID,
            "09000000",
            &["stake", "authority", "new-staker", "new-withdrawer"],
        );
        let initialize_checked_defaults = ix(STAKE_PROGRAM_ID, "09000000", &[]);
        let authorize_checked = ix(
            STAKE_PROGRAM_ID,
            "0a00000001000000",
            &["stake", "clock", "old-authority", "new-auth"],
        );
        let authorize_checked_default = ix(STAKE_PROGRAM_ID, "0a00000001000000", &[]);
        let authorize_checked_with_seed = ix(
            STAKE_PROGRAM_ID,
            "0b00000000000000",
            &["stake", "clock", "old", "new-staker-auth"],
        );

        let d_init = decode_stake(&initialize, &data_of(&initialize), &initialize.accounts);
        let d_init_none = decode_stake(
            &initialize_no_accounts,
            &data_of(&initialize_no_accounts),
            &initialize_no_accounts.accounts,
        );
        let d_init_checked = decode_stake(
            &initialize_checked,
            &data_of(&initialize_checked),
            &initialize_checked.accounts,
        );
        let d_init_checked_defaults = decode_stake(
            &initialize_checked_defaults,
            &data_of(&initialize_checked_defaults),
            &initialize_checked_defaults.accounts,
        );
        let d_auth_checked = decode_stake(
            &authorize_checked,
            &data_of(&authorize_checked),
            &authorize_checked.accounts,
        );
        let d_auth_checked_default = decode_stake(
            &authorize_checked_default,
            &data_of(&authorize_checked_default),
            &authorize_checked_default.accounts,
        );
        let d_auth_checked_with_seed = decode_stake(
            &authorize_checked_with_seed,
            &data_of(&authorize_checked_with_seed),
            &authorize_checked_with_seed.accounts,
        );

        assert_eq!(d_init.kind, "stake_initialize");
        assert_eq!(
            d_init.summary,
            format!(
                "Initialize stake account stake-account with staker {SYSTEM_PROGRAM_ID} and withdrawer {SYSTEM_PROGRAM_ID}"
            )
        );
        assert_eq!(
            d_init_none.summary,
            format!(
                "Initialize stake account with staker {SYSTEM_PROGRAM_ID} and withdrawer {SYSTEM_PROGRAM_ID}"
            )
        );
        assert_eq!(d_init_checked.kind, "stake_initialize");
        assert_eq!(
            d_init_checked.summary,
            "Initialize stake account with staker new-staker and withdrawer new-withdrawer"
        );
        assert_eq!(
            d_init_checked_defaults.summary,
            "Initialize stake account with staker stake authority and withdrawer withdraw authority"
        );
        assert_eq!(d_auth_checked.kind, "stake_authority_change");
        assert_eq!(
            d_auth_checked.summary,
            "Set stake withdraw authority to new-auth"
        );
        assert_eq!(
            d_auth_checked_default.summary,
            "Set stake withdraw authority to new authority"
        );
        assert_eq!(
            d_auth_checked_with_seed.summary,
            "Set stake staker authority to new-staker-auth"
        );
    }

    #[test]
    fn decodes_stake_authorize_with_seed() {
        let zero = "00".repeat(32);
        let i = ix(STAKE_PROGRAM_ID, &format!("08000000{zero}00000000"), &[]);
        let d = decode_stake(&i, &data_of(&i), &i.accounts);
        assert_eq!(d.kind, "stake_authority_change");
        assert_eq!(
            d.summary,
            format!("Set stake staker authority to {SYSTEM_PROGRAM_ID}")
        );
    }

    #[test]
    fn decodes_stake_movement_and_lifecycle_actions() {
        let split = ix(STAKE_PROGRAM_ID, "030000000065cd1d00000000", &[]);
        let deactivate = ix(STAKE_PROGRAM_ID, "05000000", &[]);
        let lockup6 = ix(STAKE_PROGRAM_ID, "06000000", &[]);
        let lockup12 = ix(STAKE_PROGRAM_ID, "0c000000", &[]);
        let merge = ix(STAKE_PROGRAM_ID, "07000000", &[]);
        let minimum_delegation = ix(STAKE_PROGRAM_ID, "0d000000", &[]);
        let deactivate_delinquent = ix(STAKE_PROGRAM_ID, "0e000000", &["stake", "vote-account"]);
        let deactivate_delinquent_none = ix(STAKE_PROGRAM_ID, "0e000000", &[]);
        let redelegate = ix(
            STAKE_PROGRAM_ID,
            "0f000000",
            &["stake", "old-vote", "new-vote"],
        );
        let redelegate_none = ix(STAKE_PROGRAM_ID, "0f000000", &[]);

        assert_eq!(
            decode_stake(&split, &data_of(&split), &split.accounts).summary,
            "Split 0.5 SOL stake"
        );
        assert_eq!(
            decode_stake(&deactivate, &data_of(&deactivate), &deactivate.accounts).summary,
            "Deactivate stake"
        );
        assert_eq!(
            decode_stake(&lockup6, &data_of(&lockup6), &lockup6.accounts).kind,
            "stake_lockup_change"
        );
        assert_eq!(
            decode_stake(&lockup6, &data_of(&lockup6), &lockup6.accounts).summary,
            "Set stake lockup"
        );
        assert_eq!(
            decode_stake(&lockup12, &data_of(&lockup12), &lockup12.accounts).summary,
            "Set stake lockup"
        );
        assert_eq!(
            decode_stake(&merge, &data_of(&merge), &merge.accounts).summary,
            "Merge stake accounts"
        );
        assert_eq!(
            decode_stake(
                &minimum_delegation,
                &data_of(&minimum_delegation),
                &minimum_delegation.accounts
            )
            .summary,
            "Get minimum stake delegation"
        );
        assert_eq!(
            decode_stake(
                &deactivate_delinquent,
                &data_of(&deactivate_delinquent),
                &deactivate_delinquent.accounts
            )
            .summary,
            "Deactivate delinquent stake for vote account vote-account"
        );
        assert_eq!(
            decode_stake(
                &deactivate_delinquent_none,
                &data_of(&deactivate_delinquent_none),
                &deactivate_delinquent_none.accounts
            )
            .summary,
            "Deactivate delinquent stake"
        );
        assert_eq!(
            decode_stake(&redelegate, &data_of(&redelegate), &redelegate.accounts).summary,
            "Redelegate stake to new-vote"
        );
        assert_eq!(
            decode_stake(
                &redelegate_none,
                &data_of(&redelegate_none),
                &redelegate_none.accounts
            )
            .summary,
            "Redelegate stake"
        );
    }

    #[test]
    fn stake_falls_back_for_unknown_discriminator_and_truncated_data() {
        let unknown = ix(STAKE_PROGRAM_ID, "63000000", &[]);
        let truncated = ix(STAKE_PROGRAM_ID, "01000000", &[]); // authorize with no pubkey
        let empty = ix(STAKE_PROGRAM_ID, "", &[]);

        assert_eq!(
            decode_stake(&unknown, &data_of(&unknown), &unknown.accounts).kind,
            "raw"
        );
        assert_eq!(
            decode_stake(&truncated, &data_of(&truncated), &truncated.accounts).kind,
            "raw"
        );
        assert_eq!(
            decode_stake(&empty, &data_of(&empty), &empty.accounts).kind,
            "raw"
        );
    }

    // --- Address Lookup Table Program -------------------------------------

    #[test]
    fn decodes_address_lookup_table_actions() {
        let zero = "00".repeat(32);
        let create = ix(
            ADDRESS_LOOKUP_TABLE_PROGRAM_ID,
            "000000002a00000000000000ff",
            &[],
        );
        let extend = ix(
            ADDRESS_LOOKUP_TABLE_PROGRAM_ID,
            &format!("020000000100000000000000{zero}"),
            &[],
        );
        let close = ix(ADDRESS_LOOKUP_TABLE_PROGRAM_ID, "04000000", &[]);

        let decoded_create =
            decode_address_lookup_table(&create, &data_of(&create), &create.accounts);
        let decoded_extend =
            decode_address_lookup_table(&extend, &data_of(&extend), &extend.accounts);
        let decoded_close = decode_address_lookup_table(&close, &data_of(&close), &close.accounts);

        assert_eq!(decoded_create.program_label, "Address Lookup Table Program");
        assert_eq!(decoded_create.kind, "lookup_table_create");
        assert_eq!(
            decoded_create.summary,
            "Create address lookup table using recent slot 42"
        );
        assert_eq!(decoded_extend.kind, "lookup_table_extend");
        assert_eq!(
            decoded_extend.summary,
            "Extend address lookup table with 1 address"
        );
        assert_eq!(decoded_close.kind, "lookup_table_close");
        assert_eq!(decoded_close.summary, "Close address lookup table");
    }

    #[test]
    fn decodes_address_lookup_table_freeze_and_deactivate() {
        let freeze = ix(ADDRESS_LOOKUP_TABLE_PROGRAM_ID, "01000000", &[]);
        let deactivate = ix(ADDRESS_LOOKUP_TABLE_PROGRAM_ID, "03000000", &[]);

        let decoded_freeze =
            decode_address_lookup_table(&freeze, &data_of(&freeze), &freeze.accounts);
        let decoded_deactivate =
            decode_address_lookup_table(&deactivate, &data_of(&deactivate), &deactivate.accounts);

        assert_eq!(decoded_freeze.kind, "lookup_table_freeze");
        assert_eq!(decoded_freeze.summary, "Freeze address lookup table");
        assert_eq!(decoded_deactivate.kind, "lookup_table_deactivate");
        assert_eq!(
            decoded_deactivate.summary,
            "Deactivate address lookup table"
        );
    }

    #[test]
    fn alt_falls_back_for_unknown_discriminator_and_empty_data() {
        let unknown = ix(ADDRESS_LOOKUP_TABLE_PROGRAM_ID, "63000000", &[]);
        let empty = ix(ADDRESS_LOOKUP_TABLE_PROGRAM_ID, "", &[]);

        assert_eq!(
            decode_address_lookup_table(&unknown, &data_of(&unknown), &unknown.accounts).kind,
            "raw"
        );
        assert_eq!(
            decode_address_lookup_table(&empty, &data_of(&empty), &empty.accounts).kind,
            "raw"
        );
    }

    // --- Associated Token Account Program ---------------------------------

    #[test]
    fn decodes_associated_token_account_create() {
        let i = ix(
            ASSOCIATED_TOKEN_ACCOUNT_PROGRAM_ID,
            "",
            &["payer", "associated-token-account", "wallet", "mint"],
        );
        let d = decode_associated_token_account(&i, &data_of(&i), &i.accounts);
        assert_eq!(d.program_label, "Associated Token Account Program");
        assert_eq!(d.kind, "create");
        assert_eq!(d.summary, "Create associated token account");
        assert_eq!(
            d.accounts,
            vec![
                "payer".to_string(),
                "associated-token-account".to_string(),
                "wallet".to_string(),
                "mint".to_string()
            ]
        );
    }

    #[test]
    fn decodes_associated_token_account_create_idempotent() {
        let i = ix(ASSOCIATED_TOKEN_ACCOUNT_PROGRAM_ID, "01", &[]);
        let d = decode_associated_token_account(&i, &data_of(&i), &i.accounts);
        assert_eq!(d.kind, "create_idempotent");
        assert_eq!(d.summary, "Create associated token account if needed");
    }

    #[test]
    fn decodes_associated_token_account_recover_nested() {
        let i = ix(ASSOCIATED_TOKEN_ACCOUNT_PROGRAM_ID, "02", &[]);
        let d = decode_associated_token_account(&i, &data_of(&i), &i.accounts);
        assert_eq!(d.kind, "recover_nested");
        assert_eq!(d.summary, "Recover nested associated token account");
    }

    #[test]
    fn ata_falls_back_for_unknown_discriminator() {
        let i = ix(ASSOCIATED_TOKEN_ACCOUNT_PROGRAM_ID, "05", &[]);
        let d = decode_associated_token_account(&i, &data_of(&i), &i.accounts);
        assert_eq!(d.kind, "raw");
        assert_eq!(
            d.summary,
            "Instruction for Associated Token Account Program"
        );
    }

    // --- Memo Program ------------------------------------------------------

    #[test]
    fn decodes_memo_instruction() {
        let i = ix(MEMO_PROGRAM_ID, "68656c6c6f", &[]);
        let d = decode_memo(&i, &data_of(&i), &i.accounts);
        assert_eq!(d.program_label, "Memo Program");
        assert_eq!(d.kind, "memo");
        assert_eq!(d.summary, "Memo: hello");
    }

    #[test]
    fn decodes_memo_empty_and_long_and_invalid_utf8() {
        let empty = ix(MEMO_PROGRAM_ID, "", &[]);
        let long_text = "a".repeat(90);
        let long_hex = long_text
            .as_bytes()
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect::<String>();
        let long = ix(MEMO_PROGRAM_ID, &long_hex, &[]);
        let invalid_utf8 = ix(MEMO_PROGRAM_ID, "ff", &[]);

        let decoded_empty = decode_memo(&empty, &data_of(&empty), &empty.accounts);
        let decoded_long = decode_memo(&long, &data_of(&long), &long.accounts);
        let decoded_invalid = decode_memo(
            &invalid_utf8,
            &data_of(&invalid_utf8),
            &invalid_utf8.accounts,
        );

        assert_eq!(decoded_empty.summary, "Memo");
        assert_eq!(decoded_long.summary, format!("Memo: {}...", "a".repeat(80)));
        assert_eq!(decoded_invalid.kind, "raw");
        assert_eq!(decoded_invalid.summary, "Instruction for Memo Program");
    }

    // --- Compute Budget Program ---------------------------------------------

    #[test]
    fn decodes_compute_budget_instruction() {
        let i = ix(COMPUTE_BUDGET_PROGRAM_ID, "02a0860100", &[]);
        let d = decode_compute_budget(&i, &data_of(&i), &i.accounts);
        assert_eq!(d.program_label, "Compute Budget Program");
        assert_eq!(d.kind, "set_compute_unit_limit");
        assert_eq!(d.summary, "Set compute unit limit to 100000");
    }

    #[test]
    fn decodes_compute_budget_remaining_variants() {
        let request_units = ix(COMPUTE_BUDGET_PROGRAM_ID, "00400d030064000000", &[]);
        let heap_frame = ix(COMPUTE_BUDGET_PROGRAM_ID, "0100000100", &[]);
        let unit_price = ix(COMPUTE_BUDGET_PROGRAM_ID, "038813000000000000", &[]);

        let decoded_units = decode_compute_budget(
            &request_units,
            &data_of(&request_units),
            &request_units.accounts,
        );
        let decoded_heap =
            decode_compute_budget(&heap_frame, &data_of(&heap_frame), &heap_frame.accounts);
        let decoded_price =
            decode_compute_budget(&unit_price, &data_of(&unit_price), &unit_price.accounts);

        assert_eq!(decoded_units.kind, "request_units_deprecated");
        assert_eq!(
            decoded_units.summary,
            "Request 200000 compute units with 100 additional fee"
        );
        assert_eq!(decoded_heap.kind, "request_heap_frame");
        assert_eq!(decoded_heap.summary, "Request 65536 byte heap frame");
        assert_eq!(decoded_price.kind, "set_compute_unit_price");
        assert_eq!(
            decoded_price.summary,
            "Set compute unit price to 5000 micro-lamports"
        );
    }

    #[test]
    fn compute_budget_falls_back_for_unknown_discriminator_and_empty_data() {
        let unknown = ix(COMPUTE_BUDGET_PROGRAM_ID, "09", &[]);
        let empty = ix(COMPUTE_BUDGET_PROGRAM_ID, "", &[]);

        assert_eq!(
            decode_compute_budget(&unknown, &data_of(&unknown), &unknown.accounts).kind,
            "raw"
        );
        assert_eq!(
            decode_compute_budget(&empty, &data_of(&empty), &empty.accounts).kind,
            "raw"
        );
    }

    // --- BPF Upgradeable Loader ----------------------------------------------

    #[test]
    fn decodes_upgradeable_loader_program_admin_actions() {
        let upgrade = ix(
            BPF_UPGRADEABLE_LOADER_PROGRAM_ID,
            "03000000",
            &[
                "program-data",
                "program",
                "buffer",
                "spill",
                "rent",
                "clock",
                "authority",
            ],
        );
        let set_authority = ix(
            BPF_UPGRADEABLE_LOADER_PROGRAM_ID,
            "04000000",
            &["program-data", "authority", "new-authority"],
        );

        let decoded_upgrade =
            decode_upgradeable_loader(&upgrade, &data_of(&upgrade), &upgrade.accounts);
        let decoded_set_authority = decode_upgradeable_loader(
            &set_authority,
            &data_of(&set_authority),
            &set_authority.accounts,
        );

        assert_eq!(decoded_upgrade.program_label, "BPF Upgradeable Loader");
        assert_eq!(decoded_upgrade.kind, "program_upgrade");
        assert_eq!(decoded_upgrade.summary, "Upgrade program program");
        assert_eq!(
            decoded_set_authority.kind,
            "program_upgrade_authority_change"
        );
        assert_eq!(
            decoded_set_authority.summary,
            "Set upgrade authority to new-authority"
        );
    }

    #[test]
    fn decodes_upgradeable_loader_remaining_variants() {
        let buffer_init = ix(BPF_UPGRADEABLE_LOADER_PROGRAM_ID, "00", &[]);
        let buffer_write = ix(BPF_UPGRADEABLE_LOADER_PROGRAM_ID, "0100000010000000", &[]);
        let deploy_with_account = ix(
            BPF_UPGRADEABLE_LOADER_PROGRAM_ID,
            "02",
            &["a", "b", "program-address"],
        );
        let deploy_without_account = ix(BPF_UPGRADEABLE_LOADER_PROGRAM_ID, "02", &[]);
        let clear_authority = ix(BPF_UPGRADEABLE_LOADER_PROGRAM_ID, "04", &[]);
        let close = ix(BPF_UPGRADEABLE_LOADER_PROGRAM_ID, "05", &[]);
        let extend_with_bytes = ix(BPF_UPGRADEABLE_LOADER_PROGRAM_ID, "0600000000100000", &[]);
        let extend_without_bytes = ix(BPF_UPGRADEABLE_LOADER_PROGRAM_ID, "06", &[]);
        let checked_authority_no_account = ix(BPF_UPGRADEABLE_LOADER_PROGRAM_ID, "07", &[]);

        assert_eq!(
            decode_upgradeable_loader(&buffer_init, &data_of(&buffer_init), &buffer_init.accounts)
                .kind,
            "program_buffer_initialize"
        );
        assert_eq!(
            decode_upgradeable_loader(&buffer_init, &data_of(&buffer_init), &buffer_init.accounts)
                .summary,
            "Initialize program buffer"
        );

        assert_eq!(
            decode_upgradeable_loader(
                &buffer_write,
                &data_of(&buffer_write),
                &buffer_write.accounts
            )
            .kind,
            "program_buffer_write"
        );
        assert_eq!(
            decode_upgradeable_loader(
                &buffer_write,
                &data_of(&buffer_write),
                &buffer_write.accounts
            )
            .summary,
            "Write program buffer at offset 16"
        );

        assert_eq!(
            decode_upgradeable_loader(
                &deploy_with_account,
                &data_of(&deploy_with_account),
                &deploy_with_account.accounts
            )
            .summary,
            "Deploy upgradeable program program-address"
        );
        assert_eq!(
            decode_upgradeable_loader(
                &deploy_without_account,
                &data_of(&deploy_without_account),
                &deploy_without_account.accounts
            )
            .summary,
            "Deploy upgradeable program"
        );

        assert_eq!(
            decode_upgradeable_loader(
                &clear_authority,
                &data_of(&clear_authority),
                &clear_authority.accounts
            )
            .summary,
            "Clear upgrade authority"
        );

        assert_eq!(
            decode_upgradeable_loader(&close, &data_of(&close), &close.accounts).kind,
            "program_close"
        );
        assert_eq!(
            decode_upgradeable_loader(&close, &data_of(&close), &close.accounts).summary,
            "Close upgradeable loader account"
        );

        assert_eq!(
            decode_upgradeable_loader(
                &extend_with_bytes,
                &data_of(&extend_with_bytes),
                &extend_with_bytes.accounts
            )
            .kind,
            "program_extend"
        );
        assert_eq!(
            decode_upgradeable_loader(
                &extend_with_bytes,
                &data_of(&extend_with_bytes),
                &extend_with_bytes.accounts
            )
            .summary,
            "Extend program by 4096 bytes"
        );
        assert_eq!(
            decode_upgradeable_loader(
                &extend_without_bytes,
                &data_of(&extend_without_bytes),
                &extend_without_bytes.accounts
            )
            .summary,
            "Extend program"
        );

        assert_eq!(
            decode_upgradeable_loader(
                &checked_authority_no_account,
                &data_of(&checked_authority_no_account),
                &checked_authority_no_account.accounts
            )
            .summary,
            "Set upgrade authority"
        );
    }

    #[test]
    fn upgradeable_loader_falls_back_for_unknown_discriminator_and_empty_data() {
        let unknown = ix(BPF_UPGRADEABLE_LOADER_PROGRAM_ID, "63", &[]);
        let empty = ix(BPF_UPGRADEABLE_LOADER_PROGRAM_ID, "", &[]);
        let truncated_write = ix(BPF_UPGRADEABLE_LOADER_PROGRAM_ID, "01", &[]); // buffer write with no offset

        assert_eq!(
            decode_upgradeable_loader(&unknown, &data_of(&unknown), &unknown.accounts).kind,
            "raw"
        );
        assert_eq!(
            decode_upgradeable_loader(&empty, &data_of(&empty), &empty.accounts).kind,
            "raw"
        );
        assert_eq!(
            decode_upgradeable_loader(
                &truncated_write,
                &data_of(&truncated_write),
                &truncated_write.accounts
            )
            .kind,
            "raw"
        );
    }

    // --- Squads --------------------------------------------------------------

    #[test]
    fn passes_through_squads_config_summary() {
        let i = ix_full(
            SQUADS_PROGRAM_ID,
            "change_threshold",
            "Change threshold to 3",
            "",
            &["member-a"],
        );
        let d = decode_squads(&i, &i.accounts);
        assert_eq!(d.program_label, "Squads");
        assert_eq!(d.kind, "change_threshold");
        assert_eq!(d.summary, "Change threshold to 3");
        assert_eq!(d.accounts, vec!["member-a".to_string()]);
    }

    #[test]
    fn squads_default_summaries_for_known_and_unknown_kinds() {
        let cases = [
            ("add_member", "Add member"),
            ("remove_member", "Remove member"),
            ("change_threshold", "Change threshold"),
            ("set_time_lock", "Set time lock"),
            ("add_spending_limit", "Add spending limit"),
            ("remove_spending_limit", "Remove spending limit"),
            ("set_rent_collector", "Set rent collector"),
            ("something_unmapped", "Squads config action"),
        ];
        for (kind, expected_summary) in cases {
            let i = ix_full(SQUADS_PROGRAM_ID, kind, "", "", &[]);
            let d = decode_squads(&i, &i.accounts);
            assert_eq!(d.kind, kind);
            assert_eq!(d.summary, expected_summary);
        }

        let default_kind = ix_full(SQUADS_PROGRAM_ID, "", "", "", &[]);
        let d = decode_squads(&default_kind, &default_kind.accounts);
        assert_eq!(d.kind, "config");
        assert_eq!(d.summary, "Squads config action");
    }
}
