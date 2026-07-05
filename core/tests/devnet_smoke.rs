use std::{env, error::Error, path::PathBuf};

use solana_client::rpc_filter::{Memcmp, RpcFilterType};
use solana_sdk::signature::Signer;
use squads_multisig::{anchor_lang::Discriminator, state::Multisig};

use cosign_core::{
    rpc::RpcClient, squads::SquadsClient, squads_get_activity, squads_get_membership,
    squads_get_multisig, squads_get_proposal, squads_get_proposals_range, squads_get_vault_pda,
};

const DEFAULT_DEVNET_RPC_URL: &str = "https://api.devnet.solana.com";

#[test]
#[ignore = "hits devnet RPC; run with `cargo test --test devnet_smoke -- --ignored --nocapture`"]
fn devnet_read_smoke() -> Result<(), Box<dyn Error>> {
    load_env_files();
    let config = DevnetSmokeConfig::from_env();
    println!("RPC: {}", redact_rpc_url(&config.rpc_url));

    let multisig = match config.multisig {
        Some(multisig) => Some(multisig),
        None if config.discover_multisig => Some(discover_multisig(&config.rpc_url)?),
        None => None,
    };

    if let Some(member) = config.member.as_deref() {
        let squads = squads_get_membership(config.rpc_url.clone(), member.to_string())?;
        println!("member {member} belongs to {} squads", squads.len());
        for squad in squads.iter().take(5) {
            println!(
                "  squad={} threshold={} members={} tx_index={}",
                squad.address, squad.threshold, squad.member_count, squad.transaction_index
            );
        }
    } else {
        println!("COSIGN_DEVNET_MEMBER is unset; skipping membership lookup");
    }

    if let Some(multisig) = multisig.as_deref() {
        let detail = squads_get_multisig(config.rpc_url.clone(), multisig.to_string())?;
        println!(
            "multisig={} threshold={} members={} tx_index={} stale_tx_index={}",
            detail.address,
            detail.threshold,
            detail.members.len(),
            detail.transaction_index,
            detail.stale_transaction_index
        );

        let vault = squads_get_vault_pda(multisig.to_string(), 0)?;
        println!("vault[0]={vault}");

        if detail.transaction_index > 0 {
            let to = detail.transaction_index;
            let from = to.saturating_sub(9).max(1);
            let proposals =
                squads_get_proposals_range(config.rpc_url.clone(), multisig.to_string(), from, to)?;
            println!("proposals in range {from}..={to}: {}", proposals.len());
        } else {
            println!("multisig has no transaction history; skipping proposal range");
        }

        let activity = squads_get_activity(config.rpc_url.clone(), multisig.to_string(), None, 10)?;
        println!("activity items: {}", activity.len());

        if let Some(index) = config.proposal_index {
            let proposal =
                squads_get_proposal(config.rpc_url.clone(), multisig.to_string(), index)?;
            println!(
                "proposal tx_index={} status={} kind={} instructions={}",
                proposal.transaction_index,
                proposal.status,
                proposal.kind,
                proposal.instructions.len()
            );
        }
    } else {
        println!(
            "COSIGN_DEVNET_MULTISIG is unset and discovery is disabled; skipping multisig lookup"
        );
    }

    Ok(())
}

#[test]
#[ignore = "creates a real multisig on devnet; run with \
            `COSIGN_DEVNET_CREATE=1 cargo test --test devnet_smoke devnet_create_squad -- --ignored --nocapture`"]
