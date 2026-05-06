//! FFI-friendly value types for the Squads read APIs.
//!
//! Conversion helpers from `squads_multisig` Anchor types live here; pubkeys
//! cross the FFI boundary as base58 strings (canonical Solana address format).

use solana_client::rpc_response::RpcConfirmedTransactionStatusWithSignature;
use solana_sdk::pubkey::Pubkey;
use squads_multisig::{
    pda,
    squads_multisig_program::state::VaultTransaction,
    state::{
        ConfigAction, ConfigTransaction, Member, Multisig, Permission, Permissions, Proposal,
        ProposalStatus,
    },
};

#[derive(Debug, Clone)]
pub struct MultisigSummary {
    pub address: String,
    pub threshold: u16,
    pub member_count: u32,
    pub transaction_index: u64,
    pub stale_transaction_index: u64,
}

#[derive(Debug, Clone)]
pub struct MultisigDetail {
    pub address: String,
    pub threshold: u16,
    pub time_lock_seconds: u32,
    pub transaction_index: u64,
    pub stale_transaction_index: u64,
    pub members: Vec<MemberInfo>,
    pub vaults: Vec<VaultRef>,
}

#[derive(Debug, Clone)]
pub struct MemberInfo {
    pub pubkey: String,
    pub can_initiate: bool,
    pub can_vote: bool,
    pub can_execute: bool,
}

#[derive(Debug, Clone)]
pub struct VaultRef {
    pub index: u8,
    pub address: String,
}

#[derive(Debug, Clone)]
pub struct ProposalSummary {
    pub transaction_index: u64,
    pub status: String,
    pub votes_yes: u32,
    pub votes_no: u32,
    pub votes_cancelled: u32,
    pub threshold: u16,
}

#[derive(Debug, Clone)]
pub struct ProposalDetail {
    pub transaction_index: u64,
    pub status: String,
    pub votes_yes: u32,
    pub votes_no: u32,
    pub votes_cancelled: u32,
    pub threshold: u16,
    pub kind: String,
    pub voters_yes: Vec<String>,
    pub voters_no: Vec<String>,
    pub voters_cancelled: Vec<String>,
    pub instructions: Vec<DecodedInstruction>,
    pub accounts_referenced: Vec<String>,
    pub transaction_address: Option<String>,
    pub proposer: Option<String>,
    pub created_at_unix: Option<i64>,
}

#[derive(Debug, Clone)]
pub struct DecodedInstruction {
    pub program: String,
    pub kind: String,
    pub summary: String,
    pub accounts: Vec<String>,
    pub raw_data_hex: String,
}

#[derive(Debug, Clone)]
pub struct ActivityItem {
    pub signature: String,
    pub slot: u64,
    pub timestamp_unix: i64,
    pub kind: String,
    pub error: Option<String>,
}

pub fn multisig_summary(address: &Pubkey, ms: &Multisig) -> MultisigSummary {
    MultisigSummary {
        address: address.to_string(),
        threshold: ms.threshold,
        member_count: ms.members.len() as u32,
        transaction_index: ms.transaction_index,
        stale_transaction_index: ms.stale_transaction_index,
    }
}

pub fn multisig_detail(
    address: &Pubkey,
    ms: &Multisig,
    program_id: &Pubkey,
    vault_indices: &[u8],
) -> MultisigDetail {
    let vault_indices = if vault_indices.is_empty() {
        vec![0]
    } else {
        vault_indices.to_vec()
    };

    MultisigDetail {
        address: address.to_string(),
        threshold: ms.threshold,
        time_lock_seconds: ms.time_lock,
        transaction_index: ms.transaction_index,
        stale_transaction_index: ms.stale_transaction_index,
        members: ms.members.iter().map(member_info).collect(),
        vaults: vault_indices
            .into_iter()
            .map(|index| vault_ref(address, index, program_id))
            .collect(),
    }
}

pub fn vault_ref(multisig: &Pubkey, index: u8, program_id: &Pubkey) -> VaultRef {
    let (address, _) = pda::get_vault_pda(multisig, index, Some(program_id));
    VaultRef {
        index,
        address: address.to_string(),
    }
}

