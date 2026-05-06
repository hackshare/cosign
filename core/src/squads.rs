//! Squads v4 read-only operations.

use solana_client::rpc_filter::{Memcmp, RpcFilterType};
use solana_sdk::{pubkey::Pubkey, signature::Signature};
use squads_multisig::squads_multisig_program::state::VaultTransaction;
use squads_multisig::{
    anchor_lang::{AccountDeserialize, Discriminator},
    pda, squads_multisig_program,
    state::{ConfigTransaction, Multisig, Proposal},
};

use crate::rpc::{RpcClient, RpcError};

const MAX_DISCOVERABLE_VAULTS: u8 = 8;

#[derive(Debug, thiserror::Error)]
pub enum SquadsError {
    #[error("RPC error: {0}")]
    Rpc(#[from] RpcError),
    #[error("invalid account data: {0}")]
    InvalidAccount(String),
    #[error("companion transaction account not found")]
    CompanionMissing,
}

/// Either a VaultTransaction (transfer / CPI / arbitrary instructions) or a
/// ConfigTransaction (member changes, threshold changes, time-lock changes).
pub enum ProposalCompanion {
    Vault(VaultTransaction),
    Config(ConfigTransaction),
}

pub struct ProposalWithCompanion {
    pub proposal: Proposal,
    pub companion_address: Pubkey,
    pub companion: ProposalCompanion,
}

pub struct SquadsClient {
    rpc: RpcClient,
    program_id: Pubkey,
}

impl SquadsClient {
    pub fn derive_vault_pda(multisig: &Pubkey, vault_index: u8) -> Pubkey {
        let (vault, _) =
            pda::get_vault_pda(multisig, vault_index, Some(&Self::default_program_id()));
        vault
    }

    pub fn default_program_id() -> Pubkey {
        squads_multisig_program::ID
    }

    pub fn new(rpc: RpcClient) -> Self {
        Self {
            rpc,
            program_id: Self::default_program_id(),
        }
    }

    pub fn program_id(&self) -> Pubkey {
        self.program_id
    }

    pub(crate) fn rpc_ref(&self) -> &RpcClient {
        &self.rpc
    }

    pub fn get_vault_pda(&self, multisig: &Pubkey, vault_index: u8) -> Pubkey {
        let (vault, _) = pda::get_vault_pda(multisig, vault_index, Some(&self.program_id));
        vault
    }

    pub fn discover_vault_indices(&self, multisig: &Pubkey) -> Result<Vec<u8>, SquadsError> {
        let indices = 0..MAX_DISCOVERABLE_VAULTS;
        let vaults = indices
            .clone()
            .map(|index| self.get_vault_pda(multisig, index))
            .collect::<Vec<_>>();
        let accounts = self.rpc.get_multiple_accounts(&vaults)?;
        let mut discovered = Vec::new();

        for (index, account) in indices.zip(accounts) {
            if index == 0 || account.is_some() {
                discovered.push(index);
            }
        }

        Ok(discovered)
    }

    pub fn get_multisig(&self, address: &Pubkey) -> Result<Multisig, SquadsError> {
        let account = self.rpc.get_account(address)?;
        let mut data = account.data.as_slice();
        Multisig::try_deserialize(&mut data).map_err(|e| SquadsError::InvalidAccount(e.to_string()))
    }

    /// Find every Multisig that contains `member` in its members list.
    /// Filters only by Anchor discriminator on the network side; member-list
    /// scanning happens client-side. Acceptable for v1; a relay-side index
    /// makes this scale.
    pub fn get_membership(&self, member: &Pubkey) -> Result<Vec<(Pubkey, Multisig)>, SquadsError> {
        let filters = vec![RpcFilterType::Memcmp(Memcmp::new_raw_bytes(
            0,
            Multisig::DISCRIMINATOR.to_vec(),
        ))];
        let accounts = self
            .rpc
            .get_program_accounts_with_filters(&self.program_id, filters)?;

        let mut hits = Vec::new();
        for (pubkey, account) in accounts {
            let mut data = account.data.as_slice();
            if let Ok(ms) = Multisig::try_deserialize(&mut data)
                && ms.members.iter().any(|m| &m.key == member)
            {
                hits.push((pubkey, ms));
            }
        }
        Ok(hits)
    }

