//! On-chain round trip for multisig creation against a local validator with
//! the Squads program loaded.
//!
//! Run manually: `cargo test --test create_multisig_localnet -- --ignored`
//! Requires a running `solana-test-validator` with the squads_multisig program
//! cloned from devnet (or deployed) and its ProgramConfig account initialised.

use std::{error::Error, time::Duration};

use solana_sdk::signature::{Keypair, Signer};

use cosign_core::{rpc::RpcClient, transactions};

#[allow(dead_code)]
#[path = "support/localnet.rs"]
mod localnet;

#[test]
#[ignore = "spawns solana-test-validator and clones Squads from devnet"]
fn creates_a_one_of_one_multisig_on_localnet() -> Result<(), Box<dyn Error>> {
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
        prepared.message_bytes.clone(),
        creator_sig,
        create_key,
        prepared.create_key_signature.clone(),
    )?;
    assert!(!submission.signature.is_empty());

    let multisig: solana_sdk::pubkey::Pubkey = prepared.multisig_address.parse()?;
    let account = RpcClient::new(rpc_url).get_account(&multisig)?;
    assert!(!account.data.is_empty());

    Ok(())
}