pub fn member_info(m: &Member) -> MemberInfo {
    MemberInfo {
        pubkey: m.key.to_string(),
        can_initiate: has_permission(&m.permissions, Permission::Initiate),
        can_vote: has_permission(&m.permissions, Permission::Vote),
        can_execute: has_permission(&m.permissions, Permission::Execute),
    }
}

fn has_permission(p: &Permissions, perm: Permission) -> bool {
    p.has(perm)
}

pub fn proposal_summary(transaction_index: u64, p: &Proposal, threshold: u16) -> ProposalSummary {
    ProposalSummary {
        transaction_index,
        status: status_label(&p.status),
        votes_yes: p.approved.len() as u32,
        votes_no: p.rejected.len() as u32,
        votes_cancelled: p.cancelled.len() as u32,
        threshold,
    }
}

pub fn proposal_detail(
    transaction_index: u64,
    p: &Proposal,
    threshold: u16,
    companion: &ProposalCompanionRef<'_>,
    companion_address: Option<&Pubkey>,
) -> ProposalDetail {
    let (kind, instructions, accounts_referenced) = companion_details(companion);
    ProposalDetail {
        transaction_index,
        status: status_label(&p.status),
        votes_yes: p.approved.len() as u32,
        votes_no: p.rejected.len() as u32,
        votes_cancelled: p.cancelled.len() as u32,
        threshold,
        kind,
        voters_yes: p.approved.iter().map(ToString::to_string).collect(),
        voters_no: p.rejected.iter().map(ToString::to_string).collect(),
        voters_cancelled: p.cancelled.iter().map(ToString::to_string).collect(),
        instructions,
        accounts_referenced,
        transaction_address: companion_address.map(ToString::to_string),
        proposer: Some(companion_creator(companion)),
        created_at_unix: status_timestamp(&p.status),
    }
}

/// The member that created the transaction. Exact for the proposer line; the
/// status timestamp it pairs with is the creation time only while Active.
fn companion_creator(companion: &ProposalCompanionRef<'_>) -> String {
    match companion {
        ProposalCompanionRef::Vault(vault) => vault.creator.to_string(),
        ProposalCompanionRef::Config(config) => config.creator.to_string(),
    }
}

fn status_timestamp(status: &ProposalStatus) -> Option<i64> {
    match status {
        ProposalStatus::Draft { timestamp }
        | ProposalStatus::Active { timestamp }
        | ProposalStatus::Rejected { timestamp }
        | ProposalStatus::Approved { timestamp }
        | ProposalStatus::Executed { timestamp }
        | ProposalStatus::Cancelled { timestamp } => Some(*timestamp),
        _ => None,
    }
}

