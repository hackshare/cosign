use std::{error::Error, thread, time::Duration};

use solana_sdk::{
    pubkey::Pubkey,
    signature::{Keypair, Signer},
};
use spl_associated_token_account::get_associated_token_address_with_program_id;

use cosign_core::{
    PreparedProposalCreation, PreparedTransaction, TokenTransferProposalParams, VoteType,
    rpc::RpcClient, squads_build_execute_transaction,
    squads_build_sol_transfer_proposal_transaction,
    squads_build_token_transfer_proposal_transaction, squads_build_vote_transaction,
    squads_get_activity, squads_get_membership, squads_get_multisig, squads_get_proposal,
    squads_get_proposals_range, squads_get_signature_status, squads_send_signed_transaction,
    squads_simulate_signed_transaction, transactions,
};

#[path = "support/localnet.rs"]
mod localnet;

#[test]
#[ignore = "spawns solana-test-validator and clones Squads from devnet"]
fn local_validator_squads_read_fixture() -> Result<(), Box<dyn Error>> {
    localnet::load_env_files();

    let clone_rpc_url = localnet::clone_rpc_url_from_env();
    let rpc_port = localnet::free_validator_rpc_port()?;
    let reserved_validator_ports = localnet::validator_reserved_ports(rpc_port)?;
    let faucet_port = localnet::free_port_excluding(&reserved_validator_ports)?;
    let ledger_dir = localnet::temp_ledger_dir();
    let _validator =
        localnet::LocalValidator::start(&ledger_dir, rpc_port, faucet_port, &clone_rpc_url)?;

    let rpc_url = format!("http://127.0.0.1:{rpc_port}");
    let rpc = localnet::new_rpc_client(rpc_url.clone());
    localnet::wait_for_validator(&rpc, Duration::from_secs(120))?;

    let browser_member = localnet::browser_member_from_env().unwrap_or_else(Pubkey::new_unique);
    let fixture = localnet::create_squads_fixture(
        &rpc,
        &localnet::FixtureConfig {
            browser_member,
            threshold: 1,
            proposal_count: 3,
            vault_count: 2,
            memo: "Cosign local validator test fixture".to_string(),
        },
    )?;
    assert_eq!(fixture.proposals.len(), 3);
    assert_eq!(fixture.threshold, 1);
    assert_eq!(fixture.member_count, 2);
    assert_eq!(fixture.proposals[0].transaction_index, 1);
    assert_ne!(fixture.proposals[0].proposal, Pubkey::default());
    assert_ne!(fixture.proposals[0].transaction, Pubkey::default());
    assert_eq!(
        fixture.proposals[0].state,
        localnet::FixtureProposalState::Approved
    );
    assert_eq!(
        fixture.proposals[0].kind,
        localnet::FixtureProposalKind::SolTransfer
    );
    assert_eq!(fixture.proposals[0].state.label(), "approved");
    assert_eq!(fixture.proposals[1].transaction_index, 2);
    assert_eq!(
        fixture.proposals[1].state,
        localnet::FixtureProposalState::Active
    );
    assert_eq!(fixture.proposals[1].state.label(), "active");
    assert_eq!(fixture.proposals[2].transaction_index, 3);
    assert_eq!(
        fixture.proposals[2].state,
        localnet::FixtureProposalState::Executed
    );
    assert_eq!(fixture.proposals[2].state.label(), "executed");
    assert_ne!(fixture.proposals[1].proposal, fixture.proposals[0].proposal);
    assert_ne!(
        fixture.proposals[1].transaction,
        fixture.proposals[0].transaction
    );

    assert_eq!(fixture.vault_fundings.len(), 2);
    for (expected_index, funding) in fixture.vault_fundings.iter().enumerate() {
        assert_eq!(funding.vault_index, expected_index as u8);
        assert_eq!(rpc.get_balance(&funding.vault)?, funding.sol_lamports);
        assert_token_funding(&rpc, &funding.spl_token)?;
        assert_token_funding(&rpc, &funding.token_2022)?;
    }

    let membership = squads_get_membership(rpc_url.clone(), fixture.browser_member.to_string())?;
    assert!(
        membership
            .iter()
            .any(|squad| squad.address == fixture.multisig.to_string())
    );

    let detail = squads_get_multisig(rpc_url.clone(), fixture.multisig.to_string())?;
    assert_eq!(detail.address, fixture.multisig.to_string());
    assert_eq!(detail.threshold, 1);
    assert_eq!(detail.transaction_index, 3);
    assert_eq!(detail.members.len(), 2);
    assert_eq!(detail.vaults.len(), 2);
    assert_eq!(detail.vaults[0].index, 0);
    assert_eq!(detail.vaults[1].index, 1);

    let proposals =
        squads_get_proposals_range(rpc_url.clone(), fixture.multisig.to_string(), 1, 3)?;
    assert_eq!(proposals.len(), 3);
    assert_eq!(proposals[0].transaction_index, 1);
    assert_eq!(proposals[0].status, "Approved");
    assert_eq!(proposals[0].votes_yes, 1);
    assert_eq!(proposals[1].transaction_index, 2);
    assert_eq!(proposals[1].status, "Active");
    assert_eq!(proposals[1].votes_yes, 0);
    assert_eq!(proposals[2].transaction_index, 3);
    assert_eq!(proposals[2].status, "Executed");
    assert_eq!(proposals[2].votes_yes, 1);

    let proposal = squads_get_proposal(rpc_url.clone(), fixture.multisig.to_string(), 1)?;
    assert_eq!(proposal.transaction_index, 1);
    assert_eq!(proposal.status, "Approved");
    assert_eq!(proposal.kind, "vault");
    assert_eq!(proposal.instructions.len(), 1);
    assert!(
        proposal
            .voters_yes
            .contains(&fixture.creator_member.to_string())
    );

    let active_proposal = squads_get_proposal(rpc_url.clone(), fixture.multisig.to_string(), 2)?;
    assert_eq!(active_proposal.transaction_index, 2);
    assert_eq!(active_proposal.status, "Active");
    assert_eq!(active_proposal.kind, "vault");
    assert!(active_proposal.voters_yes.is_empty());

    let executed_proposal = squads_get_proposal(rpc_url.clone(), fixture.multisig.to_string(), 3)?;
    assert_eq!(executed_proposal.transaction_index, 3);
    assert_eq!(executed_proposal.status, "Executed");
    assert_eq!(executed_proposal.kind, "vault");
    assert!(
        executed_proposal
            .voters_yes
            .contains(&fixture.creator_member.to_string())
    );

    let activity = squads_get_activity(rpc_url, fixture.multisig.to_string(), None, 10)?;
    assert!(!activity.is_empty());
    assert!(activity.iter().any(|item| item.kind == "Create Squad"));
    assert!(
        activity
            .iter()
            .any(|item| item.kind == "Approve Proposal 1")
    );
    assert!(activity.iter().any(|item| item.kind == "Create Proposal 2"));
    assert!(
        activity
            .iter()
            .any(|item| item.kind == "Execute Proposal 3")
    );

    Ok(())
}

