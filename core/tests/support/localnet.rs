use std::{
    env,
    error::Error,
    net::TcpListener,
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use solana_client::rpc_client::RpcClient as SolanaRpcClient;
use solana_sdk::{
    commitment_config::CommitmentConfig,
    instruction::Instruction,
    program_pack::Pack,
    pubkey::Pubkey,
    signature::{Keypair, Signature, Signer},
    system_instruction, system_program,
    transaction::Transaction,
};
use spl_associated_token_account::{
    get_associated_token_address_with_program_id, instruction::create_associated_token_account,
};
use spl_token::{instruction as token_instruction, state::Mint};
use spl_token_2022::{instruction as token_2022_instruction, state::Mint as Token2022Mint};
use squads_multisig::{
    anchor_lang::AccountDeserialize,
    client::{
        ConfigTransactionCreateAccounts, ConfigTransactionCreateArgs,
        ConfigTransactionExecuteAccounts, MultisigCreateAccountsV2, MultisigCreateArgsV2,
        ProposalCreateAccounts, ProposalCreateArgs, ProposalVoteAccounts, ProposalVoteArgs,
        VaultTransactionCreateAccounts, VaultTransactionExecuteAccounts, config_transaction_create,
        config_transaction_execute, multisig_create_v2, proposal_approve, proposal_create,
        vault_transaction_create, vault_transaction_execute,
    },
    pda::{
        get_multisig_pda, get_program_config_pda, get_proposal_pda, get_transaction_pda,
        get_vault_pda,
    },
    squads_multisig_program::{ID, TransactionMessage, state::ProgramConfig as ProgramConfigState},
    state::{ConfigAction, Member, Multisig, Permission, Permissions},
    vault_transaction::VaultTransactionMessageExt,
};

pub const DEFAULT_CLONE_RPC_URL: &str = "https://api.devnet.solana.com";
const LAMPORTS_PER_FIXTURE: u64 = 20_000_000_000;
const VAULT_SOL_LAMPORTS: u64 = 3_000_000_000;
const VAULT_TOKEN_AMOUNT: u64 = 1_000_000_000;
const VAULT_TOKEN_DECIMALS: u8 = 6;
const LOCAL_VALIDATOR_LEDGER_SHREDS: &str = "10000000";

#[derive(Clone, Debug)]
pub struct FixtureConfig {
    pub browser_member: Pubkey,
    pub threshold: u16,
    pub proposal_count: u64,
    pub vault_count: u8,
    pub memo: String,
}

pub struct FixtureSquad {
    #[cfg(test)]
    #[allow(dead_code)]
    pub creator: Keypair,
    pub multisig: Pubkey,
    pub creator_member: Pubkey,
    pub browser_member: Pubkey,
    pub threshold: u16,
    pub member_count: usize,
    pub vault_fundings: Vec<FixtureVaultFunding>,
    pub proposals: Vec<FixtureProposal>,
}

#[derive(Debug)]
pub struct FixtureProposal {
    pub transaction_index: u64,
    pub proposal: Pubkey,
    pub transaction: Pubkey,
    pub state: FixtureProposalState,
    pub kind: FixtureProposalKind,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FixtureProposalState {
    Active,
    Approved,
    Executed,
}

impl FixtureProposalState {
    pub fn label(self) -> &'static str {
        match self {
            FixtureProposalState::Active => "active",
            FixtureProposalState::Approved => "approved",
            FixtureProposalState::Executed => "executed",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FixtureProposalKind {
    SolTransfer,
    SplTokenTransfer,
    Token2022Transfer,
    UnknownMemo,
    ConfigChange,
}

impl FixtureProposalKind {
    pub fn label(self) -> &'static str {
        match self {
            FixtureProposalKind::SolTransfer => "sol_transfer",
            FixtureProposalKind::SplTokenTransfer => "spl_token_transfer",
            FixtureProposalKind::Token2022Transfer => "token_2022_transfer",
            FixtureProposalKind::UnknownMemo => "unknown_memo",
            FixtureProposalKind::ConfigChange => "config_change",
        }
    }

    fn is_config(self) -> bool {
        matches!(self, FixtureProposalKind::ConfigChange)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct FixtureProposalSpec {
    pub state: FixtureProposalState,
    pub kind: FixtureProposalKind,
}

impl FixtureProposalSpec {
    pub fn new(state: FixtureProposalState, kind: FixtureProposalKind) -> Self {
        Self { state, kind }
    }
}

#[derive(Debug)]
pub struct FixtureVaultFunding {
    pub vault_index: u8,
    pub vault: Pubkey,
    pub sol_lamports: u64,
    pub spl_token: FixtureTokenFunding,
    pub token_2022: FixtureTokenFunding,
}

#[derive(Debug)]
pub struct FixtureTokenFunding {
    pub program_id: Pubkey,
    pub mint: Pubkey,
    pub account: Pubkey,
    pub amount: u64,
    pub decimals: u8,
}

pub fn create_squads_fixture(
    rpc: &SolanaRpcClient,
    config: &FixtureConfig,
) -> Result<FixtureSquad, Box<dyn Error>> {
    let proposal_specs = default_fixture_proposal_specs(config.proposal_count);
    create_squads_fixture_with_specs(rpc, config, &proposal_specs)
}

pub fn create_squads_fixture_with_specs(
    rpc: &SolanaRpcClient,
    config: &FixtureConfig,
    proposal_specs: &[FixtureProposalSpec],
) -> Result<FixtureSquad, Box<dyn Error>> {
    if config.vault_count == 0 {
        return Err("fixture vault_count must be greater than 0".into());
    }
    if proposal_specs.is_empty() {
        return Err("fixture proposal specs must not be empty".into());
    }

    let creator = Keypair::new();
    let creator_member = creator.pubkey();
    let create_key = Keypair::new();
    airdrop(rpc, &creator_member, LAMPORTS_PER_FIXTURE)?;
    if config.browser_member != creator_member {
        airdrop(rpc, &config.browser_member, LAMPORTS_PER_FIXTURE)?;
    }

    let program_id = ID;
    let (program_config_pda, _) = get_program_config_pda(Some(&program_id));
    let program_config_account = rpc.get_account(&program_config_pda)?;
    let mut program_config_data = program_config_account.data.as_slice();
    let program_config = ProgramConfigState::try_deserialize(&mut program_config_data)?;

    let (multisig, _) = get_multisig_pda(&create_key.pubkey(), Some(&program_id));
    send_transaction(
        rpc,
        &[
            multisig_create_v2(
                MultisigCreateAccountsV2 {
                    program_config: program_config_pda,
                    treasury: program_config.treasury,
                    multisig,
                    create_key: create_key.pubkey(),
                    creator: creator.pubkey(),
                    system_program: system_program::id(),
                },
                MultisigCreateArgsV2 {
                    members: vec![
                        fixture_member(creator_member),
                        fixture_member(config.browser_member),
                    ],
                    threshold: config.threshold,
                    time_lock: 0,
                    config_authority: None,
                    rent_collector: None,
                    memo: Some(config.memo.clone()),
                },
                Some(program_id),
            ),
            memo_instruction("Create Squad"),
        ],
        &[&creator, &create_key],
    )?;

    let mut vault_fundings = Vec::new();
    for vault_index in 0..config.vault_count {
        vault_fundings.push(fund_fixture_vault(rpc, &creator, multisig, vault_index)?);
    }

    let mut proposals = Vec::new();
    for (offset, spec) in proposal_specs.iter().enumerate() {
        let index = offset as u64 + 1;
        let accounts = if spec.kind.is_config() {
            create_config_proposal(rpc, &creator, multisig, index, *spec)?
        } else {
            create_vault_proposal(rpc, &creator, multisig, index, *spec, &vault_fundings)?
        };
        apply_executed_fixture_effect(&mut vault_fundings, index, *spec)?;
        proposals.push(FixtureProposal {
            transaction_index: index,
            proposal: accounts.proposal,
            transaction: accounts.transaction,
            state: spec.state,
            kind: spec.kind,
        });
    }
    let final_multisig = get_fixture_multisig(rpc, &multisig)?;

    Ok(FixtureSquad {
        #[cfg(test)]
        creator,
        multisig,
        creator_member,
        browser_member: config.browser_member,
        threshold: final_multisig.threshold,
        member_count: final_multisig.members.len(),
        vault_fundings,
        proposals,
    })
}

pub fn default_fixture_proposal_specs(count: u64) -> Vec<FixtureProposalSpec> {
    (1..=count)
        .map(|index| {
            FixtureProposalSpec::new(
                fixture_proposal_state(index),
                FixtureProposalKind::SolTransfer,
            )
        })
        .collect()
}

pub fn inspection_matrix_fixture_proposal_specs() -> Vec<FixtureProposalSpec> {
    use FixtureProposalKind::{
        ConfigChange, SolTransfer, SplTokenTransfer, Token2022Transfer, UnknownMemo,
    };
    use FixtureProposalState::{Active, Approved, Executed};

    vec![
        FixtureProposalSpec::new(Active, SolTransfer),
        FixtureProposalSpec::new(Approved, SolTransfer),
        FixtureProposalSpec::new(Executed, SolTransfer),
        FixtureProposalSpec::new(Active, SplTokenTransfer),
        FixtureProposalSpec::new(Approved, Token2022Transfer),
        FixtureProposalSpec::new(Approved, UnknownMemo),
        FixtureProposalSpec::new(Active, ConfigChange),
        FixtureProposalSpec::new(Executed, ConfigChange),
    ]
}

pub struct LocalValidator {
    child: Child,
    ledger_dir: PathBuf,
}

impl LocalValidator {
    pub fn start(
        ledger_dir: &Path,
        rpc_port: u16,
        faucet_port: u16,
        clone_rpc_url: &str,
    ) -> Result<Self, Box<dyn Error>> {
        let (program_config, _) = get_program_config_pda(Some(&ID));
        let pubsub_port = validator_pubsub_port(rpc_port)?;
        if faucet_port == rpc_port || faucet_port == pubsub_port {
            return Err(format!(
                "local validator faucet port {faucet_port} conflicts with RPC/PubSub ports"
            )
            .into());
        }
        let gossip_port = free_port_excluding(&[rpc_port, pubsub_port, faucet_port])?;
        let child = Command::new("solana-test-validator")
            .arg("--reset")
            .arg("--quiet")
            .arg("--ledger")
            .arg(ledger_dir)
            .arg("--rpc-port")
            .arg(rpc_port.to_string())
            .arg("--faucet-port")
            .arg(faucet_port.to_string())
            .arg("--gossip-port")
            .arg(gossip_port.to_string())
            .arg("--limit-ledger-size")
            .arg(LOCAL_VALIDATOR_LEDGER_SHREDS)
            .arg("--url")
            .arg(clone_rpc_url)
            .arg("--clone-upgradeable-program")
            .arg(ID.to_string())
            .arg("--clone")
            .arg(program_config.to_string())
            .arg("--account-index")
            .arg("program-id")
            .arg("--account-index")
            .arg("spl-token-owner")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()?;

        Ok(Self {
            child,
            ledger_dir: ledger_dir.to_path_buf(),
        })
    }
}

impl Drop for LocalValidator {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_dir_all(&self.ledger_dir);
    }
}

pub fn new_rpc_client(rpc_url: String) -> SolanaRpcClient {
    SolanaRpcClient::new_with_commitment(rpc_url, CommitmentConfig::confirmed())
}

pub fn wait_for_validator(rpc: &SolanaRpcClient, timeout: Duration) -> Result<(), Box<dyn Error>> {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if rpc.get_latest_blockhash().is_ok() {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(500));
    }
    Err("validator did not become ready before timeout".into())
}

#[allow(dead_code)]
pub fn free_port() -> Result<u16, Box<dyn Error>> {
    free_port_excluding(&[])
}

pub fn free_port_excluding(excluded_ports: &[u16]) -> Result<u16, Box<dyn Error>> {
    for _ in 0..100 {
        let listener = TcpListener::bind("127.0.0.1:0")?;
        let port = listener.local_addr()?.port();
        if !excluded_ports.contains(&port) {
            return Ok(port);
        }
    }

    Err("could not find a free local port outside the excluded set".into())
}

pub fn validator_pubsub_port(rpc_port: u16) -> Result<u16, Box<dyn Error>> {
    rpc_port.checked_add(1).ok_or_else(|| {
        "local validator RPC port cannot be 65535 because PubSub uses rpc-port + 1".into()
    })
}

pub fn validator_reserved_ports(rpc_port: u16) -> Result<[u16; 2], Box<dyn Error>> {
    Ok([rpc_port, validator_pubsub_port(rpc_port)?])
}

fn port_is_available(port: u16) -> bool {
    TcpListener::bind(("127.0.0.1", port)).is_ok()
}

#[allow(dead_code)]
pub fn free_validator_rpc_port() -> Result<u16, Box<dyn Error>> {
    for _ in 0..100 {
        let rpc_listener = TcpListener::bind("127.0.0.1:0")?;
        let rpc_port = rpc_listener.local_addr()?.port();
        let Ok(pubsub_port) = validator_pubsub_port(rpc_port) else {
            continue;
        };
        if port_is_available(pubsub_port) {
            return Ok(rpc_port);
        }
    }

    Err("could not find adjacent free ports for local validator RPC and PubSub".into())
}

pub fn temp_ledger_dir() -> PathBuf {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or_default();
    env::temp_dir().join(format!(
        "cosign-local-validator-{}-{now}",
        std::process::id()
    ))
}

pub fn load_env_files() {
    if let Ok(path) = env::var("COSIGN_ENV_FILE") {
        load_env_file(PathBuf::from(path));
        return;
    }

    let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("core crate has repository parent")
        .to_path_buf();
    load_env_file(repo_root.join(".env"));
    load_env_file(repo_root.join(".env.devnet"));
}

pub fn clone_rpc_url_from_env() -> String {
    env::var("COSIGN_LOCALNET_CLONE_RPC_URL")
        .or_else(|_| env::var("COSIGN_DEVNET_RPC_URL"))
        .unwrap_or_else(|_| DEFAULT_CLONE_RPC_URL.to_string())
}

pub fn browser_member_from_env() -> Option<Pubkey> {
    env::var("COSIGN_LOCALNET_MEMBER_PUBKEY")
        .or_else(|_| env::var("COSIGN_DEVNET_MEMBER"))
        .ok()
        .and_then(|value| value.parse().ok())
}

#[allow(dead_code)]
pub fn redacted_rpc_url(url: &str) -> String {
    let Ok(mut parsed) = url::Url::parse(url) else {
        return url.to_string();
    };

    let query_items = parsed
        .query_pairs()
        .map(|(key, value)| {
            if key == "api-key" {
                (key.to_string(), "REDACTED".to_string())
            } else {
                (key.to_string(), value.to_string())
            }
        })
        .collect::<Vec<_>>();

    if query_items.is_empty() {
        return parsed.to_string();
    }

    parsed.query_pairs_mut().clear().extend_pairs(query_items);
    parsed.to_string()
}

fn create_vault_proposal(
    rpc: &SolanaRpcClient,
    creator: &Keypair,
    multisig: Pubkey,
    index: u64,
    spec: FixtureProposalSpec,
    vault_fundings: &[FixtureVaultFunding],
) -> Result<FixtureProposalAccounts, Box<dyn Error>> {
    let program_id = ID;
    let vault_index = 0;
    let vault_funding = vault_fundings
        .first()
        .ok_or("fixture requires a primary vault")?;
    let vault = vault_funding.vault;
    let instructions =
        fixture_proposal_instructions(rpc, creator, vault_funding, index, spec.kind)?;
    let message = TransactionMessage::try_compile(&vault, &instructions, &[])?;
    let (transaction, _) = get_transaction_pda(&multisig, index, Some(&program_id));
    send_transaction(
        rpc,
        &[
            vault_transaction_create(
                VaultTransactionCreateAccounts {
                    multisig,
                    transaction,
                    creator: creator.pubkey(),
                    rent_payer: creator.pubkey(),
                    system_program: system_program::id(),
                },
                vault_index,
                0,
                &message,
                Some(format!("{} fixture {index}", spec.kind.label())),
                Some(program_id),
            ),
            memo_instruction(format!("Create Vault Transaction {index}")),
        ],
        &[creator],
    )?;

    let (proposal, _) = get_proposal_pda(&multisig, index, Some(&program_id));
    send_transaction(
        rpc,
        &[
            proposal_create(
                ProposalCreateAccounts {
                    multisig,
                    creator: creator.pubkey(),
                    proposal,
                    rent_payer: creator.pubkey(),
                    system_program: system_program::id(),
                },
                ProposalCreateArgs {
                    transaction_index: index,
                    draft: false,
                },
                Some(program_id),
            ),
            memo_instruction(format!("Create Proposal {index}")),
        ],
        &[creator],
    )?;

    if matches!(
        spec.state,
        FixtureProposalState::Approved | FixtureProposalState::Executed
    ) {
        send_transaction(
            rpc,
            &[
                proposal_approve(
                    ProposalVoteAccounts {
                        multisig,
                        proposal,
                        member: creator.pubkey(),
                    },
                    ProposalVoteArgs {
                        memo: Some(format!("Approve fixture {index}")),
                    },
                    Some(program_id),
                ),
                memo_instruction(format!("Approve Proposal {index}")),
            ],
            &[creator],
        )?;
    }

    if spec.state == FixtureProposalState::Executed {
        send_transaction(
            rpc,
            &[
                vault_transaction_execute(
                    VaultTransactionExecuteAccounts {
                        multisig,
                        transaction,
                        member: creator.pubkey(),
                        proposal,
                    },
                    vault_index,
                    0,
                    &message,
                    &[],
                    Some(program_id),
                )?,
                memo_instruction(format!("Execute Proposal {index}")),
            ],
            &[creator],
        )?;
    }

    Ok(FixtureProposalAccounts {
        proposal,
        transaction,
    })
}

fn create_config_proposal(
    rpc: &SolanaRpcClient,
    creator: &Keypair,
    multisig: Pubkey,
    index: u64,
    spec: FixtureProposalSpec,
) -> Result<FixtureProposalAccounts, Box<dyn Error>> {
    let program_id = ID;
    let (transaction, _) = get_transaction_pda(&multisig, index, Some(&program_id));
    send_transaction(
        rpc,
        &[
            config_transaction_create(
                ConfigTransactionCreateAccounts {
                    multisig,
                    creator: creator.pubkey(),
                    rent_payer: creator.pubkey(),
                    transaction,
                    system_program: system_program::id(),
                },
                ConfigTransactionCreateArgs {
                    actions: fixture_config_actions(),
                    memo: Some(format!("{} fixture {index}", spec.kind.label())),
                },
                Some(program_id),
            ),
            memo_instruction(format!("Create Config Transaction {index}")),
        ],
        &[creator],
    )?;

    let (proposal, _) = get_proposal_pda(&multisig, index, Some(&program_id));
    send_transaction(
        rpc,
        &[
            proposal_create(
                ProposalCreateAccounts {
                    multisig,
                    creator: creator.pubkey(),
                    proposal,
                    rent_payer: creator.pubkey(),
                    system_program: system_program::id(),
                },
                ProposalCreateArgs {
                    transaction_index: index,
                    draft: false,
                },
                Some(program_id),
            ),
            memo_instruction(format!("Create Proposal {index}")),
        ],
        &[creator],
    )?;

    if matches!(
        spec.state,
        FixtureProposalState::Approved | FixtureProposalState::Executed
    ) {
        send_transaction(
            rpc,
            &[
                proposal_approve(
                    ProposalVoteAccounts {
                        multisig,
                        proposal,
                        member: creator.pubkey(),
                    },
                    ProposalVoteArgs {
                        memo: Some(format!("Approve fixture {index}")),
                    },
                    Some(program_id),
                ),
                memo_instruction(format!("Approve Proposal {index}")),
            ],
            &[creator],
        )?;
    }

    if spec.state == FixtureProposalState::Executed {
        send_transaction(
            rpc,
            &[
                config_transaction_execute(
                    ConfigTransactionExecuteAccounts {
                        multisig,
                        member: creator.pubkey(),
                        proposal,
                        transaction,
                        rent_payer: Some(creator.pubkey()),
                        system_program: Some(system_program::id()),
                    },
                    Vec::new(),
                    Some(program_id),
                ),
                memo_instruction(format!("Execute Proposal {index}")),
            ],
            &[creator],
        )?;
    }

    Ok(FixtureProposalAccounts {
        proposal,
        transaction,
    })
}

fn fixture_config_actions() -> Vec<ConfigAction> {
    vec![
        ConfigAction::AddMember {
            new_member: Member {
                key: Pubkey::new_unique(),
                permissions: Permissions::from_vec(&[Permission::Initiate, Permission::Vote]),
            },
        },
        ConfigAction::ChangeThreshold { new_threshold: 2 },
        ConfigAction::SetTimeLock { new_time_lock: 60 },
    ]
}

fn fixture_proposal_instructions(
    rpc: &SolanaRpcClient,
    creator: &Keypair,
    vault_funding: &FixtureVaultFunding,
    index: u64,
    kind: FixtureProposalKind,
) -> Result<Vec<Instruction>, Box<dyn Error>> {
    let vault = vault_funding.vault;
    match kind {
        FixtureProposalKind::SolTransfer => {
            let recipient = Pubkey::new_unique();
            Ok(vec![system_instruction::transfer(
                &vault,
                &recipient,
                vault_transfer_lamports(index),
            )])
        }
        FixtureProposalKind::SplTokenTransfer => token_transfer_instructions(
            rpc,
            creator,
            vault,
            &vault_funding.spl_token,
            token_transfer_amount(index),
        ),
        FixtureProposalKind::Token2022Transfer => token_transfer_instructions(
            rpc,
            creator,
            vault,
            &vault_funding.token_2022,
            token_transfer_amount(index),
        ),
        FixtureProposalKind::UnknownMemo => {
            Ok(vec![memo_instruction(format!("Unknown fixture {index}"))])
        }
        FixtureProposalKind::ConfigChange => {
            Err("config proposals do not have vault instructions".into())
        }
    }
}

fn token_transfer_instructions(
    rpc: &SolanaRpcClient,
    payer: &Keypair,
    vault: Pubkey,
    token: &FixtureTokenFunding,
    amount: u64,
) -> Result<Vec<Instruction>, Box<dyn Error>> {
    let recipient = Pubkey::new_unique();
    let destination =
        get_associated_token_address_with_program_id(&recipient, &token.mint, &token.program_id);
    send_transaction(
        rpc,
        &[create_associated_token_account(
            &payer.pubkey(),
            &recipient,
            &token.mint,
            &token.program_id,
        )],
        &[payer],
    )?;

    let transfer = if token.program_id == spl_token::id() {
        token_instruction::transfer_checked(
            &token.program_id,
            &token.account,
            &token.mint,
            &destination,
            &vault,
            &[],
            amount,
            token.decimals,
        )?
    } else {
        token_2022_instruction::transfer_checked(
            &token.program_id,
            &token.account,
            &token.mint,
            &destination,
            &vault,
            &[],
            amount,
            token.decimals,
        )?
    };

    Ok(vec![transfer])
}

fn fixture_proposal_state(index: u64) -> FixtureProposalState {
    match index % 3 {
        0 => FixtureProposalState::Executed,
        1 => FixtureProposalState::Approved,
        _ => FixtureProposalState::Active,
    }
}

fn vault_transfer_lamports(index: u64) -> u64 {
    index * 1_000_000
}

fn token_transfer_amount(index: u64) -> u64 {
    index * 1_000_000
}

fn apply_executed_fixture_effect(
    vault_fundings: &mut [FixtureVaultFunding],
    index: u64,
    spec: FixtureProposalSpec,
) -> Result<(), Box<dyn Error>> {
    if spec.state != FixtureProposalState::Executed {
        return Ok(());
    }

    let primary_vault = vault_fundings
        .first_mut()
        .ok_or("fixture requires a primary vault")?;
    match spec.kind {
        FixtureProposalKind::SolTransfer => {
            primary_vault.sol_lamports = primary_vault
                .sol_lamports
                .checked_sub(vault_transfer_lamports(index))
                .ok_or("executed fixture SOL transfer exceeded vault funding")?;
        }
        FixtureProposalKind::SplTokenTransfer => {
            primary_vault.spl_token.amount = primary_vault
                .spl_token
                .amount
                .checked_sub(token_transfer_amount(index))
                .ok_or("executed fixture SPL transfer exceeded vault funding")?;
        }
        FixtureProposalKind::Token2022Transfer => {
            primary_vault.token_2022.amount = primary_vault
                .token_2022
                .amount
                .checked_sub(token_transfer_amount(index))
                .ok_or("executed fixture Token-2022 transfer exceeded vault funding")?;
        }
        FixtureProposalKind::UnknownMemo | FixtureProposalKind::ConfigChange => {}
    }

    Ok(())
}

fn get_fixture_multisig(
    rpc: &SolanaRpcClient,
    multisig: &Pubkey,
) -> Result<Multisig, Box<dyn Error>> {
    let account = rpc.get_account(multisig)?;
    let mut data = account.data.as_slice();
    Ok(Multisig::try_deserialize(&mut data)?)
}

struct FixtureProposalAccounts {
    proposal: Pubkey,
    transaction: Pubkey,
}

fn memo_instruction(label: impl AsRef<str>) -> Instruction {
    Instruction {
        program_id: memo_program_id(),
        accounts: Vec::new(),
        data: label.as_ref().as_bytes().to_vec(),
    }
}

fn memo_program_id() -> Pubkey {
    "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"
        .parse()
        .expect("valid memo program id")
}

fn fund_fixture_vault(
    rpc: &SolanaRpcClient,
    payer: &Keypair,
    multisig: Pubkey,
    vault_index: u8,
) -> Result<FixtureVaultFunding, Box<dyn Error>> {
    let program_id = ID;
    let (vault, _) = get_vault_pda(&multisig, vault_index, Some(&program_id));

    send_transaction(
        rpc,
        &[system_instruction::transfer(
            &payer.pubkey(),
            &vault,
            VAULT_SOL_LAMPORTS,
        )],
        &[payer],
    )?;

    let spl_token = fund_token_account(rpc, payer, vault, FixtureTokenProgram::Spl)?;
    let token_2022 = fund_token_account(rpc, payer, vault, FixtureTokenProgram::Token2022)?;

    Ok(FixtureVaultFunding {
        vault_index,
        vault,
        sol_lamports: VAULT_SOL_LAMPORTS,
        spl_token,
        token_2022,
    })
}

#[derive(Clone, Copy)]
enum FixtureTokenProgram {
    Spl,
    Token2022,
}

impl FixtureTokenProgram {
    fn program_id(self) -> Pubkey {
        match self {
            FixtureTokenProgram::Spl => spl_token::id(),
            FixtureTokenProgram::Token2022 => spl_token_2022::id(),
        }
    }

    fn mint_len(self) -> usize {
        match self {
            FixtureTokenProgram::Spl => Mint::LEN,
            FixtureTokenProgram::Token2022 => Token2022Mint::LEN,
        }
    }

    fn initialize_mint(
        self,
        mint: &Pubkey,
        mint_authority: &Pubkey,
    ) -> Result<Instruction, Box<dyn Error>> {
        let program_id = self.program_id();
        Ok(match self {
            FixtureTokenProgram::Spl => token_instruction::initialize_mint(
                &program_id,
                mint,
                mint_authority,
                None,
                VAULT_TOKEN_DECIMALS,
            )?,
            FixtureTokenProgram::Token2022 => token_2022_instruction::initialize_mint(
                &program_id,
                mint,
                mint_authority,
                None,
                VAULT_TOKEN_DECIMALS,
            )?,
        })
    }

    fn mint_to(
        self,
        mint: &Pubkey,
        token_account: &Pubkey,
        mint_authority: &Pubkey,
    ) -> Result<Instruction, Box<dyn Error>> {
        let program_id = self.program_id();
        Ok(match self {
            FixtureTokenProgram::Spl => token_instruction::mint_to(
                &program_id,
                mint,
                token_account,
                mint_authority,
                &[],
                VAULT_TOKEN_AMOUNT,
            )?,
            FixtureTokenProgram::Token2022 => token_2022_instruction::mint_to(
                &program_id,
                mint,
                token_account,
                mint_authority,
                &[],
                VAULT_TOKEN_AMOUNT,
            )?,
        })
    }
}

fn fund_token_account(
    rpc: &SolanaRpcClient,
    payer: &Keypair,
    vault: Pubkey,
    token_program: FixtureTokenProgram,
) -> Result<FixtureTokenFunding, Box<dyn Error>> {
    let mint = Keypair::new();
    let token_mint = mint.pubkey();
    let token_program_id = token_program.program_id();
    let token_account =
        get_associated_token_address_with_program_id(&vault, &token_mint, &token_program_id);
    let mint_len = token_program.mint_len();
    let mint_rent = rpc.get_minimum_balance_for_rent_exemption(mint_len)?;

    let instructions = vec![
        system_instruction::create_account(
            &payer.pubkey(),
            &token_mint,
            mint_rent,
            mint_len as u64,
            &token_program_id,
        ),
        token_program.initialize_mint(&token_mint, &payer.pubkey())?,
        create_associated_token_account(&payer.pubkey(), &vault, &token_mint, &token_program_id),
        token_program.mint_to(&token_mint, &token_account, &payer.pubkey())?,
    ];
    send_transaction(rpc, &instructions, &[payer, &mint])?;

    Ok(FixtureTokenFunding {
        program_id: token_program_id,
        mint: token_mint,
        account: token_account,
        amount: VAULT_TOKEN_AMOUNT,
        decimals: VAULT_TOKEN_DECIMALS,
    })
}

fn fixture_member(key: Pubkey) -> Member {
    Member {
        key,
        permissions: Permissions::from_vec(&[
            Permission::Initiate,
            Permission::Vote,
            Permission::Execute,
        ]),
    }
}

fn send_transaction(
    rpc: &SolanaRpcClient,
    instructions: &[solana_sdk::instruction::Instruction],
    signers: &[&Keypair],
) -> Result<Signature, Box<dyn Error>> {
    let payer = signers
        .first()
        .ok_or("transaction requires a payer")?
        .pubkey();
    let blockhash = rpc.get_latest_blockhash()?;
    let transaction =
        Transaction::new_signed_with_payer(instructions, Some(&payer), signers, blockhash);
    Ok(rpc.send_and_confirm_transaction(&transaction)?)
}

pub fn airdrop(
    rpc: &SolanaRpcClient,
    pubkey: &Pubkey,
    lamports: u64,
) -> Result<(), Box<dyn Error>> {
    let signature = rpc.request_airdrop(pubkey, lamports)?;
    let deadline = Instant::now() + Duration::from_secs(30);
    while Instant::now() < deadline {
        if rpc.confirm_transaction(&signature)? {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(250));
    }
    Err(format!("airdrop {signature} was not confirmed").into())
}

fn load_env_file(path: PathBuf) {
    if path.exists() {
        let _ = dotenvy::from_path(path);
    }
}