fn devnet_create_squad() -> Result<(), Box<dyn Error>> {
    load_env_files();
    if env_string("COSIGN_DEVNET_CREATE").as_deref() != Some("1") {
        println!("COSIGN_DEVNET_CREATE is not 1; skipping (this test spends devnet SOL)");
        return Ok(());
    }
    let rpc_url =
        env::var("COSIGN_DEVNET_RPC_URL").unwrap_or_else(|_| DEFAULT_DEVNET_RPC_URL.to_string());
    println!("RPC: {}", redact_rpc_url(&rpc_url));

    let creator = load_creator_keypair()?;
    let creator_pubkey = creator.pubkey().to_string();
    let seed = creator.to_bytes()[..32].to_vec();
    println!("creator={creator_pubkey}");

    // Exact app path: build (generates ephemeral create_key, signs with it) -> sign
    // with the creator seed -> submit both signatures -> read the multisig back.
    let prepared = cosign_core::squads_build_create_multisig_transaction(
        rpc_url.clone(),
        creator_pubkey.clone(),
        vec![],
        1,
    )?;
    println!(
        "multisig={} create_key={}",
        prepared.multisig_address, prepared.create_key
    );

    let creator_signature = cosign_core::sign(seed, prepared.message_bytes.clone());
    let submission = cosign_core::squads_send_multisig_create_transaction(
        rpc_url.clone(),
        prepared.message_bytes.clone(),
        creator_signature,
        prepared.create_key.clone(),
        prepared.create_key_signature.clone(),
    )?;
    println!("submitted signature={}", submission.signature);
    println!(
        "explorer: https://explorer.solana.com/address/{}?cluster=devnet",
        prepared.multisig_address
    );

    let detail = read_multisig_with_retries(&rpc_url, &prepared.multisig_address)?;
    println!(
        "read back: multisig={} threshold={} members={} tx_index={}",
        detail.address,
        detail.threshold,
        detail.members.len(),
        detail.transaction_index
    );
    assert_eq!(detail.threshold, 1, "1-of-1 threshold");
    assert_eq!(detail.members.len(), 1, "creator-only membership");
    assert_eq!(
        detail.members[0].pubkey, creator_pubkey,
        "creator is the sole member"
    );
    Ok(())
}

fn load_creator_keypair() -> Result<solana_sdk::signature::Keypair, Box<dyn Error>> {
    let path = env_string("COSIGN_DEVNET_PAYER_KEYPAIR")
        .ok_or("set COSIGN_DEVNET_PAYER_KEYPAIR to a funded devnet keypair.json")?;
    let path = PathBuf::from(&path);
    let resolved = if path.is_absolute() {
        path
    } else {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("core crate has repository parent")
            .join(path)
    };
    solana_sdk::signature::read_keypair_file(&resolved)
        .map_err(|e| format!("failed to read keypair {}: {e}", resolved.display()).into())
}

fn read_multisig_with_retries(
    rpc_url: &str,
    multisig: &str,
) -> Result<cosign_core::MultisigDetail, Box<dyn Error>> {
    let mut last_err: Option<String> = None;
    for attempt in 0..15 {
        std::thread::sleep(std::time::Duration::from_secs(2));
        match squads_get_multisig(rpc_url.to_string(), multisig.to_string()) {
            Ok(detail) => return Ok(detail),
            Err(e) => {
                last_err = Some(e.to_string());
                println!("  attempt {attempt}: multisig not readable yet ({e})");
            }
        }
    }
    Err(format!(
        "multisig {multisig} never became readable: {}",
        last_err.unwrap_or_default()
    )
    .into())
}

fn load_env_files() {
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

fn load_env_file(path: PathBuf) {
    if path.exists() {
        println!("loading env file {}", path.display());
        if let Err(error) = dotenvy::from_path(&path) {
            eprintln!("failed to load {}: {error}", path.display());
        }
    }
}

fn redact_rpc_url(url: &str) -> String {
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

struct DevnetSmokeConfig {
    rpc_url: String,
    member: Option<String>,
    multisig: Option<String>,
    proposal_index: Option<u64>,
    discover_multisig: bool,
}

impl DevnetSmokeConfig {
    fn from_env() -> Self {
        Self {
            rpc_url: env::var("COSIGN_DEVNET_RPC_URL")
                .unwrap_or_else(|_| DEFAULT_DEVNET_RPC_URL.to_string()),
            member: env_string("COSIGN_DEVNET_MEMBER"),
            multisig: env_string("COSIGN_DEVNET_MULTISIG"),
            proposal_index: env_string("COSIGN_DEVNET_PROPOSAL_INDEX")
                .and_then(|value| value.parse().ok()),
            discover_multisig: env::var("COSIGN_DEVNET_DISCOVER_MULTISIG")
                .map(|value| value == "1" || value.eq_ignore_ascii_case("true"))
                .unwrap_or(false),
        }
    }
}

fn env_string(name: &str) -> Option<String> {
    env::var(name)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn discover_multisig(rpc_url: &str) -> Result<String, Box<dyn Error>> {
    let rpc = RpcClient::new(rpc_url.to_string());
    let filters = vec![RpcFilterType::Memcmp(Memcmp::new_raw_bytes(
        0,
        Multisig::DISCRIMINATOR.to_vec(),
    ))];
    let accounts =
        rpc.get_program_accounts_with_filters(&SquadsClient::default_program_id(), filters)?;
    let (pubkey, _) = accounts
        .into_iter()
        .next()
        .ok_or("no Squads multisig accounts found on devnet")?;
    println!("discovered multisig={pubkey}");
    Ok(pubkey.to_string())
}