    pub fn get_proposal(
        &self,
        multisig: &Pubkey,
        transaction_index: u64,
    ) -> Result<ProposalWithCompanion, SquadsError> {
        let (proposal_pda, _) =
            pda::get_proposal_pda(multisig, transaction_index, Some(&self.program_id));
        let (companion_pda, _) =
            pda::get_transaction_pda(multisig, transaction_index, Some(&self.program_id));

        let accounts = self
            .rpc
            .get_multiple_accounts(&[proposal_pda, companion_pda])?;
        let mut iter = accounts.into_iter();
        let proposal_account = iter
            .next()
            .flatten()
            .ok_or_else(|| SquadsError::InvalidAccount("proposal account missing".into()))?;
        let companion_account = iter.next().flatten().ok_or(SquadsError::CompanionMissing)?;

        let mut proposal_data = proposal_account.data.as_slice();
        let proposal = Proposal::try_deserialize(&mut proposal_data)
            .map_err(|e| SquadsError::InvalidAccount(e.to_string()))?;

        // The companion lives at the same PDA whether it's a VaultTransaction
        // or a ConfigTransaction; the Anchor discriminator distinguishes them.
        let companion_data = companion_account.data.as_slice();
        let companion = parse_companion(companion_data)?;

        Ok(ProposalWithCompanion {
            proposal,
            companion_address: companion_pda,
            companion,
        })
    }

    /// Fetch a contiguous range of proposals (inclusive `from`..=`to`).
    /// Splits into batches of 100 to stay within `getMultipleAccounts` limits.
    pub fn get_proposals_range(
        &self,
        multisig: &Pubkey,
        from: u64,
        to: u64,
    ) -> Result<Vec<(u64, Proposal)>, SquadsError> {
        let mut indices = Vec::new();
        let mut pdas = Vec::new();
        for ix in from..=to {
            indices.push(ix);
            let (pda_addr, _) = pda::get_proposal_pda(multisig, ix, Some(&self.program_id));
            pdas.push(pda_addr);
        }

        let mut out = Vec::new();
        for (chunk_pdas, chunk_indices) in pdas.chunks(100).zip(indices.chunks(100)) {
            let accounts = self.rpc.get_multiple_accounts(chunk_pdas)?;
            for (idx, account_opt) in chunk_indices.iter().zip(accounts) {
                if let Some(account) = account_opt {
                    let mut data = account.data.as_slice();
                    if let Ok(proposal) = Proposal::try_deserialize(&mut data) {
                        out.push((*idx, proposal));
                    }
                }
            }
        }
        Ok(out)
    }

    pub fn get_activity(
        &self,
        address: &Pubkey,
        before: Option<Signature>,
        limit: u32,
    ) -> Result<
        Vec<solana_client::rpc_response::RpcConfirmedTransactionStatusWithSignature>,
        SquadsError,
    > {
        Ok(self
            .rpc
            .get_signatures_for_address(address, before, limit.min(100) as usize)?)
    }
}

fn parse_companion(data: &[u8]) -> Result<ProposalCompanion, SquadsError> {
    if data.len() < 8 {
        return Err(SquadsError::InvalidAccount(
            "account too small for discriminator".into(),
        ));
    }
    let discriminator = &data[..8];
    if discriminator == VaultTransaction::DISCRIMINATOR {
        let mut slice = data;
        let vt = VaultTransaction::try_deserialize(&mut slice)
            .map_err(|e| SquadsError::InvalidAccount(e.to_string()))?;
        Ok(ProposalCompanion::Vault(vt))
    } else if discriminator == ConfigTransaction::DISCRIMINATOR {
        let mut slice = data;
        let ct = ConfigTransaction::try_deserialize(&mut slice)
            .map_err(|e| SquadsError::InvalidAccount(e.to_string()))?;
        Ok(ProposalCompanion::Config(ct))
    } else {
        Err(SquadsError::InvalidAccount(
            "unknown transaction account discriminator".into(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn squads_program_id_is_v4() {
        let client = SquadsClient::new(RpcClient::new("https://example.invalid".into()));
        assert_eq!(client.program_id(), squads_multisig_program::ID);
    }

    #[test]
    fn proposal_pda_is_deterministic() {
        let multisig = Pubkey::new_unique();
        let (a, _) = pda::get_proposal_pda(&multisig, 5, None);
        let (b, _) = pda::get_proposal_pda(&multisig, 5, None);
        assert_eq!(a, b);
    }

    #[test]
    fn proposal_pdas_differ_per_index() {
        let multisig = Pubkey::new_unique();
        let (a, _) = pda::get_proposal_pda(&multisig, 5, None);
        let (b, _) = pda::get_proposal_pda(&multisig, 6, None);
        assert_ne!(a, b);
    }

    #[test]
    fn discriminator_is_8_bytes() {
        assert_eq!(Multisig::DISCRIMINATOR.len(), 8);
        assert_eq!(Proposal::DISCRIMINATOR.len(), 8);
        assert_eq!(VaultTransaction::DISCRIMINATOR.len(), 8);
        assert_eq!(ConfigTransaction::DISCRIMINATOR.len(), 8);
    }
}
