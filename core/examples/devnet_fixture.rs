//! Devnet fixtures — create a real Squads v4 multisig on devnet so the
//! `CosignDevnet` build has live data to load against the relay.
//!
//! Shape: 3 members, threshold 2. Member A is the app's signer (its keypair is
//! saved + its base58 secret printed for import); co-signers B and C are held
//! here. B pre-approves a SOL-transfer proposal (1/2) so the app completes it by
//! co-signing — exercising the app's whole point.
//!
//! Funding: airdrops ~1 SOL to member A; if the devnet faucet rejects it, falls
//! back to a pre-funded payer keypair (`COSIGN_DEVNET_PAYER_KEYPAIR`).
//!
//! Run: `scripts/devnet-fixtures.sh` (or `cargo run --example devnet_fixture`).
//! Reads/writes `.env.devnet` (RPC url in, multisig + member out).

use std::{
    collections::HashMap,
    error::Error,
    fs,
    path::Path,
    thread,
    time::{Duration, Instant},
};

use bip39::Mnemonic;
use cosign_core::keypair_from_mnemonic;
use solana_client::rpc_client::RpcClient as SolanaRpcClient;
use solana_sdk::{
    commitment_config::CommitmentConfig,
    instruction::Instruction,
    native_token::LAMPORTS_PER_SOL,
    pubkey::Pubkey,
    signature::{Keypair, Signer, read_keypair_file, write_keypair_file},
    signer::keypair::keypair_from_seed,
    system_instruction, system_program,
    transaction::Transaction,
};
use squads_multisig::{
    anchor_lang::AccountDeserialize,
    client::{
        MultisigCreateAccountsV2, MultisigCreateArgsV2, ProposalCreateAccounts, ProposalCreateArgs,
        ProposalVoteAccounts, ProposalVoteArgs, VaultTransactionCreateAccounts, multisig_create_v2,
        proposal_approve, proposal_create, vault_transaction_create,
    },
    pda::{
        get_multisig_pda, get_program_config_pda, get_proposal_pda, get_transaction_pda,
        get_vault_pda,
    },
    squads_multisig_program::{ID, TransactionMessage, state::ProgramConfig as ProgramConfigState},
    state::{Member, Multisig, Permission, Permissions},
    vault_transaction::VaultTransactionMessageExt,
};

const ENV_FILE: &str = ".env.devnet";
const DEFAULT_SIGNER_PATH: &str = ".devnet-fixtures/app-signer.json";
const MEMBER_A_MNEMONIC_PATH: &str = ".devnet-fixtures/member-a.mnemonic";
const COSIGNER_B_PATH: &str = ".devnet-fixtures/cosigner-b.json";
const CREATE_KEY_PATH: &str = ".devnet-fixtures/create-key.json";
const AIRDROP_LAMPORTS: u64 = LAMPORTS_PER_SOL;
const VAULT_FUNDING_LAMPORTS: u64 = LAMPORTS_PER_SOL / 5;
const PROPOSAL_TRANSFER_LAMPORTS: u64 = LAMPORTS_PER_SOL / 20;

