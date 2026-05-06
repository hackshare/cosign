use solana_sdk::{
    instruction::Instruction,
    message::Message,
    pubkey::Pubkey,
    signature::Signature,
    system_instruction, system_program,
    transaction::{Transaction, TransactionError},
};
use spl_associated_token_account::{
    get_associated_token_address_with_program_id,
    instruction::create_associated_token_account_idempotent,
};
use squads_multisig::{
    anchor_lang::{InstructionData, ToAccountMetas},
    client::{
        ConfigTransactionExecuteAccounts, ProposalCreateAccounts, ProposalCreateArgs,
        ProposalVoteAccounts, ProposalVoteArgs, VaultTransactionCreateAccounts,
        VaultTransactionExecuteAccounts, config_transaction_execute, proposal_approve,
        proposal_cancel, proposal_create, vault_transaction_create, vault_transaction_execute,
    },
    pda::{get_proposal_pda, get_spending_limit_pda, get_transaction_pda, get_vault_pda},
    squads_multisig_program::{
        CompiledInstruction, MessageAddressTableLookup, TransactionMessage,
        instruction::ProposalReject as ProposalRejectData,
        state::{ConfigAction, ProposalStatus},
    },
    state::{Permission, Permissions},
    vault_transaction::VaultTransactionMessageExt,
};

use crate::{
    rpc::{RpcClient, RpcError},
    squads::{ProposalCompanion, SquadsClient, SquadsError},
    types::{self, ProposalSummary},
};

#[derive(Debug, Clone, Copy)]
pub enum VoteType {
    Approve,
    Reject,
    Cancel,
}

#[derive(Debug, Clone)]
pub struct PreparedTransaction {
    pub message_bytes: Vec<u8>,
    pub fee_payer: String,
    pub recent_blockhash: String,
    pub action: String,
    pub refreshed_proposal: ProposalSummary,
}

#[derive(Debug, Clone)]
pub struct PreparedProposalCreation {
    pub message_bytes: Vec<u8>,
    pub fee_payer: String,
    pub recent_blockhash: String,
    pub action: String,
    pub transaction_index: u64,
    pub proposal_address: String,
    pub transaction_address: String,
    pub vault_address: String,
}

pub struct TokenTransferProposalRequest {
    pub multisig: Pubkey,
    pub vault_index: u8,
    pub member: Pubkey,
    pub recipient_owner: Pubkey,
    pub mint: Pubkey,
    pub amount: u64,
    pub decimals: u8,
    pub token_program_id: Pubkey,
    pub memo: Option<String>,
}

