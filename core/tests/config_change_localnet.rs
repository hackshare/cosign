//! On-chain round trip for config-change proposals against a local validator
//! with the Squads program loaded.
//!
//! Run manually: `cargo test --test config_change_localnet -- --ignored`
//! Requires a running `solana-test-validator` with the squads_multisig program
//! cloned from devnet (or deployed) and its ProgramConfig account initialised.

use std::{error::Error, thread, time::Duration, time::Instant};

use solana_sdk::signature::{Keypair, Signer};
use squads_multisig::{anchor_lang::AccountDeserialize, state::Multisig};

use cosign_core::{
    rpc::RpcClient,
    transactions::{self, VoteType},
};
use squads_multisig::state::{Member, Permissions};

#[allow(dead_code)]
#[path = "support/localnet.rs"]
mod localnet;

fn wait_for_signature(
    rpc: &solana_client::rpc_client::RpcClient,
    sig_str: &str,
) -> Result<(), Box<dyn Error>> {
    let sig: solana_sdk::signature::Signature = sig_str.parse()?;
    let deadline = Instant::now() + Duration::from_secs(30);
    while Instant::now() < deadline {
        if rpc.confirm_transaction(&sig)? {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(250));
    }
    Err(format!("transaction {sig_str} was not confirmed in time").into())
}

#[test]
#[ignore = "spawns solana-test-validator and clones Squads from devnet"]
fn config_change_proposal_round_trip() -> Result<(), Box<dyn Error>> {
    localnet::load_env_files();

    let clone_rpc_url = localnet::clone_rpc_url_from_env();
    let rpc_port = localnet::free_validator_rpc_port()?;
    let reserved = localnet::validator_reserved_ports(rpc_port)?;
    let faucet_port = localnet::free_port_excluding(&reserved)?;
    let ledger_dir = localnet::temp_ledger_dir();
    let _validator =
        localnet::LocalValidator::start(&ledger_dir, rpc_port, faucet_port, &clone_rpc_url)?;

    let rpc_url = format!("http://127.0.0.1:{rpc_port}");
    let raw_rpc = localnet::new_rpc_client(rpc_url.clone());
    localnet::wait_for_validator(&raw_rpc, Duration::from_secs(120))?;

    let creator = Keypair::new();
    localnet::airdrop(&raw_rpc, &creator.pubkey(), 2_000_000_000)?;

    // Create a 1-of-1 multisig.
    let prepared = transactions::build_create_multisig_transaction(
        RpcClient::new(rpc_url.clone()),
        creator.pubkey(),
        vec![],
        1,
    )?;
    let creator_sig: Vec<u8> = creator
        .sign_message(&prepared.message_bytes)
        .as_ref()
        .to_vec();
    let create_key: solana_sdk::pubkey::Pubkey = prepared.create_key.parse()?;
    let submission = transactions::send_multisig_create_transaction(
        RpcClient::new(rpc_url.clone()),
        prepared.message_bytes,
        creator_sig,
        create_key,
        prepared.create_key_signature,
    )?;
    wait_for_signature(&raw_rpc, &submission.signature)?;

    let multisig: solana_sdk::pubkey::Pubkey = prepared.multisig_address.parse()?;

    // Build a config-change proposal: add a second member, raise threshold to 2.
    let new_member = solana_sdk::pubkey::Pubkey::new_unique();
    let full = Permissions { mask: 7 };
    let desired_members = vec![
        Member {
            key: creator.pubkey(),
            permissions: full,
        },
        Member {
            key: new_member,
            permissions: full,
        },
    ];
    // The expected current state: 1-of-1 with creator only (matches the just-created multisig).
    let expected_members = vec![Member {
        key: creator.pubkey(),
        permissions: full,
    }];
    let prepared_proposal = transactions::build_config_change_proposal_transaction(
        RpcClient::new(rpc_url.clone()),
        multisig,
        creator.pubkey(),
        desired_members,
        2,
        0,
        None,
        expected_members,
        1,
        0,
        None,
        Some("add member and raise threshold".into()),
    )?;
    let proposal_sig: Vec<u8> = creator
        .sign_message(&prepared_proposal.message_bytes)
        .as_ref()
        .to_vec();
    let submission = transactions::send_signed_transaction(
        RpcClient::new(rpc_url.clone()),
        prepared_proposal.message_bytes,
        proposal_sig,
    )?;
    wait_for_signature(&raw_rpc, &submission.signature)?;

    let transaction_index = prepared_proposal.transaction_index;

    // Approve the proposal.
    let prepared_vote = transactions::build_vote_transaction(
        RpcClient::new(rpc_url.clone()),
        multisig,
        transaction_index,
        creator.pubkey(),
        VoteType::Approve,
    )?;
    let vote_sig: Vec<u8> = creator
        .sign_message(&prepared_vote.message_bytes)
        .as_ref()
        .to_vec();
    let submission = transactions::send_signed_transaction(
        RpcClient::new(rpc_url.clone()),
        prepared_vote.message_bytes,
        vote_sig,
    )?;
    wait_for_signature(&raw_rpc, &submission.signature)?;

    // Execute the proposal.
    let prepared_execute = transactions::build_execute_transaction(
        RpcClient::new(rpc_url.clone()),
        multisig,
        transaction_index,
        creator.pubkey(),
    )?;
    let execute_sig: Vec<u8> = creator
        .sign_message(&prepared_execute.message_bytes)
        .as_ref()
        .to_vec();
    let submission = transactions::send_signed_transaction(
        RpcClient::new(rpc_url.clone()),
        prepared_execute.message_bytes,
        execute_sig,
    )?;
    wait_for_signature(&raw_rpc, &submission.signature)?;

    // Read the multisig back and assert the config change was applied.
    let account = raw_rpc.get_account(&multisig)?;
    let ms = Multisig::try_deserialize(&mut account.data.as_slice())?;
    assert_eq!(ms.members.len(), 2);
    assert_eq!(ms.threshold, 2);

    Ok(())
}
