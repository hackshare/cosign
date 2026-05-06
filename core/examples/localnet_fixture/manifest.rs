use std::{
    error::Error,
    fs,
    path::Path,
    time::{SystemTime, UNIX_EPOCH},
};

use serde::{Deserialize, Serialize};

use crate::localnet::{FixtureSquad, FixtureTokenFunding};

#[derive(Deserialize, Serialize)]
pub struct LocalnetFixtureManifest {
    pub created_at_unix_seconds: u64,
    #[serde(default = "default_scenario")]
    pub scenario: String,
    pub local_validator_rpc_url: String,
    pub local_validator_websocket_url: String,
    pub browser_safe_rpc_url: Option<String>,
    pub browser_safe_websocket_url: Option<String>,
    pub ca_cert_path: Option<String>,
    pub browser_member: String,
    pub squads: Vec<SquadFixture>,
}

#[derive(Deserialize, Serialize)]
pub struct SquadFixture {
    pub index: u32,
    pub multisig: String,
    pub creator_member: String,
    pub browser_member: String,
    pub threshold: String,
    pub vaults: Vec<VaultFixture>,
    pub proposals: Vec<ProposalFixture>,
}

#[derive(Deserialize, Serialize)]
pub struct VaultFixture {
    pub index: u8,
    pub address: String,
    pub sol_lamports: u64,
    pub spl_token: TokenFixture,
    pub token_2022: TokenFixture,
}

#[derive(Deserialize, Serialize)]
pub struct TokenFixture {
    pub program_id: String,
    pub mint: String,
    pub account: String,
    pub amount_base_units: u64,
    pub decimals: u8,
}

#[derive(Deserialize, Serialize)]
pub struct ProposalFixture {
    pub transaction_index: u64,
    pub state: String,
    #[serde(default = "default_proposal_kind")]
    pub kind: String,
    pub proposal_account: String,
    pub transaction_account: String,
}

impl LocalnetFixtureManifest {
    pub fn new(
        local_validator_rpc_url: String,
        local_validator_websocket_url: String,
        browser_safe_rpc_url: Option<String>,
        browser_safe_websocket_url: Option<String>,
        ca_cert_path: Option<String>,
        browser_member: String,
        scenario: String,
    ) -> Self {
        Self {
            created_at_unix_seconds: unix_timestamp(),
            scenario,
            local_validator_rpc_url,
            local_validator_websocket_url,
            browser_safe_rpc_url,
            browser_safe_websocket_url,
            ca_cert_path,
            browser_member,
            squads: Vec::new(),
        }
    }

    pub fn push_squad(&mut self, index: u32, fixture: &FixtureSquad) {
        self.squads.push(SquadFixture {
            index,
            multisig: fixture.multisig.to_string(),
            creator_member: fixture.creator_member.to_string(),
            browser_member: fixture.browser_member.to_string(),
            threshold: format!("{} / {}", fixture.threshold, fixture.member_count),
            vaults: fixture
                .vault_fundings
                .iter()
                .map(|vault| VaultFixture {
                    index: vault.vault_index,
                    address: vault.vault.to_string(),
                    sol_lamports: vault.sol_lamports,
                    spl_token: token_fixture(&vault.spl_token),
                    token_2022: token_fixture(&vault.token_2022),
                })
                .collect(),
            proposals: fixture
                .proposals
                .iter()
                .map(|proposal| ProposalFixture {
                    transaction_index: proposal.transaction_index,
                    state: proposal.state.label().to_string(),
                    kind: proposal.kind.label().to_string(),
                    proposal_account: proposal.proposal.to_string(),
                    transaction_account: proposal.transaction.to_string(),
                })
                .collect(),
        });
    }

    pub fn write_to(&self, path: &Path) -> Result<(), Box<dyn Error>> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }

        fs::write(path, serde_json::to_vec_pretty(self)?)?;
        Ok(())
    }
}

fn token_fixture(token: &FixtureTokenFunding) -> TokenFixture {
    TokenFixture {
        program_id: token.program_id.to_string(),
        mint: token.mint.to_string(),
        account: token.account.to_string(),
        amount_base_units: token.amount,
        decimals: token.decimals,
    }
}

fn default_scenario() -> String {
    "default".to_string()
}

fn default_proposal_kind() -> String {
    "sol_transfer".to_string()
}

fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or_default()
}