#[derive(Debug, Clone)]
pub struct SimulationResult {
    pub err: Option<String>,
    pub logs: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct TransactionSubmission {
    pub signature: String,
}

#[derive(Debug, Clone)]
pub struct SignatureStatus {
    pub slot: Option<u64>,
    pub status: String,
    pub err: Option<String>,
}

#[derive(Debug, thiserror::Error)]
pub enum TransactionBuildError {
    #[error("RPC error: {0}")]
    Rpc(#[from] RpcError),
    #[error("Squads error: {0}")]
    Squads(#[from] SquadsError),
    #[error("invalid transaction: {0}")]
    InvalidTransaction(String),
    #[error("serialization failed: {0}")]
    Serialization(String),
    #[error("invalid signature")]
    InvalidSignature,
}

pub fn build_sol_transfer_proposal_transaction(
    rpc: RpcClient,
    multisig: Pubkey,
    vault_index: u8,
    member: Pubkey,
    recipient: Pubkey,
    lamports: u64,
    memo: Option<String>,
) -> Result<PreparedProposalCreation, TransactionBuildError> {
    if lamports == 0 {
        return Err(TransactionBuildError::InvalidTransaction(
            "transfer amount must be greater than zero".into(),
        ));
    }

    let client = SquadsClient::new(rpc);
    let multisig_account = client.get_multisig(&multisig)?;
    if !member_has_permission(&multisig_account.members, &member, Permission::Initiate) {
        return Err(TransactionBuildError::InvalidTransaction(
            "member does not have initiate permission".into(),
        ));
    }

    let transaction_index = multisig_account
        .transaction_index
        .checked_add(1)
        .ok_or_else(|| {
            TransactionBuildError::InvalidTransaction("transaction index overflow".into())
        })?;
    let program_id = client.program_id();
    let (vault, _) = get_vault_pda(&multisig, vault_index, Some(&program_id));
    let (transaction, _) = get_transaction_pda(&multisig, transaction_index, Some(&program_id));
    let (proposal, _) = get_proposal_pda(&multisig, transaction_index, Some(&program_id));
    let transfer = system_instruction::transfer(&vault, &recipient, lamports);
    let message = TransactionMessage::try_compile(&vault, &[transfer], &[])
        .map_err(|err| TransactionBuildError::InvalidTransaction(err.to_string()))?;

    let instructions = vec![
        vault_transaction_create(
            VaultTransactionCreateAccounts {
                multisig,
                transaction,
                creator: member,
                rent_payer: member,
                system_program: system_program::id(),
            },
            vault_index,
            0,
            &message,
            memo,
            Some(program_id),
        ),
        proposal_create(
            ProposalCreateAccounts {
                multisig,
                creator: member,
                proposal,
                rent_payer: member,
                system_program: system_program::id(),
            },
            ProposalCreateArgs {
                transaction_index,
                draft: false,
            },
            Some(program_id),
        ),
    ];
    let prepared = prepare_message(client.rpc(), &member, instructions)?;

    Ok(PreparedProposalCreation {
        message_bytes: prepared.message_bytes,
        fee_payer: prepared.fee_payer,
        recent_blockhash: prepared.recent_blockhash,
        action: "Create SOL transfer proposal".into(),
        transaction_index,
        proposal_address: proposal.to_string(),
        transaction_address: transaction.to_string(),
        vault_address: vault.to_string(),
    })
}

pub fn build_token_transfer_proposal_transaction(
    rpc: RpcClient,
    request: TokenTransferProposalRequest,
) -> Result<PreparedProposalCreation, TransactionBuildError> {
    if request.amount == 0 {
        return Err(TransactionBuildError::InvalidTransaction(
            "transfer amount must be greater than zero".into(),
        ));
    }

    let client = SquadsClient::new(rpc);
    let multisig_account = client.get_multisig(&request.multisig)?;
    if !member_has_permission(
        &multisig_account.members,
        &request.member,
        Permission::Initiate,
    ) {
        return Err(TransactionBuildError::InvalidTransaction(
            "member does not have initiate permission".into(),
        ));
    }

    let token_program = supported_token_program(&request.token_program_id)?;
    let transaction_index = multisig_account
        .transaction_index
        .checked_add(1)
        .ok_or_else(|| {
            TransactionBuildError::InvalidTransaction("transaction index overflow".into())
        })?;
    let program_id = client.program_id();
    let (vault, _) = get_vault_pda(&request.multisig, request.vault_index, Some(&program_id));
    let (transaction, _) =
        get_transaction_pda(&request.multisig, transaction_index, Some(&program_id));
    let (proposal, _) = get_proposal_pda(&request.multisig, transaction_index, Some(&program_id));
    let source_token_account = get_associated_token_address_with_program_id(
        &vault,
        &request.mint,
        &request.token_program_id,
    );
    let destination_token_account = get_associated_token_address_with_program_id(
        &request.recipient_owner,
        &request.mint,
        &request.token_program_id,
    );
    let create_destination_token_account = create_associated_token_account_idempotent(
        &vault,
        &request.recipient_owner,
        &request.mint,
        &request.token_program_id,
    );
    let transfer = token_program.transfer_checked(
        &source_token_account,
        &request.mint,
        &destination_token_account,
        &vault,
        request.amount,
        request.decimals,
    )?;
    let message =
        TransactionMessage::try_compile(&vault, &[create_destination_token_account, transfer], &[])
            .map_err(|err| TransactionBuildError::InvalidTransaction(err.to_string()))?;

    let instructions = vec![
        vault_transaction_create(
            VaultTransactionCreateAccounts {
                multisig: request.multisig,
                transaction,
                creator: request.member,
                rent_payer: request.member,
                system_program: system_program::id(),
            },
            request.vault_index,
            0,
            &message,
            request.memo,
            Some(program_id),
        ),
        proposal_create(
            ProposalCreateAccounts {
                multisig: request.multisig,
                creator: request.member,
                proposal,
                rent_payer: request.member,
                system_program: system_program::id(),
            },
            ProposalCreateArgs {
                transaction_index,
                draft: false,
            },
            Some(program_id),
        ),
    ];
    let prepared = prepare_message(client.rpc(), &request.member, instructions)?;

    Ok(PreparedProposalCreation {
        message_bytes: prepared.message_bytes,
        fee_payer: prepared.fee_payer,
        recent_blockhash: prepared.recent_blockhash,
        action: token_program.action_label().into(),
        transaction_index,
        proposal_address: proposal.to_string(),
        transaction_address: transaction.to_string(),
        vault_address: vault.to_string(),
    })
}

pub fn build_vote_transaction(
    rpc: RpcClient,
    multisig: Pubkey,
    transaction_index: u64,
    member: Pubkey,
    vote: VoteType,
) -> Result<PreparedTransaction, TransactionBuildError> {
    let client = SquadsClient::new(rpc);
    let multisig_account = client.get_multisig(&multisig)?;
    let proposal_with_companion = client.get_proposal(&multisig, transaction_index)?;
    validate_vote_status(&proposal_with_companion.proposal.status, vote)?;

    let (proposal, _) = get_proposal_pda(&multisig, transaction_index, Some(&client.program_id()));
    let accounts = ProposalVoteAccounts {
        multisig,
        proposal,
        member,
    };
    let args = ProposalVoteArgs {
        memo: Some(vote.memo().into()),
    };
    let instruction = match vote {
        VoteType::Approve => proposal_approve(accounts, args, Some(client.program_id())),
        VoteType::Reject => proposal_reject(accounts, args, Some(client.program_id())),
        VoteType::Cancel => proposal_cancel(accounts, args, Some(client.program_id())),
    };
    let refreshed = types::proposal_summary(
        transaction_index,
        &proposal_with_companion.proposal,
        multisig_account.threshold,
    );

    prepare_transaction(
        client.rpc(),
        &member,
        vote.action_label(),
        refreshed,
        vec![instruction],
    )
}

pub fn build_execute_transaction(
    rpc: RpcClient,
    multisig: Pubkey,
    transaction_index: u64,
    member: Pubkey,
) -> Result<PreparedTransaction, TransactionBuildError> {
    let client = SquadsClient::new(rpc);
    let multisig_account = client.get_multisig(&multisig)?;
    let proposal_with_companion = client.get_proposal(&multisig, transaction_index)?;
    if !matches!(
        proposal_with_companion.proposal.status,
        ProposalStatus::Approved { .. }
    ) {
        return Err(TransactionBuildError::InvalidTransaction(
            "proposal must be approved before execution".into(),
        ));
    }

    let (proposal, _) = get_proposal_pda(&multisig, transaction_index, Some(&client.program_id()));
    let (transaction, _) =
        get_transaction_pda(&multisig, transaction_index, Some(&client.program_id()));
    let instruction = match &proposal_with_companion.companion {
        ProposalCompanion::Vault(vault) => {
            let message = transaction_message_from_vault(vault);
            vault_transaction_execute(
                VaultTransactionExecuteAccounts {
                    multisig,
                    transaction,
                    member,
                    proposal,
                },
                vault.vault_index,
                vault.ephemeral_signer_bumps.len().try_into().map_err(|_| {
                    TransactionBuildError::InvalidTransaction("too many ephemeral signers".into())
                })?,
                &message,
                &[],
                Some(client.program_id()),
            )
            .map_err(|err| TransactionBuildError::InvalidTransaction(err.to_string()))?
        }
        ProposalCompanion::Config(config) => config_transaction_execute(
            ConfigTransactionExecuteAccounts {
                multisig,
                member,
                proposal,
                transaction,
                rent_payer: Some(member),
                system_program: Some(system_program::id()),
            },
            spending_limit_accounts(&multisig, config, &client.program_id()),
            Some(client.program_id()),
        ),
    };
    let refreshed = types::proposal_summary(
        transaction_index,
        &proposal_with_companion.proposal,
        multisig_account.threshold,
    );

    prepare_transaction(
        client.rpc(),
        &member,
        "Execute proposal",
        refreshed,
        vec![instruction],
    )
}

pub fn simulate_signed_transaction(
    rpc: RpcClient,
    message_bytes: Vec<u8>,
    signature_bytes: Vec<u8>,
) -> Result<SimulationResult, TransactionBuildError> {
    let transaction = signed_transaction(message_bytes, signature_bytes)?;
    let result = rpc.simulate_transaction(&transaction)?;
    Ok(SimulationResult {
        err: result.err,
        logs: result.logs,
    })
}

pub fn simulate_unsigned_message(
    rpc: RpcClient,
    message_bytes: Vec<u8>,
) -> Result<SimulationResult, TransactionBuildError> {
    let message = bincode::deserialize::<Message>(&message_bytes)
        .map_err(|err| TransactionBuildError::Serialization(err.to_string()))?;
    let signatures =
        vec![Signature::default(); usize::from(message.header.num_required_signatures)];
    let transaction = Transaction {
        signatures,
        message,
    };
    let result = rpc.simulate_transaction_without_signature_verification(&transaction)?;
    Ok(SimulationResult {
        err: result.err,
        logs: result.logs,
    })
}

pub fn send_signed_transaction(
    rpc: RpcClient,
    message_bytes: Vec<u8>,
    signature_bytes: Vec<u8>,
) -> Result<TransactionSubmission, TransactionBuildError> {
    let transaction = signed_transaction(message_bytes, signature_bytes)?;
    let signature = rpc.send_transaction(&transaction)?;
    Ok(TransactionSubmission {
        signature: signature.to_string(),
    })
}

pub fn get_signature_status(
    rpc: RpcClient,
    signature: Signature,
) -> Result<SignatureStatus, TransactionBuildError> {
    let snapshot = rpc.get_signature_status(&signature)?;
    Ok(SignatureStatus {
        slot: snapshot.slot,
        status: snapshot.status,
        err: snapshot.err,
    })
}

impl SquadsClient {
    fn rpc(&self) -> &RpcClient {
        self.rpc_ref()
    }
}

fn prepare_transaction(
    rpc: &RpcClient,
    fee_payer: &Pubkey,
    action: impl Into<String>,
    refreshed_proposal: ProposalSummary,
    instructions: Vec<Instruction>,
) -> Result<PreparedTransaction, TransactionBuildError> {
    let prepared = prepare_message(rpc, fee_payer, instructions)?;
    Ok(PreparedTransaction {
        message_bytes: prepared.message_bytes,
        fee_payer: prepared.fee_payer,
        recent_blockhash: prepared.recent_blockhash,
        action: action.into(),
        refreshed_proposal,
    })
}

fn prepare_message(
    rpc: &RpcClient,
    fee_payer: &Pubkey,
    instructions: Vec<Instruction>,
) -> Result<PreparedMessage, TransactionBuildError> {
    let blockhash = rpc.get_latest_blockhash()?;
    let message = Message::new_with_blockhash(&instructions, Some(fee_payer), &blockhash);
    Ok(PreparedMessage {
        message_bytes: message.serialize(),
        fee_payer: fee_payer.to_string(),
        recent_blockhash: blockhash.to_string(),
    })
}

struct PreparedMessage {
    message_bytes: Vec<u8>,
    fee_payer: String,
    recent_blockhash: String,
}

fn signed_transaction(
    message_bytes: Vec<u8>,
    signature_bytes: Vec<u8>,
) -> Result<Transaction, TransactionBuildError> {
    let message = bincode::deserialize::<Message>(&message_bytes)
        .map_err(|err| TransactionBuildError::Serialization(err.to_string()))?;
    let signature = Signature::try_from(signature_bytes.as_slice())
        .map_err(|_| TransactionBuildError::InvalidSignature)?;
    let transaction = Transaction {
        signatures: vec![signature],
        message,
    };
    transaction.verify().map_err(|err| match err {
        TransactionError::SignatureFailure => TransactionBuildError::InvalidSignature,
        other => TransactionBuildError::InvalidTransaction(other.to_string()),
    })?;
    Ok(transaction)
}

fn validate_vote_status(
    status: &ProposalStatus,
    vote: VoteType,
) -> Result<(), TransactionBuildError> {
    let is_valid = match vote {
        VoteType::Approve | VoteType::Reject => matches!(status, ProposalStatus::Active { .. }),
        VoteType::Cancel => matches!(status, ProposalStatus::Approved { .. }),
    };
    if is_valid {
        Ok(())
    } else {
        Err(TransactionBuildError::InvalidTransaction(format!(
            "proposal status does not allow {}",
            vote.action_label()
        )))
    }
}

fn proposal_reject(
    accounts: ProposalVoteAccounts,
    args: ProposalVoteArgs,
    program_id: Option<Pubkey>,
) -> Instruction {
    let program_id = program_id.unwrap_or_else(SquadsClient::default_program_id);
    Instruction {
        accounts: accounts.to_account_metas(Some(false)),
        data: ProposalRejectData { args }.data(),
        program_id,
    }
}

fn spending_limit_accounts(
    multisig: &Pubkey,
    config: &squads_multisig::state::ConfigTransaction,
    program_id: &Pubkey,
) -> Vec<Pubkey> {
    config
        .actions
        .iter()
        .filter_map(|action| match action {
            ConfigAction::AddSpendingLimit { create_key, .. } => {
                Some(get_spending_limit_pda(multisig, create_key, Some(program_id)).0)
            }
            ConfigAction::RemoveSpendingLimit { spending_limit } => Some(*spending_limit),
            _ => None,
        })
        .collect()
}

fn member_has_permission(
    members: &[squads_multisig::state::Member],
    member: &Pubkey,
    permission: Permission,
) -> bool {
    members
        .iter()
        .find(|candidate| candidate.key == *member)
        .map(|candidate| has_permission(&candidate.permissions, permission))
        .unwrap_or(false)
}

fn has_permission(permissions: &Permissions, permission: Permission) -> bool {
    permissions.has(permission)
}

enum SupportedTokenProgram {
    SplToken,
    Token2022,
}

impl SupportedTokenProgram {
    fn transfer_checked(
        &self,
        source: &Pubkey,
        mint: &Pubkey,
        destination: &Pubkey,
        authority: &Pubkey,
        amount: u64,
        decimals: u8,
    ) -> Result<Instruction, TransactionBuildError> {
        match self {
            Self::SplToken => spl_token::instruction::transfer_checked(
                &spl_token::id(),
                source,
                mint,
                destination,
                authority,
                &[],
                amount,
                decimals,
            ),
            Self::Token2022 => spl_token_2022::instruction::transfer_checked(
                &spl_token_2022::id(),
                source,
                mint,
                destination,
                authority,
                &[],
                amount,
                decimals,
            ),
        }
        .map_err(|err| TransactionBuildError::InvalidTransaction(err.to_string()))
    }

    fn action_label(&self) -> &'static str {
        match self {
            Self::SplToken => "Create SPL token transfer proposal",
            Self::Token2022 => "Create Token-2022 transfer proposal",
        }
    }
}

fn supported_token_program(
    token_program_id: &Pubkey,
) -> Result<SupportedTokenProgram, TransactionBuildError> {
    if *token_program_id == spl_token::id() {
        Ok(SupportedTokenProgram::SplToken)
    } else if *token_program_id == spl_token_2022::id() {
        Ok(SupportedTokenProgram::Token2022)
    } else {
        Err(TransactionBuildError::InvalidTransaction(format!(
            "unsupported token program {token_program_id}"
        )))
    }
}

fn transaction_message_from_vault(
    vault: &squads_multisig::squads_multisig_program::state::VaultTransaction,
) -> TransactionMessage {
    TransactionMessage {
        num_signers: vault.message.num_signers,
        num_writable_signers: vault.message.num_writable_signers,
        num_writable_non_signers: vault.message.num_writable_non_signers,
        account_keys: vault.message.account_keys.clone().into(),
        instructions: vault
            .message
            .instructions
            .iter()
            .map(|instruction| CompiledInstruction {
                program_id_index: instruction.program_id_index,
                account_indexes: instruction.account_indexes.clone().into(),
                data: instruction.data.clone().into(),
            })
            .collect::<Vec<_>>()
            .into(),
        address_table_lookups: vault
            .message
            .address_table_lookups
            .iter()
            .map(|lookup| MessageAddressTableLookup {
                account_key: lookup.account_key,
                writable_indexes: lookup.writable_indexes.clone().into(),
                readonly_indexes: lookup.readonly_indexes.clone().into(),
            })
            .collect::<Vec<_>>()
            .into(),
    }
}

impl VoteType {
    fn action_label(self) -> &'static str {
        match self {
            VoteType::Approve => "Approve proposal",
            VoteType::Reject => "Reject proposal",
            VoteType::Cancel => "Cancel proposal",
        }
    }