#[test]
#[ignore = "spawns solana-test-validator and clones Squads from devnet"]
fn local_validator_squads_vote_and_execute_fixture() -> Result<(), Box<dyn Error>> {
    localnet::load_env_files();

    let clone_rpc_url = localnet::clone_rpc_url_from_env();
    let rpc_port = localnet::free_validator_rpc_port()?;
    let reserved_validator_ports = localnet::validator_reserved_ports(rpc_port)?;
    let faucet_port = localnet::free_port_excluding(&reserved_validator_ports)?;
    let ledger_dir = localnet::temp_ledger_dir();
    let _validator =
        localnet::LocalValidator::start(&ledger_dir, rpc_port, faucet_port, &clone_rpc_url)?;

    let rpc_url = format!("http://127.0.0.1:{rpc_port}");
    let rpc = localnet::new_rpc_client(rpc_url.clone());
    localnet::wait_for_validator(&rpc, Duration::from_secs(120))?;

    let browser = Keypair::new();
    let fixture = localnet::create_squads_fixture(
        &rpc,
        &localnet::FixtureConfig {
            browser_member: browser.pubkey(),
            threshold: 1,
            proposal_count: 5,
            vault_count: 1,
            memo: "Cosign local validator write fixture".to_string(),
        },
    )?;
    let member = fixture.creator.pubkey().to_string();
    let multisig = fixture.multisig.to_string();

    let cancel = squads_build_vote_transaction(
        rpc_url.clone(),
        multisig.clone(),
        1,
        member.clone(),
        VoteType::Cancel,
    )?;
    assert_eq!(cancel.refreshed_proposal.status, "Approved");
    submit_prepared(&rpc_url, &fixture.creator, cancel)?;
    let cancelled = squads_get_proposal(rpc_url.clone(), multisig.clone(), 1)?;
    assert_eq!(cancelled.status, "Cancelled");

    let reject = squads_build_vote_transaction(
        rpc_url.clone(),
        multisig.clone(),
        2,
        member.clone(),
        VoteType::Reject,
    )?;
    assert_eq!(reject.refreshed_proposal.status, "Active");
    submit_prepared(&rpc_url, &fixture.creator, reject)?;
    let second_reject = squads_build_vote_transaction(
        rpc_url.clone(),
        multisig.clone(),
        2,
        browser.pubkey().to_string(),
        VoteType::Reject,
    )?;
    assert_eq!(second_reject.refreshed_proposal.status, "Active");
    submit_prepared(&rpc_url, &browser, second_reject)?;
    let rejected = squads_get_proposal(rpc_url.clone(), multisig.clone(), 2)?;
    assert_eq!(rejected.status, "Rejected");

    let approve = squads_build_vote_transaction(
        rpc_url.clone(),
        multisig.clone(),
        5,
        member.clone(),
        VoteType::Approve,
    )?;
    assert_eq!(approve.refreshed_proposal.status, "Active");
    submit_prepared(&rpc_url, &fixture.creator, approve)?;
    let approved = squads_get_proposal(rpc_url.clone(), multisig.clone(), 5)?;
    assert_eq!(approved.status, "Approved");

    let execute =
        squads_build_execute_transaction(rpc_url.clone(), multisig.clone(), 5, member.clone())?;
    assert_eq!(execute.refreshed_proposal.status, "Approved");
    let relay_simulation = transactions::simulate_unsigned_message(
        RpcClient::new(rpc_url.clone()),
        execute.message_bytes.clone(),
    )?;
    assert_eq!(relay_simulation.err, None);
    assert!(!relay_simulation.logs.is_empty());
    submit_prepared(&rpc_url, &fixture.creator, execute)?;
    let executed = squads_get_proposal(rpc_url.clone(), multisig.clone(), 5)?;
    assert_eq!(executed.status, "Executed");

    let recipient = Pubkey::new_unique();
    let create = squads_build_sol_transfer_proposal_transaction(
        rpc_url.clone(),
        multisig.clone(),
        0,
        member.clone(),
        recipient.to_string(),
        1_000_000,
        Some("Cosign create proposal test".to_string()),
    )?;
    assert_eq!(create.transaction_index, 6);
    assert_eq!(
        create.vault_address,
        fixture.vault_fundings[0].vault.to_string()
    );
    submit_created_proposal(&rpc_url, &fixture.creator, create)?;
    let created = squads_get_proposal(rpc_url.clone(), multisig.clone(), 6)?;
    assert_eq!(created.status, "Active");
    assert_eq!(created.kind, "vault");

    let approve_created = squads_build_vote_transaction(
        rpc_url.clone(),
        multisig.clone(),
        6,
        member.clone(),
        VoteType::Approve,
    )?;
    assert_eq!(approve_created.refreshed_proposal.status, "Active");
    submit_prepared(&rpc_url, &fixture.creator, approve_created)?;
    let approved_created = squads_get_proposal(rpc_url.clone(), multisig.clone(), 6)?;
    assert_eq!(approved_created.status, "Approved");

    let execute_created =
        squads_build_execute_transaction(rpc_url.clone(), multisig.clone(), 6, member.clone())?;
    assert_eq!(execute_created.refreshed_proposal.status, "Approved");
    submit_prepared(&rpc_url, &fixture.creator, execute_created)?;
    let executed_created = squads_get_proposal(rpc_url.clone(), multisig.clone(), 6)?;
    assert_eq!(executed_created.status, "Executed");
    assert_eq!(rpc.get_balance(&recipient)?, 1_000_000);

    let multisig = fixture.multisig.to_string();
    let member = fixture.creator.pubkey().to_string();
    let spl_recipient = Pubkey::new_unique();
    let create_spl =
        squads_build_token_transfer_proposal_transaction(TokenTransferProposalParams {
            rpc_url: rpc_url.clone(),
            multisig_address: multisig.clone(),
            vault_index: 0,
            member_pubkey: member.clone(),
            recipient_owner_pubkey: spl_recipient.to_string(),
            mint_pubkey: fixture.vault_fundings[0].spl_token.mint.to_string(),
            amount: 1_000_000,
            decimals: fixture.vault_fundings[0].spl_token.decimals,
            token_program_id: fixture.vault_fundings[0].spl_token.program_id.to_string(),
            memo: Some("Cosign SPL token create proposal test".to_string()),
        })?;
    assert_eq!(create_spl.transaction_index, 7);
    submit_created_proposal(&rpc_url, &fixture.creator, create_spl)?;
    approve_and_execute(&rpc_url, &fixture.creator, &multisig, &member, 7)?;
    assert_token_recipient_balance(
        &rpc,
        &spl_recipient,
        &fixture.vault_fundings[0].spl_token,
        1_000_000,
    )?;

    let token_2022_recipient = Pubkey::new_unique();
    let create_token_2022 =
        squads_build_token_transfer_proposal_transaction(TokenTransferProposalParams {
            rpc_url: rpc_url.clone(),
            multisig_address: multisig.clone(),
            vault_index: 0,
            member_pubkey: member.clone(),
            recipient_owner_pubkey: token_2022_recipient.to_string(),
            mint_pubkey: fixture.vault_fundings[0].token_2022.mint.to_string(),
            amount: 2_000_000,
            decimals: fixture.vault_fundings[0].token_2022.decimals,
            token_program_id: fixture.vault_fundings[0].token_2022.program_id.to_string(),
            memo: Some("Cosign Token-2022 create proposal test".to_string()),
        })?;
    assert_eq!(create_token_2022.transaction_index, 8);
    submit_created_proposal(&rpc_url, &fixture.creator, create_token_2022)?;
    approve_and_execute(&rpc_url, &fixture.creator, &multisig, &member, 8)?;
    assert_token_recipient_balance(
        &rpc,
        &token_2022_recipient,
        &fixture.vault_fundings[0].token_2022,
        2_000_000,
    )?;

    Ok(())
}

