use std::{env, error::Error, fs, io, path::PathBuf};

use solana_client::rpc_client::RpcClient as SolanaRpcClient;
use solana_sdk::{commitment_config::CommitmentConfig, pubkey::Pubkey};

use cosign_core::{
    squads_get_activity, squads_get_membership, squads_get_multisig, squads_get_proposal,
    squads_get_proposals_range, squads_get_vault_pda,
};

#[allow(dead_code)]
#[path = "../tests/support/localnet.rs"]
mod localnet;
#[allow(dead_code)]
#[path = "localnet_fixture/manifest.rs"]
mod manifest;

use manifest::{
    LocalnetFixtureManifest, ProposalFixture, SquadFixture, TokenFixture, VaultFixture,
};

fn main() -> Result<(), Box<dyn Error>> {
    let args = Args::parse()?;
    let manifest = load_manifest(&args.manifest_path)?;
    let rpc_url = args
        .rpc_url
        .clone()
        .unwrap_or_else(|| manifest.local_validator_rpc_url.clone());
    let rpc = SolanaRpcClient::new_with_commitment(rpc_url.clone(), CommitmentConfig::confirmed());

    let version = rpc.get_version()?;
    println!("RPC version: {}", version.solana_core);

    check_membership(&rpc_url, &manifest)?;
    for squad in &manifest.squads {
        check_squad(&rpc_url, &rpc, &manifest, squad)?;
    }

    println!(
        "Checked {} localnet fixture Squad{}.",
        manifest.squads.len(),
        if manifest.squads.len() == 1 { "" } else { "s" }
    );
    Ok(())
}

#[derive(Debug)]
struct Args {
    manifest_path: PathBuf,
    rpc_url: Option<String>,
}

impl Args {
    fn parse() -> Result<Self, Box<dyn Error>> {
        let mut args = env::args().skip(1);
        let mut parsed = Args {
            manifest_path: default_manifest_path(),
            rpc_url: None,
        };

        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--manifest" => parsed.manifest_path = next_value(&mut args, &arg)?.into(),
                "--rpc-url" => parsed.rpc_url = Some(next_value(&mut args, &arg)?),
                "--help" | "-h" => {
                    print_usage();
                    std::process::exit(0);
                }
                unknown => return fail(format!("unknown argument: {unknown}")),
            }
        }

        Ok(parsed)
    }
}

fn load_manifest(path: &PathBuf) -> Result<LocalnetFixtureManifest, Box<dyn Error>> {
    let data = fs::read(path)?;
    Ok(serde_json::from_slice(&data)?)
}

fn check_membership(
    rpc_url: &str,
    manifest: &LocalnetFixtureManifest,
) -> Result<(), Box<dyn Error>> {
    let membership = squads_get_membership(rpc_url.to_string(), manifest.browser_member.clone())?;

    for squad in &manifest.squads {
        ensure(
            membership
                .iter()
                .any(|summary| summary.address == squad.multisig),
            format!(
                "browser member {} is missing Squad {} from membership",
                manifest.browser_member, squad.multisig
            ),
        )?;
    }

    println!("Membership includes all manifest Squads.");
    Ok(())
}

fn check_squad(
    rpc_url: &str,
    rpc: &SolanaRpcClient,
    manifest: &LocalnetFixtureManifest,
    squad: &SquadFixture,
) -> Result<(), Box<dyn Error>> {
    let detail = squads_get_multisig(rpc_url.to_string(), squad.multisig.clone())?;
    ensure(
        detail.address == squad.multisig,
        format!("loaded wrong Squad address for {}", squad.multisig),
    )?;
    ensure(
        detail.threshold == expected_threshold(squad)?,
        format!("Squad {} threshold mismatch", squad.multisig),
    )?;
    ensure(
        detail
            .members
            .iter()
            .any(|member| member.pubkey == manifest.browser_member),
        format!(
            "Squad {} is missing browser member {}",
            squad.multisig, manifest.browser_member
        ),
    )?;

    check_vaults(rpc_url, rpc, squad)?;
    check_proposals(rpc_url, squad)?;
    check_activity(rpc_url, squad)?;

    println!(
        "Squad {} OK: {} vault{}, {} proposal{}.",
        squad.index,
        squad.vaults.len(),
        if squad.vaults.len() == 1 { "" } else { "s" },
        squad.proposals.len(),
        if squad.proposals.len() == 1 { "" } else { "s" }
    );
    Ok(())
}

fn check_vaults(
    rpc_url: &str,
    rpc: &SolanaRpcClient,
    squad: &SquadFixture,
) -> Result<(), Box<dyn Error>> {
    for vault in &squad.vaults {
        check_vault_pda(rpc_url, squad, vault)?;
        check_vault_balance(rpc, vault)?;
        check_token_funding(rpc, &vault.spl_token)?;
        check_token_funding(rpc, &vault.token_2022)?;
    }
    Ok(())
}

fn check_vault_pda(
    rpc_url: &str,
    squad: &SquadFixture,
    vault: &VaultFixture,
) -> Result<(), Box<dyn Error>> {
    let derived = squads_get_vault_pda(squad.multisig.clone(), vault.index)?;
    ensure(
        derived == vault.address,
        format!(
            "vault {} for Squad {} does not match derived PDA",
            vault.index, squad.multisig
        ),
    )?;

    let _ = rpc_url;
    Ok(())
}

fn check_vault_balance(rpc: &SolanaRpcClient, vault: &VaultFixture) -> Result<(), Box<dyn Error>> {
    let balance = rpc.get_balance(&pubkey(&vault.address)?)?;
    ensure(
        balance == vault.sol_lamports,
        format!(
            "vault {} SOL balance mismatch: expected {}, got {}",
            vault.address, vault.sol_lamports, balance
        ),
    )
}