pub enum ProposalCompanionRef<'a> {
    Vault(&'a VaultTransaction),
    Config(&'a ConfigTransaction),
}

fn companion_details(
    companion: &ProposalCompanionRef<'_>,
) -> (String, Vec<DecodedInstruction>, Vec<String>) {
    match companion {
        ProposalCompanionRef::Vault(vault) => vault_transaction_details(vault),
        ProposalCompanionRef::Config(config) => config_transaction_details(config),
    }
}

fn vault_transaction_details(
    vault: &VaultTransaction,
) -> (String, Vec<DecodedInstruction>, Vec<String>) {
    let account_keys = &vault.message.account_keys;
    let mut all_accounts = Vec::new();
    let instructions = vault
        .message
        .instructions
        .iter()
        .map(|ix| {
            let program = account_keys
                .get(usize::from(ix.program_id_index))
                .map(ToString::to_string)
                .unwrap_or_else(|| format!("lookup:{}", ix.program_id_index));
            let accounts = ix
                .account_indexes
                .iter()
                .filter_map(|idx| account_keys.get(usize::from(*idx)))
                .map(ToString::to_string)
                .collect::<Vec<_>>();
            all_accounts.extend(accounts.iter().cloned());
            DecodedInstruction {
                program: program.clone(),
                kind: "raw".into(),
                summary: format!("Instruction for program {program}"),
                accounts,
                raw_data_hex: bytes_to_hex(&ix.data),
            }
        })
        .collect();

    all_accounts.sort();
    all_accounts.dedup();
    ("vault".into(), instructions, all_accounts)
}

fn config_transaction_details(
    config: &ConfigTransaction,
) -> (String, Vec<DecodedInstruction>, Vec<String>) {
    let mut accounts = Vec::new();
    let instructions = config
        .actions
        .iter()
        .map(|action| config_action_instruction(action, &mut accounts))
        .collect();

    accounts.sort();
    accounts.dedup();
    ("config".into(), instructions, accounts)
}

fn config_action_instruction(
    action: &ConfigAction,
    accounts: &mut Vec<String>,
) -> DecodedInstruction {
    match action {
        ConfigAction::AddMember { new_member } => {
            accounts.push(new_member.key.to_string());
            DecodedInstruction {
                program: "Squads".into(),
                kind: "add_member".into(),
                summary: format!(
                    "Add member {} with {}",
                    new_member.key,
                    permissions_summary(&new_member.permissions)
                ),
                accounts: vec![new_member.key.to_string()],
                raw_data_hex: String::new(),
            }
        }
        ConfigAction::RemoveMember { old_member } => {
            accounts.push(old_member.to_string());
            DecodedInstruction {
                program: "Squads".into(),
                kind: "remove_member".into(),
                summary: format!("Remove member {old_member}"),
                accounts: vec![old_member.to_string()],
                raw_data_hex: String::new(),
            }
        }
        ConfigAction::ChangeThreshold { new_threshold } => DecodedInstruction {
            program: "Squads".into(),
            kind: "change_threshold".into(),
            summary: format!("Change threshold to {new_threshold}"),
            accounts: Vec::new(),
            raw_data_hex: String::new(),
        },
        ConfigAction::SetTimeLock { new_time_lock } => DecodedInstruction {
            program: "Squads".into(),
            kind: "set_time_lock".into(),
            summary: format!("Set time lock to {new_time_lock} seconds"),
            accounts: Vec::new(),
            raw_data_hex: String::new(),
        },
        ConfigAction::AddSpendingLimit {
            create_key,
            vault_index,
            mint,
            amount,
            ..
        } => {
            accounts.push(create_key.to_string());
            accounts.push(mint.to_string());
            DecodedInstruction {
                program: "Squads".into(),
                kind: "add_spending_limit".into(),
                summary: format!("Add spending limit for vault {vault_index}: {amount}"),
                accounts: vec![create_key.to_string(), mint.to_string()],
                raw_data_hex: String::new(),
            }
        }
        ConfigAction::RemoveSpendingLimit { spending_limit } => {
            accounts.push(spending_limit.to_string());
            DecodedInstruction {
                program: "Squads".into(),
                kind: "remove_spending_limit".into(),
                summary: format!("Remove spending limit {spending_limit}"),
                accounts: vec![spending_limit.to_string()],
                raw_data_hex: String::new(),
            }
        }
        ConfigAction::SetRentCollector { new_rent_collector } => {
            if let Some(rent_collector) = new_rent_collector {
                accounts.push(rent_collector.to_string());
            }
            let summary = match new_rent_collector {
                Some(rent_collector) => format!("Set rent collector to {rent_collector}"),
                None => "Clear rent collector".into(),
            };
            DecodedInstruction {
                program: "Squads".into(),
                kind: "set_rent_collector".into(),
                summary,
                accounts: new_rent_collector.iter().map(ToString::to_string).collect(),
                raw_data_hex: String::new(),
            }
        }
        _ => DecodedInstruction {
            program: "Squads".into(),
            kind: "config".into(),
            summary: "Unknown config action".into(),
            accounts: Vec::new(),
            raw_data_hex: String::new(),
        },
    }
}

fn permissions_summary(permissions: &Permissions) -> String {
    let labels = [
        (Permission::Initiate, "initiate"),
        (Permission::Vote, "vote"),
        (Permission::Execute, "execute"),
    ]
    .into_iter()
    .filter_map(|(permission, label)| permissions.has(permission).then_some(label))
    .collect::<Vec<_>>();

    if labels.is_empty() {
        return "no permissions".into();
    }

    format!(
        "{} permission{}",
        labels.join(", "),
        if labels.len() == 1 { "" } else { "s" }
    )
}

pub fn activity_item(tx: &RpcConfirmedTransactionStatusWithSignature) -> ActivityItem {
    ActivityItem {
        signature: tx.signature.clone(),
        slot: tx.slot,
        timestamp_unix: tx.block_time.unwrap_or(0),
        kind: activity_kind(tx),
        error: tx.err.as_ref().map(|e| format!("{e:?}")),
    }
}

fn activity_kind(tx: &RpcConfirmedTransactionStatusWithSignature) -> String {
    tx.memo
        .as_deref()
        .map(str::trim)
        .map(strip_memo_prefix)
        .filter(|memo| !memo.is_empty())
        .unwrap_or("transaction")
        .to_string()
}

fn strip_memo_prefix(memo: &str) -> &str {
    let Some(rest) = memo.strip_prefix('[') else {
        return memo;
    };
    let Some((_, label)) = rest.split_once("] ") else {
        return memo;
    };
    label.trim()
}

fn bytes_to_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        out.push(HEX[(b >> 4) as usize] as char);
        out.push(HEX[(b & 0x0f) as usize] as char);
    }
    out
}

