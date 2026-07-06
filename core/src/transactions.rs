use solana_sdk::signer::{Signer as _, keypair::Keypair};
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
    anchor_lang::{AccountDeserialize, InstructionData, ToAccountMetas},
    client::{
        ConfigTransactionCreateAccounts, ConfigTransactionCreateArgs,
        ConfigTransactionExecuteAccounts, MultisigCreateAccountsV2, MultisigCreateArgsV2,
        ProposalCreateAccounts, ProposalCreateArgs, ProposalVoteAccounts, ProposalVoteArgs,
        VaultTransactionCreateAccounts, VaultTransactionExecuteAccounts, config_transaction_create,
        config_transaction_execute, multisig_create_v2, proposal_approve, proposal_cancel,
        proposal_create, vault_transaction_create, vault_transaction_execute,
    },
    pda::{
        get_multisig_pda, get_program_config_pda, get_proposal_pda, get_spending_limit_pda,
        get_transaction_pda, get_vault_pda,
    },
    squads_multisig_program::state::{Multisig, ProgramConfig},
    squads_multisig_program::{
        CompiledInstruction, MessageAddressTableLookup, TransactionMessage,
        instruction::ProposalReject as ProposalRejectData,
        state::{ConfigAction, ProposalStatus},
    },
    state::{Member, Permission, Permissions},
    vault_transaction::VaultTransactionMessageExt,
};

use crate::{
    rpc::{RpcClient, RpcError},
    squads::{ProposalCompanion, SquadsClient, SquadsError},
    types::{self, ProposalSummary},
};

pub(crate) fn build_members(creator: Pubkey, extra: &[Pubkey]) -> Vec<Member> {
    let full = Permissions { mask: 7 }; // Initiate | Vote | Execute
    let mut keys = vec![creator];
    for key in extra {
        if !keys.contains(key) {
            keys.push(*key);
        }
    }
    keys.into_iter()
        .map(|key| Member {
            key,
            permissions: full,
        })
        .collect()
}

pub(crate) fn validate_threshold(
    threshold: u16,
    member_count: usize,
) -> Result<(), TransactionBuildError> {
    if threshold == 0 || usize::from(threshold) > member_count {
        return Err(TransactionBuildError::InvalidTransaction(format!(
            "threshold {threshold} must be between 1 and {member_count}"
        )));
    }
    Ok(())
}

pub(crate) fn project_config_members(
    current: &[Member],
    added: &[Pubkey],
    removed: &[Pubkey],
) -> Result<Vec<Member>, TransactionBuildError> {
    let invalid = |m: String| TransactionBuildError::InvalidTransaction(m);
    for key in added {
        if removed.contains(key) {
            return Err(invalid(format!("{key} is both added and removed")));
        }
        if current.iter().any(|m| &m.key == key) {
            return Err(invalid(format!("{key} is already a member")));
        }
    }
    for key in removed {
        if !current.iter().any(|m| &m.key == key) {
            return Err(invalid(format!("{key} is not a member")));
        }
    }
    let full = Permissions { mask: 7 };
    let mut projected: Vec<Member> = current
        .iter()
        .filter(|m| !removed.contains(&m.key))
        .cloned()
        .collect();
    for key in added {
        projected.push(Member {
            key: *key,
            permissions: full,
        });
    }
    Ok(projected)
}

pub(crate) fn validate_config_projection(
    projected: &[Member],
    new_threshold: u16,
) -> Result<(), TransactionBuildError> {
    let invalid = |m: &str| TransactionBuildError::InvalidTransaction(m.to_string());
    if new_threshold == 0 {
        return Err(invalid("threshold must be at least 1"));
    }
    let voters = Multisig::num_voters(projected);
    if usize::from(new_threshold) > voters {
        return Err(TransactionBuildError::InvalidTransaction(format!(
            "threshold {new_threshold} cannot exceed the {voters} voting members"
        )));
    }
    if Multisig::num_proposers(projected) == 0 {
        return Err(invalid(
            "the squad must keep at least one member who can propose",
        ));
    }
    if Multisig::num_executors(projected) == 0 {
        return Err(invalid(
            "the squad must keep at least one member who can execute",
        ));
    }
    Ok(())
}

pub(crate) fn build_config_actions(
    current_threshold: u16,
    new_threshold: u16,
    added: &[Pubkey],
    removed: &[Pubkey],
) -> Vec<ConfigAction> {
    let full = Permissions { mask: 7 };
    let mut actions: Vec<ConfigAction> = Vec::new();
    for key in removed {
        actions.push(ConfigAction::RemoveMember { old_member: *key });
    }
    for key in added {
        actions.push(ConfigAction::AddMember {
            new_member: Member {
                key: *key,
                permissions: full,
            },
        });
    }
    if new_threshold != current_threshold {
        actions.push(ConfigAction::ChangeThreshold { new_threshold });
    }
    actions
}