fn check_token_funding(rpc: &SolanaRpcClient, token: &TokenFixture) -> Result<(), Box<dyn Error>> {
    let program = pubkey(&token.program_id)?;
    let mint = pubkey(&token.mint)?;
    let token_account = pubkey(&token.account)?;

    let mint_account = rpc.get_account(&mint)?;
    ensure(
        mint_account.owner == program,
        format!("mint {} is not owned by {}", token.mint, token.program_id),
    )?;

    let account = rpc.get_account(&token_account)?;
    ensure(
        account.owner == program,
        format!(
            "token account {} is not owned by {}",
            token.account, token.program_id
        ),
    )?;

    let balance = rpc.get_token_account_balance(&token_account)?;
    ensure(
        balance.amount == token.amount_base_units.to_string(),
        format!(
            "token account {} amount mismatch: expected {}, got {}",
            token.account, token.amount_base_units, balance.amount
        ),
    )?;
    ensure(
        balance.decimals == token.decimals,
        format!(
            "token account {} decimals mismatch: expected {}, got {}",
            token.account, token.decimals, balance.decimals
        ),
    )
}

fn check_proposals(rpc_url: &str, squad: &SquadFixture) -> Result<(), Box<dyn Error>> {
    if squad.proposals.is_empty() {
        return fail(format!(
            "Squad {} has no proposals in manifest",
            squad.multisig
        ));
    }

    let from_index = squad
        .proposals
        .iter()
        .map(|proposal| proposal.transaction_index)
        .min()
        .unwrap_or_default();
    let to_index = squad
        .proposals
        .iter()
        .map(|proposal| proposal.transaction_index)
        .max()
        .unwrap_or_default();
    let summaries = squads_get_proposals_range(
        rpc_url.to_string(),
        squad.multisig.clone(),
        from_index,
        to_index,
    )?;

    for proposal in &squad.proposals {
        let expected_status = expected_proposal_status(proposal)?;
        let summary = summaries
            .iter()
            .find(|summary| summary.transaction_index == proposal.transaction_index)
            .ok_or_else(|| {
                io::Error::other(format!(
                    "proposal {} missing from range for Squad {}",
                    proposal.transaction_index, squad.multisig
                ))
            })?;
        ensure(
            summary.status == expected_status,
            format!(
                "proposal {} status mismatch: expected {}, got {}",
                proposal.transaction_index, expected_status, summary.status
            ),
        )?;

        check_proposal_detail(rpc_url, squad, proposal, expected_status)?;
    }

    Ok(())
}

fn check_proposal_detail(
    rpc_url: &str,
    squad: &SquadFixture,
    proposal: &ProposalFixture,
    expected_status: &str,
) -> Result<(), Box<dyn Error>> {
    let detail = squads_get_proposal(
        rpc_url.to_string(),
        squad.multisig.clone(),
        proposal.transaction_index,
    )?;
    ensure(
        detail.status == expected_status,
        format!(
            "proposal detail {} status mismatch: expected {}, got {}",
            proposal.transaction_index, expected_status, detail.status
        ),
    )?;
    ensure(
        detail.transaction_address.as_deref() == Some(proposal.transaction_account.as_str()),
        format!(
            "proposal {} transaction account mismatch",
            proposal.transaction_index
        ),
    )?;
    Ok(())
}

fn check_activity(rpc_url: &str, squad: &SquadFixture) -> Result<(), Box<dyn Error>> {
    let activity = squads_get_activity(rpc_url.to_string(), squad.multisig.clone(), None, 20)?;
    ensure(
        !activity.is_empty(),
        format!("Squad {} returned no activity", squad.multisig),
    )
}

fn expected_threshold(squad: &SquadFixture) -> Result<u16, Box<dyn Error>> {
    let Some((value, _total)) = squad.threshold.split_once('/') else {
        return fail(format!(
            "Squad {} has invalid threshold '{}'",
            squad.multisig, squad.threshold
        ));
    };
    Ok(value.trim().parse()?)
}

fn expected_proposal_status(proposal: &ProposalFixture) -> Result<&'static str, Box<dyn Error>> {
    match proposal.state.as_str() {
        "active" => Ok("Active"),
        "approved" => Ok("Approved"),
        "executed" => Ok("Executed"),
        "rejected" => Ok("Rejected"),
        "cancelled" => Ok("Cancelled"),
        state => fail(format!("unknown proposal state in manifest: {state}")),
    }
}

fn pubkey(value: &str) -> Result<Pubkey, Box<dyn Error>> {
    Ok(value.parse()?)
}

fn default_manifest_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("core crate has repository parent")
        .join(".cosign-local")
        .join("localnet-fixture.json")
}

fn next_value(
    args: &mut impl Iterator<Item = String>,
    flag: &str,
) -> Result<String, Box<dyn Error>> {
    args.next()
        .ok_or_else(|| io::Error::other(format!("{flag} requires a value")).into())
}

fn ensure(condition: bool, message: impl Into<String>) -> Result<(), Box<dyn Error>> {
    if condition { Ok(()) } else { fail(message) }
}

fn fail<T>(message: impl Into<String>) -> Result<T, Box<dyn Error>> {
    Err(io::Error::other(message.into()).into())
}

fn print_usage() {
    println!(
        "Usage: cargo run --manifest-path core/Cargo.toml --example check_localnet_fixture -- [options]"
    );
    println!();
    println!("Options:");
    println!("  --manifest <PATH>   JSON fixture manifest");
    println!("  --rpc-url <URL>     Override manifest local validator RPC URL");
}