fn main() -> Result<(), Box<dyn Error>> {
    let env = read_env_file(ENV_FILE);
    let rpc_url = env
        .get("COSIGN_DEVNET_RPC_URL")
        .or_else(|| env.get("COSIGN_RELAY_RPC_URL"))
        .cloned()
        .ok_or("set COSIGN_DEVNET_RPC_URL in .env.devnet")?;
    let rpc = SolanaRpcClient::new_with_commitment(rpc_url.clone(), CommitmentConfig::confirmed());
    println!("RPC: {}", redact(&rpc_url));

    let signer_path = env
        .get("COSIGN_DEVNET_MEMBER_KEYPAIR")
        .cloned()
        .unwrap_or_else(|| DEFAULT_SIGNER_PATH.to_string());
    // Stable keypairs (saved): re-runs reuse the same multisig + members and add a
    // fresh proposal, instead of piling up duplicate squads. Delete the
    // .devnet-fixtures/ keypairs to start a brand-new fixture.
    let (app_signer, member_a_mnemonic) =
        load_or_generate_member_a(MEMBER_A_MNEMONIC_PATH, &signer_path)?;
    let cosigner_b = load_or_generate_keypair(COSIGNER_B_PATH)?;
    let create_key = load_or_generate_keypair(CREATE_KEY_PATH)?;
    println!("App signer (member A): {}", app_signer.pubkey());

    fund_creator(
        &rpc,
        &app_signer,
        env.get("COSIGN_DEVNET_PAYER_KEYPAIR").map(String::as_str),
    )?;

    let program_id = ID;
    let (multisig, _) = get_multisig_pda(&create_key.pubkey(), Some(&program_id));

    if rpc.get_account(&multisig).is_err() {
        let cosigner_c = Keypair::new();
        let (program_config_pda, _) = get_program_config_pda(Some(&program_id));
        let program_config = ProgramConfigState::try_deserialize(
            &mut rpc.get_account(&program_config_pda)?.data.as_slice(),
        )?;
        send(
            &rpc,
            &[multisig_create_v2(
                MultisigCreateAccountsV2 {
                    program_config: program_config_pda,
                    treasury: program_config.treasury,
                    multisig,
                    create_key: create_key.pubkey(),
                    creator: app_signer.pubkey(),
                    system_program: system_program::id(),
                },
                MultisigCreateArgsV2 {
                    members: vec![
                        member(app_signer.pubkey()),
                        member(cosigner_b.pubkey()),
                        member(cosigner_c.pubkey()),
                    ],
                    threshold: 2,
                    time_lock: 0,
                    config_authority: None,
                    rent_collector: None,
                    memo: Some("Cosign devnet fixture".to_string()),
                },
                Some(program_id),
            )],
            &[&app_signer, &create_key],
        )?;
        println!("Multisig created: {multisig}");
    } else {
        println!("Reusing multisig: {multisig}");
    }

    let (vault, _) = get_vault_pda(&multisig, 0, Some(&program_id));
    if rpc.get_balance(&vault)? < VAULT_FUNDING_LAMPORTS {
        send(
            &rpc,
            &[system_instruction::transfer(
                &app_signer.pubkey(),
                &vault,
                VAULT_FUNDING_LAMPORTS,
            )],
            &[&app_signer],
        )?;
        println!(
            "Vault[0] funded: {vault} ({} SOL)",
            sol(VAULT_FUNDING_LAMPORTS)
        );
    }

    // Add a fresh active proposal at the next index; co-signer B pre-approves
    // (1/2), leaving it for the app (member A) to complete.
    let index = next_transaction_index(&rpc, &multisig)?;
    create_proposal(
        &rpc,
        program_id,
        &multisig,
        &vault,
        &app_signer,
        &cosigner_b,
        index,
    )?;
    println!("Proposal #{index} active — co-signer B approved (1/2).");

    update_env_file(
        ENV_FILE,
        &[
            ("COSIGN_DEVNET_MULTISIG", multisig.to_string()),
            ("COSIGN_DEVNET_MEMBER", app_signer.pubkey().to_string()),
        ],
    )?;

    let (proposal, _) = get_proposal_pda(&multisig, index, Some(&program_id));
    println!("\n=== Devnet fixture ready ===");
    println!("Multisig:   {multisig}");
    println!("Vault[0]:   {vault}");
    println!("Proposal:   #{index} ({proposal}) — active, 1/2");
    println!("App signer: {} (member A — 2-of-3)", app_signer.pubkey());
    println!("Keypairs saved in .devnet-fixtures/ — re-run scripts/devnet-fixtures.sh");
    println!("to add another fresh proposal to the same multisig.");
    println!("\nImport into the build (Add hot wallet → Import → recovery phrase):");
    println!("  {member_a_mnemonic}");
    Ok(())
}

fn member(key: Pubkey) -> Member {
    Member {
        key,
        permissions: Permissions::from_vec(&[
            Permission::Initiate,
            Permission::Vote,
            Permission::Execute,
        ]),
    }
}