    fn memo(self) -> &'static str {
        self.action_label()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn supported_token_programs_have_distinct_action_labels() {
        let spl = supported_token_program(&spl_token::id()).expect("SPL token program supported");
        let token_2022 =
            supported_token_program(&spl_token_2022::id()).expect("Token-2022 program supported");

        assert_eq!(spl.action_label(), "Create SPL token transfer proposal");
        assert_eq!(
            token_2022.action_label(),
            "Create Token-2022 transfer proposal"
        );
    }

    #[test]
    fn token_transfer_checked_uses_selected_program() {
        let source = Pubkey::new_unique();
        let mint = Pubkey::new_unique();
        let destination = Pubkey::new_unique();
        let authority = Pubkey::new_unique();

        let spl = SupportedTokenProgram::SplToken
            .transfer_checked(&source, &mint, &destination, &authority, 1_500_000, 6)
            .expect("SPL transfer_checked instruction");
        let token_2022 = SupportedTokenProgram::Token2022
            .transfer_checked(&source, &mint, &destination, &authority, 1_500_000, 6)
            .expect("Token-2022 transfer_checked instruction");

        assert_eq!(spl.program_id, spl_token::id());
        assert_eq!(token_2022.program_id, spl_token_2022::id());
        assert_eq!(spl.accounts, token_2022.accounts);
        assert_eq!(spl.accounts[0].pubkey, source);
        assert_eq!(spl.accounts[1].pubkey, mint);
        assert_eq!(spl.accounts[2].pubkey, destination);
        assert_eq!(spl.accounts[3].pubkey, authority);
    }

    #[test]
    fn unsupported_token_program_is_rejected() {
        let program = Pubkey::new_unique();
        let result = supported_token_program(&program);

        assert!(matches!(
            result,
            Err(TransactionBuildError::InvalidTransaction(message))
                if message.contains("unsupported token program")
                    && message.contains(&program.to_string())
        ));
    }
}