#[test]
fn inspection_matrix_fixture_specs_cover_relay_permutations() {
    let specs = localnet::inspection_matrix_fixture_proposal_specs();
    assert!(specs.contains(&localnet::FixtureProposalSpec::new(
        localnet::FixtureProposalState::Active,
        localnet::FixtureProposalKind::SolTransfer
    )));
    assert!(specs.contains(&localnet::FixtureProposalSpec::new(
        localnet::FixtureProposalState::Approved,
        localnet::FixtureProposalKind::Token2022Transfer
    )));
    assert!(specs.contains(&localnet::FixtureProposalSpec::new(
        localnet::FixtureProposalState::Active,
        localnet::FixtureProposalKind::SplTokenTransfer
    )));
    assert!(specs.contains(&localnet::FixtureProposalSpec::new(
        localnet::FixtureProposalState::Approved,
        localnet::FixtureProposalKind::UnknownMemo
    )));
    assert!(specs.contains(&localnet::FixtureProposalSpec::new(
        localnet::FixtureProposalState::Active,
        localnet::FixtureProposalKind::ConfigChange
    )));
    assert!(specs.contains(&localnet::FixtureProposalSpec::new(
        localnet::FixtureProposalState::Executed,
        localnet::FixtureProposalKind::ConfigChange
    )));
    assert!(specs.iter().any(|spec| {
        spec.state == localnet::FixtureProposalState::Executed
            && spec.kind == localnet::FixtureProposalKind::SolTransfer
    }));
}

