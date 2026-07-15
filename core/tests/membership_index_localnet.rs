//! Builds the membership index from a seeded local validator and asserts index
//! reads match the live scan for both a seeded member and a non-member. The
//! membership-delta path (a changed member set replacing the reverse index) is
//! covered by the store and worker unit tests, not here.
//!
//! Run manually: `cargo test --features relay-index --test membership_index_localnet -- --ignored`
//! Requires a running `solana-test-validator` with the squads_multisig program
//! cloned from devnet (or deployed) and its ProgramConfig account initialised.
#![cfg(feature = "relay-index")]

use std::{error::Error, time::Duration};

use solana_sdk::signature::{Keypair, Signer};

use cosign_core::membership_index::MembershipIndex;
use cosign_core::membership_indexer;
use cosign_core::rpc::RpcClient;
use cosign_core::squads::SquadsClient;

#[allow(dead_code)]
#[path = "support/localnet.rs"]
mod localnet;

#[test]
#[ignore = "spawns solana-test-validator and clones Squads from devnet"]
fn index_reads_match_live_reads() -> Result<(), Box<dyn Error>> {
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

    let browser_member = Keypair::new().pubkey();
    let config = localnet::FixtureConfig {
        browser_member,
        threshold: 2,
        proposal_count: 1,
        vault_count: 1,
        memo: "index test".into(),
    };
    let squad = localnet::create_squads_fixture(&raw_rpc, &config)?;

    let client = SquadsClient::new(RpcClient::new(rpc_url.clone()));
    let index = MembershipIndex::open(":memory:").unwrap();

    // Build from the seeded chain.
    let seen = membership_indexer::reconcile(&index, &client, 1_000)?;
    assert!(seen >= 1, "at least the seeded squad is indexed");
    index.mark_build_complete().unwrap();
    index.set_healthy(true);
    assert!(index.is_fresh(1_000));

    // Index read == live read for the seeded member.
    let indexed = index.squads_for_member(&browser_member).unwrap();
    let live = client.get_membership(&browser_member).unwrap();
    assert_eq!(indexed.len(), live.len());
    assert!(
        indexed
            .iter()
            .any(|s| s.address == squad.multisig.to_string())
    );

    // A member not in any squad resolves to empty in both.
    let stranger = Keypair::new().pubkey();
    assert!(index.squads_for_member(&stranger).unwrap().is_empty());
    assert!(client.get_membership(&stranger).unwrap().is_empty());

    Ok(())
}