pub(crate) fn assemble_signatures(
    message: &Message,
    signers: &[(Pubkey, Signature)],
) -> Result<Vec<Signature>, TransactionBuildError> {
    let required = usize::from(message.header.num_required_signatures);
    let mut ordered = vec![Signature::default(); required];
    for (pubkey, signature) in signers {
        let index = message
            .account_keys
            .iter()
            .position(|k| k == pubkey)
            .filter(|i| *i < required)
            .ok_or_else(|| {
                TransactionBuildError::InvalidTransaction(format!(
                    "signer {pubkey} is not a required signer for this message"
                ))
            })?;
        ordered[index] = *signature;
    }
    Ok(ordered)
}

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

#[derive(Debug, Clone)]
pub struct PreparedMultisigCreation {
    pub message_bytes: Vec<u8>,
    pub fee_payer: String,
    pub recent_blockhash: String,
    pub multisig_address: String,
    pub create_key: String,
    pub create_key_signature: Vec<u8>,
}

#[derive(Debug, Clone, Copy)]
pub struct CreateMultisigCost {
    pub network_fee: u64,
    pub rent: u64,
    pub creation_fee: u64,
    pub total: u64,
}

impl CreateMultisigCost {
    pub fn new(network_fee: u64, rent: u64, creation_fee: u64) -> Self {
        Self {
            network_fee,
            rent,
            creation_fee,
            total: network_fee
                .saturating_add(rent)
                .saturating_add(creation_fee),
        }
    }
}

pub fn estimate_create_multisig_cost(
    rpc: RpcClient,
    creator: Pubkey,
    extra_members: Vec<Pubkey>,
    threshold: u16,
) -> Result<CreateMultisigCost, TransactionBuildError> {
    let members = build_members(creator, &extra_members);
    validate_threshold(threshold, members.len())?;
    let member_count = members.len();

    let client = SquadsClient::new(rpc);
    let program_id = client.program_id();
    let (treasury, creation_fee) = fetch_program_config(&client)?;

    let create_key = Keypair::new();
    let (program_config, _) = get_program_config_pda(Some(&program_id));
    let (multisig, _) = get_multisig_pda(&create_key.pubkey(), Some(&program_id));
    let instruction = build_create_multisig_instruction(
        program_config,
        treasury,
        multisig,
        create_key.pubkey(),
        creator,
        members,
        threshold,
        program_id,
    );
    let prepared = prepare_message(client.rpc(), &creator, vec![instruction])?;
    let message = bincode::deserialize::<Message>(&prepared.message_bytes)
        .map_err(|err| TransactionBuildError::Serialization(err.to_string()))?;

    let network_fee = client.rpc().get_fee_for_message(&message)?;
    let rent = client
        .rpc()
        .get_minimum_balance_for_rent_exemption(Multisig::size(member_count))?;
    Ok(CreateMultisigCost::new(network_fee, rent, creation_fee))
}

#[allow(clippy::too_many_arguments)]
pub fn build_create_multisig_instruction(
    program_config: Pubkey,
    treasury: Pubkey,
    multisig: Pubkey,
    create_key: Pubkey,
    creator: Pubkey,
    members: Vec<Member>,
    threshold: u16,
    program_id: Pubkey,
) -> Instruction {
    multisig_create_v2(
        MultisigCreateAccountsV2 {
            program_config,
            treasury,
            multisig,
            create_key,
            creator,
            system_program: system_program::id(),
        },
        MultisigCreateArgsV2 {
            // Autonomous by design: the squad governs itself through member-initiated
            // config proposals. A set config_authority would let an external key rewrite
            // membership unilaterally and would make the chain reject the in-app manage
            // flow (NotSupportedForControlled). Do not wire this to a picker.
            config_authority: None,
            threshold,
            members,
            time_lock: 0,
            rent_collector: None,
            memo: None,
        },
        Some(program_id),
    )
}

pub fn fetch_program_config(client: &SquadsClient) -> Result<(Pubkey, u64), TransactionBuildError> {
    let program_id = client.program_id();
    let (config_pda, _) = get_program_config_pda(Some(&program_id));
    let account = client.rpc().get_account(&config_pda)?;
    let config = ProgramConfig::try_deserialize(&mut account.data.as_slice())
        .map_err(|e| TransactionBuildError::InvalidTransaction(e.to_string()))?;
    Ok((config.treasury, config.multisig_creation_fee))
}