fn assert_token_funding(
    rpc: &solana_client::rpc_client::RpcClient,
    funding: &localnet::FixtureTokenFunding,
) -> Result<(), Box<dyn Error>> {
    assert_ne!(funding.mint, Pubkey::default());
    assert_ne!(funding.account, Pubkey::default());

    let token_balance = rpc.get_token_account_balance(&funding.account)?;
    assert_eq!(token_balance.amount, funding.amount.to_string());
    assert_eq!(token_balance.decimals, funding.decimals);

    let token_account = rpc.get_account(&funding.account)?;
    assert_eq!(token_account.owner, funding.program_id);

    Ok(())
}

fn submit_prepared(
    rpc_url: &str,
    signer: &solana_sdk::signature::Keypair,
    prepared: PreparedTransaction,
) -> Result<String, Box<dyn Error>> {
    submit_message(rpc_url, signer, prepared.message_bytes)
}

fn submit_created_proposal(
    rpc_url: &str,
    signer: &solana_sdk::signature::Keypair,
    prepared: PreparedProposalCreation,
) -> Result<String, Box<dyn Error>> {
    submit_message(rpc_url, signer, prepared.message_bytes)
}

fn approve_and_execute(
    rpc_url: &str,
    signer: &solana_sdk::signature::Keypair,
    multisig: &str,
    member: &str,
    transaction_index: u64,
) -> Result<(), Box<dyn Error>> {
    let approve = squads_build_vote_transaction(
        rpc_url.to_string(),
        multisig.to_string(),
        transaction_index,
        member.to_string(),
        VoteType::Approve,
    )?;
    submit_prepared(rpc_url, signer, approve)?;

    let execute = squads_build_execute_transaction(
        rpc_url.to_string(),
        multisig.to_string(),
        transaction_index,
        member.to_string(),
    )?;
    submit_prepared(rpc_url, signer, execute)?;
    let executed =
        squads_get_proposal(rpc_url.to_string(), multisig.to_string(), transaction_index)?;
    assert_eq!(executed.status, "Executed");
    Ok(())
}