fn send(
    rpc: &SolanaRpcClient,
    instructions: &[Instruction],
    signers: &[&Keypair],
) -> Result<(), Box<dyn Error>> {
    let payer = signers
        .first()
        .ok_or("transaction requires a payer")?
        .pubkey();
    let blockhash = rpc.get_latest_blockhash()?;
    let transaction =
        Transaction::new_signed_with_payer(instructions, Some(&payer), signers, blockhash);
    rpc.send_and_confirm_transaction(&transaction)?;
    Ok(())
}

fn fund_creator(
    rpc: &SolanaRpcClient,
    creator: &Keypair,
    payer_path: Option<&str>,
) -> Result<(), Box<dyn Error>> {
    let balance = rpc.get_balance(&creator.pubkey())?;
    if balance >= AIRDROP_LAMPORTS / 2 {
        println!("Creator already funded ({} SOL)", sol(balance));
        return Ok(());
    }
    match airdrop(rpc, &creator.pubkey(), AIRDROP_LAMPORTS) {
        Ok(()) => {
            println!("Airdropped {} SOL to the creator", sol(AIRDROP_LAMPORTS));
            return Ok(());
        }
        Err(error) => println!("Airdrop rejected ({error}); falling back to a payer keypair…"),
    }
    let path = payer_path.ok_or(
        "airdrop failed and COSIGN_DEVNET_PAYER_KEYPAIR is unset — fund a keypair with devnet SOL \
         and set its path in .env.devnet",
    )?;
    let payer = read_keypair_file(path).map_err(|e| format!("read payer keypair {path}: {e}"))?;
    let payer_balance = rpc.get_balance(&payer.pubkey())?;
    if payer_balance < AIRDROP_LAMPORTS {
        return Err(format!(
            "payer {} holds only {} SOL — fund it with devnet SOL",
            payer.pubkey(),
            sol(payer_balance)
        )
        .into());
    }
    send(
        rpc,
        &[system_instruction::transfer(
            &payer.pubkey(),
            &creator.pubkey(),
            AIRDROP_LAMPORTS,
        )],
        &[&payer],
    )?;
    println!(
        "Funded the creator with {} SOL from payer {}",
        sol(AIRDROP_LAMPORTS),
        payer.pubkey()
    );
    Ok(())
}