pub fn build_create_multisig_transaction(
    rpc: RpcClient,
    creator: Pubkey,
    extra_members: Vec<Pubkey>,
    threshold: u16,
) -> Result<PreparedMultisigCreation, TransactionBuildError> {
    let members = build_members(creator, &extra_members);
    validate_threshold(threshold, members.len())?;

    let client = SquadsClient::new(rpc);
    let program_id = client.program_id();
    let (treasury, _creation_fee) = fetch_program_config(&client)?;

    let create_key = Keypair::new();
    let (program_config, _) = get_program_config_pda(Some(&program_id));
    let (multisig, _) = get_multisig_pda(&create_key.pubkey(), Some(&program_id));

    let instruction = build_create_multisig_instruction(
        program_config,
        treasury,
        multisig,
        create_key.pubkey(),
        creator,
        members,
        threshold,
        program_id,
    );
    let prepared = prepare_message(client.rpc(), &creator, vec![instruction])?;
    let create_key_signature: [u8; 64] = create_key.sign_message(&prepared.message_bytes).into();

    Ok(PreparedMultisigCreation {
        message_bytes: prepared.message_bytes,
        fee_payer: prepared.fee_payer,
        recent_blockhash: prepared.recent_blockhash,
        multisig_address: multisig.to_string(),
        create_key: create_key.pubkey().to_string(),
        create_key_signature: create_key_signature.to_vec(),
    })
}