fn assert_token_recipient_balance(
    rpc: &solana_client::rpc_client::RpcClient,
    recipient_owner: &Pubkey,
    funding: &localnet::FixtureTokenFunding,
    expected_amount: u64,
) -> Result<(), Box<dyn Error>> {
    let recipient_token_account = get_associated_token_address_with_program_id(
        recipient_owner,
        &funding.mint,
        &funding.program_id,
    );
    let token_balance = rpc.get_token_account_balance(&recipient_token_account)?;
    assert_eq!(token_balance.amount, expected_amount.to_string());
    assert_eq!(token_balance.decimals, funding.decimals);
    Ok(())
}

fn submit_message(
    rpc_url: &str,
    signer: &solana_sdk::signature::Keypair,
    message_bytes: Vec<u8>,
) -> Result<String, Box<dyn Error>> {
    let signature = signer.sign_message(&message_bytes).as_ref().to_vec();
    let simulation = squads_simulate_signed_transaction(
        rpc_url.to_string(),
        message_bytes.clone(),
        signature.clone(),
    )?;
    assert_eq!(simulation.err, None);

    let submission = squads_send_signed_transaction(rpc_url.to_string(), message_bytes, signature)?;
    wait_for_signature(rpc_url, &submission.signature)?;
    Ok(submission.signature)
}

fn wait_for_signature(rpc_url: &str, signature: &str) -> Result<(), Box<dyn Error>> {
    for _ in 0..40 {
        let status = squads_get_signature_status(rpc_url.to_string(), signature.to_string())?;
        if matches!(status.status.as_str(), "confirmed" | "finalized") {
            assert_eq!(status.err, None);
            return Ok(());
        }
        assert_eq!(status.err, None);
        thread::sleep(Duration::from_millis(250));
    }
    Err(format!("signature {signature} was not confirmed").into())
}