fn airdrop(rpc: &SolanaRpcClient, pubkey: &Pubkey, lamports: u64) -> Result<(), Box<dyn Error>> {
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

fn load_or_generate_keypair(path: &str) -> Result<Keypair, Box<dyn Error>> {
    if Path::new(path).exists() {
        return read_keypair_file(path).map_err(|e| format!("read keypair {path}: {e}").into());
    }
    if let Some(parent) = Path::new(path).parent() {
        fs::create_dir_all(parent)?;
    }
    let keypair = Keypair::new();
    write_keypair_file(&keypair, path).map_err(|e| format!("save keypair {path}: {e}"))?;
    Ok(keypair)
}

/// Member A is mnemonic-derived (via the same `keypair_from_mnemonic` the app's
/// recovery-phrase import uses), so a tester can import it with the printed
/// phrase. The mnemonic is saved for re-runs; the derived keypair is also written
/// to `signer_path` for the debug `--cosign-seed-signer` path + the UI walkthrough.
fn load_or_generate_member_a(
    mnemonic_path: &str,
    signer_path: &str,
) -> Result<(Keypair, String), Box<dyn Error>> {
    let mnemonic = if Path::new(mnemonic_path).exists() {
        fs::read_to_string(mnemonic_path)?.trim().to_string()
    } else {
        if let Some(parent) = Path::new(mnemonic_path).parent() {
            fs::create_dir_all(parent)?;
        }
        let generated = Mnemonic::generate(24)
            .map_err(|e| format!("generate mnemonic: {e}"))?
            .to_string();
        fs::write(mnemonic_path, &generated)?;
        generated
    };
    let derived = keypair_from_mnemonic(mnemonic.clone(), String::new())?;
    let keypair = keypair_from_seed(&derived.private_key)?;
    write_keypair_file(&keypair, signer_path)
        .map_err(|e| format!("save app signer to {signer_path}: {e}"))?;
    Ok((keypair, mnemonic))
}

fn next_transaction_index(rpc: &SolanaRpcClient, multisig: &Pubkey) -> Result<u64, Box<dyn Error>> {
    let account = rpc.get_account(multisig)?;
    let state = Multisig::try_deserialize(&mut account.data.as_slice())?;
    Ok(state.transaction_index + 1)
}

/// Vault SOL-transfer proposal at `index`, pre-approved by co-signer B (1/2).
#[allow(clippy::too_many_arguments)]
fn create_proposal(
    rpc: &SolanaRpcClient,
    program_id: Pubkey,
    multisig: &Pubkey,
    vault: &Pubkey,
    creator: &Keypair,
    cosigner_b: &Keypair,
    index: u64,
) -> Result<(), Box<dyn Error>> {
    let transfer =
        system_instruction::transfer(vault, &creator.pubkey(), PROPOSAL_TRANSFER_LAMPORTS);
    let message = TransactionMessage::try_compile(vault, &[transfer], &[])?;
    let (transaction, _) = get_transaction_pda(multisig, index, Some(&program_id));
    send(
        rpc,
        &[vault_transaction_create(
            VaultTransactionCreateAccounts {
                multisig: *multisig,
                transaction,
                creator: creator.pubkey(),
                rent_payer: creator.pubkey(),
                system_program: system_program::id(),
            },
            0,
            0,
            &message,
            Some(format!("Devnet fixture #{index}: 0.05 SOL transfer")),
            Some(program_id),
        )],
        &[creator],
    )?;
    let (proposal, _) = get_proposal_pda(multisig, index, Some(&program_id));
    send(
        rpc,
        &[proposal_create(
            ProposalCreateAccounts {
                multisig: *multisig,
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
        )],
        &[creator],
    )?;
    send(
        rpc,
        &[proposal_approve(
            ProposalVoteAccounts {
                multisig: *multisig,
                proposal,
                member: cosigner_b.pubkey(),
            },
            ProposalVoteArgs { memo: None },
            Some(program_id),
        )],
        &[creator, cosigner_b],
    )?;
    Ok(())
}

fn read_env_file(path: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();
    let Ok(contents) = fs::read_to_string(path) else {
        return map;
    };
    for line in contents.lines() {
        let trimmed = line.trim_start();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let line = trimmed.strip_prefix("export ").unwrap_or(trimmed);
        if let Some((key, value)) = line.split_once('=') {
            let value = value
                .trim()
                .trim_matches('"')
                .trim_matches('\'')
                .to_string();
            map.insert(key.trim().to_string(), value);
        }
    }
    map
}

fn update_env_file(path: &str, updates: &[(&str, String)]) -> Result<(), Box<dyn Error>> {
    let contents = fs::read_to_string(path).unwrap_or_default();
    let mut lines: Vec<String> = contents.lines().map(String::from).collect();
    for (key, value) in updates {
        let prefix = format!("{key}=");
        let replacement = format!("{key}={value}");
        if let Some(line) = lines.iter_mut().find(|line| {
            let trimmed = line.trim_start();
            let trimmed = trimmed.strip_prefix("export ").unwrap_or(trimmed);
            trimmed.starts_with(&prefix)
        }) {
            *line = replacement;
        } else {
            lines.push(replacement);
        }
    }
    fs::write(path, format!("{}\n", lines.join("\n")))?;
    Ok(())
}

fn sol(lamports: u64) -> String {
    format!("{:.4}", lamports as f64 / LAMPORTS_PER_SOL as f64)
}

fn redact(url: &str) -> String {
    match url.split_once("?api-key=") {
        Some((base, _)) => format!("{base}?api-key=***"),
        None => url.to_string(),
    }
}