pub fn send_multisig_create_transaction(
    rpc: RpcClient,
    message_bytes: Vec<u8>,
    creator_signature: Vec<u8>,
    create_key: Pubkey,
    create_key_signature: Vec<u8>,
) -> Result<TransactionSubmission, TransactionBuildError> {
    let message = bincode::deserialize::<Message>(&message_bytes)
        .map_err(|err| TransactionBuildError::Serialization(err.to_string()))?;
    let creator_sig = Signature::try_from(creator_signature.as_slice())
        .map_err(|_| TransactionBuildError::InvalidSignature)?;
    let create_key_sig = Signature::try_from(create_key_signature.as_slice())
        .map_err(|_| TransactionBuildError::InvalidSignature)?;
    let fee_payer = *message
        .account_keys
        .first()
        .ok_or_else(|| TransactionBuildError::InvalidTransaction("empty message".into()))?;
    let signatures = assemble_signatures(
        &message,
        &[(fee_payer, creator_sig), (create_key, create_key_sig)],
    )?;
    let transaction = Transaction {
        signatures,
        message,
    };
    transaction.verify().map_err(|err| match err {
        TransactionError::SignatureFailure => TransactionBuildError::InvalidSignature,
        other => TransactionBuildError::InvalidTransaction(other.to_string()),
    })?;
    let signature = rpc.send_transaction(&transaction)?;
    Ok(TransactionSubmission {
        signature: signature.to_string(),
    })
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

pub fn build_config_change_proposal_transaction(
    rpc: RpcClient,
    multisig: Pubkey,
    member: Pubkey,
    added_members: Vec<Pubkey>,
    removed_members: Vec<Pubkey>,
    new_threshold: u16,
    memo: Option<String>,
) -> Result<PreparedProposalCreation, TransactionBuildError> {
    let client = SquadsClient::new(rpc);
    let multisig_account = client.get_multisig(&multisig)?;

    if multisig_account.config_authority != Pubkey::default() {
        return Err(TransactionBuildError::InvalidTransaction(
            "this squad's configuration is managed by an external authority".into(),
        ));
    }
    if !member_has_permission(&multisig_account.members, &member, Permission::Initiate) {
        return Err(TransactionBuildError::InvalidTransaction(
            "member does not have initiate permission".into(),
        ));
    }

    let projected =
        project_config_members(&multisig_account.members, &added_members, &removed_members)?;
    validate_config_projection(&projected, new_threshold)?;
    let actions = build_config_actions(
        multisig_account.threshold,
        new_threshold,
        &added_members,
        &removed_members,
    );
    if actions.is_empty() {
        return Err(TransactionBuildError::InvalidTransaction(
            "no configuration changes".into(),
        ));
    }

    let transaction_index = multisig_account
        .transaction_index
        .checked_add(1)
        .ok_or_else(|| {
            TransactionBuildError::InvalidTransaction("transaction index overflow".into())
        })?;
    let program_id = client.program_id();
    let (transaction, _) = get_transaction_pda(&multisig, transaction_index, Some(&program_id));
    let (proposal, _) = get_proposal_pda(&multisig, transaction_index, Some(&program_id));

    let instructions = vec![
        config_transaction_create(
            ConfigTransactionCreateAccounts {
                multisig,
                transaction,
                creator: member,
                rent_payer: member,
                system_program: system_program::id(),
            },
            ConfigTransactionCreateArgs { actions, memo },
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
        action: "Create config change proposal".into(),
        transaction_index,
        proposal_address: proposal.to_string(),
        transaction_address: transaction.to_string(),
        vault_address: String::new(),
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
    use solana_sdk::signer::keypair::Keypair;

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

    #[test]
    fn build_members_puts_creator_first_with_full_permissions() {
        let creator = Pubkey::new_unique();
        let other = Pubkey::new_unique();
        let members = build_members(creator, &[other]);
        assert_eq!(members.len(), 2);
        assert_eq!(members[0].key, creator);
        assert_eq!(members[0].permissions.mask, 7);
        assert_eq!(members[1].key, other);
        assert_eq!(members[1].permissions.mask, 7);
    }

    #[test]
    fn build_members_dedupes_and_keeps_creator_once() {
        let creator = Pubkey::new_unique();
        let dup = Pubkey::new_unique();
        let members = build_members(creator, &[creator, dup, dup]);
        assert_eq!(members.len(), 2);
        assert_eq!(members[0].key, creator);
        assert_eq!(members[1].key, dup);
    }

    #[test]
    fn validate_threshold_rejects_zero_and_over_count() {
        assert!(validate_threshold(0, 3).is_err());
        assert!(validate_threshold(4, 3).is_err());
        assert!(validate_threshold(1, 1).is_ok());
        assert!(validate_threshold(3, 3).is_ok());
    }

    #[test]
    fn assemble_signatures_orders_by_account_key_position() {
        let payer = Keypair::new();
        let cosigner = Keypair::new();
        // A message where both payer and cosigner are required signers.
        let ix = solana_sdk::system_instruction::transfer(&payer.pubkey(), &cosigner.pubkey(), 1);
        let mut message = Message::new(&[ix], Some(&payer.pubkey()));
        // Force cosigner to be a signer slot by marking it required.
        message.header.num_required_signatures = 2;
        if !message.account_keys.contains(&cosigner.pubkey()) {
            message.account_keys.insert(1, cosigner.pubkey());
        }
        let msg_bytes = message.serialize();
        let recovered = bincode::deserialize::<Message>(&msg_bytes).unwrap();
        let payer_sig = Signature::from(keypair_sign(&payer, &msg_bytes));
        let cosigner_sig = Signature::from(keypair_sign(&cosigner, &msg_bytes));
        let ordered = assemble_signatures(
            &recovered,
            &[
                (cosigner.pubkey(), cosigner_sig),
                (payer.pubkey(), payer_sig),
            ],
        )
        .unwrap();
        // Position 0 is the fee payer (payer); position of cosigner matches its key index.
        let payer_index = recovered
            .account_keys
            .iter()
            .position(|k| *k == payer.pubkey())
            .unwrap();
        let cosigner_index = recovered
            .account_keys
            .iter()
            .position(|k| *k == cosigner.pubkey())
            .unwrap();
        assert_eq!(ordered[payer_index], payer_sig);
        assert_eq!(ordered[cosigner_index], cosigner_sig);
    }

    #[test]
    fn create_multisig_instruction_has_expected_accounts() {
        let program_config = Pubkey::new_unique();
        let treasury = Pubkey::new_unique();
        let multisig = Pubkey::new_unique();
        let create_key = Pubkey::new_unique();
        let creator = Pubkey::new_unique();
        let members = build_members(creator, &[]);
        let program_id = crate::squads::SquadsClient::default_program_id();
        let ix = build_create_multisig_instruction(
            program_config,
            treasury,
            multisig,
            create_key,
            creator,
            members,
            1,
            program_id,
        );
        assert_eq!(ix.program_id, program_id);
        // create_key and creator must be signers; multisig, treasury, creator writable.
        let meta = |k: Pubkey| ix.accounts.iter().find(|m| m.pubkey == k).unwrap();
        assert!(meta(create_key).is_signer);
        assert!(meta(creator).is_signer && meta(creator).is_writable);
        assert!(meta(multisig).is_writable);
        assert!(meta(treasury).is_writable);
        assert!(ix.data.len() > 8); // discriminator + args
    }

    #[test]
    fn create_multisig_cost_total_is_sum_of_parts() {
        let cost = CreateMultisigCost::new(5_000, 2_000_000, 100_000);
        assert_eq!(cost.network_fee, 5_000);
        assert_eq!(cost.rent, 2_000_000);
        assert_eq!(cost.creation_fee, 100_000);
        assert_eq!(cost.total, 2_105_000);
    }

    fn member(mask: u8) -> Member {
        Member {
            key: Pubkey::new_unique(),
            permissions: Permissions { mask },
        }
    }

    #[test]
    fn project_config_members_adds_full_perm_and_drops_removed() {
        let a = member(7);
        let b = member(7);
        let current = vec![a.clone(), b.clone()];
        let newk = Pubkey::new_unique();
        let projected = project_config_members(&current, &[newk], &[b.key]).unwrap();
        assert_eq!(projected.len(), 2);
        assert!(projected.iter().any(|m| m.key == a.key));
        assert!(
            projected
                .iter()
                .any(|m| m.key == newk && m.permissions.mask == 7)
        );
        assert!(!projected.iter().any(|m| m.key == b.key));
    }

    #[test]
    fn project_config_members_rejects_contradictions() {
        let a = member(7);
        let current = vec![a.clone()];
        // remove a key that is not a member
        assert!(project_config_members(&current, &[], &[Pubkey::new_unique()]).is_err());
        // add a key that is already a member
        assert!(project_config_members(&current, &[a.key], &[]).is_err());
        // add and remove the same key
        let k = Pubkey::new_unique();
        assert!(project_config_members(&current, &[k], &[k]).is_err());
    }

    #[test]
    fn validate_config_projection_enforces_threshold_and_voters() {
        let projected = vec![member(7)]; // 1 voter/proposer/executor
        assert!(validate_config_projection(&projected, 1).is_ok());
        assert!(validate_config_projection(&projected, 0).is_err()); // threshold >= 1
        assert!(validate_config_projection(&projected, 2).is_err()); // threshold <= voters
        // no voters at all (mask 1 = Initiate only)
        let no_voters = vec![member(1)];
        assert!(validate_config_projection(&no_voters, 1).is_err());
    }

    #[test]
    fn build_config_actions_orders_removes_adds_threshold() {
        let add = Pubkey::new_unique();
        let rem = Pubkey::new_unique();
        let actions = build_config_actions(1, 2, &[add], &[rem]);
        assert!(
            matches!(actions[0], ConfigAction::RemoveMember { old_member } if old_member == rem)
        );
        assert!(
            matches!(&actions[1], ConfigAction::AddMember { new_member } if new_member.key == add)
        );
        assert!(matches!(
            actions[2],
            ConfigAction::ChangeThreshold { new_threshold: 2 }
        ));
        // threshold unchanged -> no ChangeThreshold action
        let actions2 = build_config_actions(1, 1, &[add], &[]);
        assert_eq!(actions2.len(), 1);
        assert!(matches!(&actions2[0], ConfigAction::AddMember { .. }));
    }

    #[test]
    fn config_change_builds_actions_and_validates() {
        let a = member(7);
        let b = member(7);
        let current = vec![a.clone(), b.clone()];
        let add = Pubkey::new_unique();
        let projected = project_config_members(&current, &[add], &[b.key]).unwrap();
        validate_config_projection(&projected, 2).unwrap();
        let actions = build_config_actions(2, 2, &[add], &[b.key]);
        assert_eq!(actions.len(), 2); // remove + add, threshold unchanged
    }

    #[test]
    fn no_proposers_after_projection_is_rejected() {
        // mask 6 = Vote | Execute (no Initiate), so num_proposers == 0 after projection
        let projected = vec![member(6)];
        let result = validate_config_projection(&projected, 1);
        assert!(
            matches!(&result, Err(TransactionBuildError::InvalidTransaction(m)) if m.contains("propose")),
            "expected proposer error, got {result:?}"
        );
    }

    #[test]
    fn no_executors_after_projection_is_rejected() {
        // mask 3 = Initiate | Vote (no Execute), so num_executors == 0 after projection
        let projected = vec![member(3)];
        let result = validate_config_projection(&projected, 1);
        assert!(
            matches!(&result, Err(TransactionBuildError::InvalidTransaction(m)) if m.contains("execute")),
            "expected executor error, got {result:?}"
        );
    }

    // Local test helper: sign raw bytes with a solana Keypair.
    fn keypair_sign(kp: &Keypair, message: &[u8]) -> [u8; 64] {
        kp.sign_message(message).into()
    }
}