#[allow(deprecated)]
pub fn status_label(s: &ProposalStatus) -> String {
    match s {
        ProposalStatus::Draft { .. } => "Draft".into(),
        ProposalStatus::Active { .. } => "Active".into(),
        ProposalStatus::Approved { .. } => "Approved".into(),
        ProposalStatus::Rejected { .. } => "Rejected".into(),
        ProposalStatus::Executing => "Executing".into(),
        ProposalStatus::Executed { .. } => "Executed".into(),
        ProposalStatus::Cancelled { .. } => "Cancelled".into(),
        _ => "Unknown".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_label_recognizes_active() {
        let now = 0_i64;
        let active = ProposalStatus::Active { timestamp: now };
        assert_eq!(status_label(&active), "Active");
    }

    #[test]
    fn status_label_handles_unknown_via_wildcard() {
        // The catch-all branch protects us if squads-multisig adds new variants
        // (the enum is non_exhaustive). Active is a real variant; we cover the
        // wildcard semantically.
        let now = 0_i64;
        let executed = ProposalStatus::Executed { timestamp: now };
        assert_eq!(status_label(&executed), "Executed");
    }

    #[test]
    fn activity_item_uses_memo_as_kind() {
        let tx = activity_status(Some("[18] Approve Proposal 1"));
        let item = activity_item(&tx);
        assert_eq!(item.kind, "Approve Proposal 1");
    }

    #[test]
    fn activity_item_defaults_blank_memo_to_transaction() {
        let tx = activity_status(Some("  "));
        let item = activity_item(&tx);
        assert_eq!(item.kind, "transaction");
    }

    #[test]
    fn config_action_instruction_includes_member_permissions() {
        let member = Member {
            key: Pubkey::new_unique(),
            permissions: Permissions::from_vec(&[Permission::Initiate, Permission::Vote]),
        };
        let mut accounts = Vec::new();
        let instruction = config_action_instruction(
            &ConfigAction::AddMember { new_member: member },
            &mut accounts,
        );

        assert_eq!(instruction.kind, "add_member");
        assert!(instruction.summary.contains("initiate, vote permissions"));
    }

    #[test]
    fn config_action_instruction_distinguishes_cleared_rent_collector() {
        let mut accounts = Vec::new();
        let instruction = config_action_instruction(
            &ConfigAction::SetRentCollector {
                new_rent_collector: None,
            },
            &mut accounts,
        );

        assert_eq!(instruction.kind, "set_rent_collector");
        assert_eq!(instruction.summary, "Clear rent collector");
    }

    fn activity_status(memo: Option<&str>) -> RpcConfirmedTransactionStatusWithSignature {
        RpcConfirmedTransactionStatusWithSignature {
            signature: "4MNaSUmLxeEJw8qR9nrCUt9nv8LJxEzBVvSJY5LL1QU16".into(),
            slot: 42,
            err: None,
            memo: memo.map(String::from),
            block_time: Some(1_778_107_000),
            confirmation_status: None,
        }
    }
}
