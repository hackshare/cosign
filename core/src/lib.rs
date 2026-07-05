uniffi::include_scaffolding!("cosign_core");

pub mod derivation;
pub mod keypair;
pub mod mnemonic;
pub mod rpc;
pub mod squads;
pub mod transactions;
pub mod types;

#[derive(Debug, thiserror::Error)]
pub enum CryptoError {
    #[error("word count must be 12 or 24")]
    InvalidWordCount,
    #[error("invalid mnemonic")]
    InvalidMnemonic,
    #[error("derivation failed")]
    DerivationFailed,
    #[error("private key must be 32 bytes")]
    InvalidKeyLength,
    #[error("signature must be 64 bytes")]
    InvalidSignatureLength,
    #[error("invalid secret key")]
    InvalidSecretKey,
}

impl From<mnemonic::MnemonicError> for CryptoError {
    fn from(e: mnemonic::MnemonicError) -> Self {
        match e {
            mnemonic::MnemonicError::InvalidWordCount => Self::InvalidWordCount,
            mnemonic::MnemonicError::InvalidMnemonic(_) => Self::InvalidMnemonic,
        }
    }
}

impl From<derivation::DerivationError> for CryptoError {
    fn from(_: derivation::DerivationError) -> Self {
        Self::DerivationFailed
    }
}

impl From<keypair::KeyPairError> for CryptoError {
    fn from(e: keypair::KeyPairError) -> Self {
        match e {
            keypair::KeyPairError::Mnemonic(m) => m.into(),
            keypair::KeyPairError::Derivation(d) => d.into(),
            keypair::KeyPairError::Construction(_) => Self::DerivationFailed,
        }
    }
}

pub struct KeyPair {
    pub public_key: Vec<u8>,
    pub private_key: Vec<u8>,
}

pub struct TokenTransferProposalParams {
    pub rpc_url: String,
    pub multisig_address: String,
    pub vault_index: u8,
    pub member_pubkey: String,
    pub recipient_owner_pubkey: String,
    pub mint_pubkey: String,
    pub amount: u64,
    pub decimals: u8,
    pub token_program_id: String,
    pub memo: Option<String>,
}

pub fn generate_mnemonic(word_count: u8) -> Result<String, CryptoError> {
    mnemonic::generate(word_count).map_err(Into::into)
}

pub fn keypair_from_mnemonic(mnemonic: String, passphrase: String) -> Result<KeyPair, CryptoError> {
    let kp = keypair::from_mnemonic(&mnemonic, &passphrase)?;
    Ok(KeyPair {
        public_key: kp.public_key.to_bytes().to_vec(),
        private_key: kp.private_key.to_vec(),
    })
}

pub fn keypair_from_secret_bytes(secret_bytes: Vec<u8>) -> Result<KeyPair, CryptoError> {
    if secret_bytes.len() != 64 {
        return Err(CryptoError::InvalidKeyLength);
    }
    let kp =
        keypair::from_secret_bytes(&secret_bytes).map_err(|_| CryptoError::InvalidSecretKey)?;
    Ok(KeyPair {
        public_key: kp.public_key.to_bytes().to_vec(),
        private_key: kp.private_key.to_vec(),
    })
}

pub fn sign(private_key: Vec<u8>, message: Vec<u8>) -> Vec<u8> {
    let Ok(pk) = <[u8; 32]>::try_from(private_key.as_slice()) else {
        return Vec::new();
    };
    keypair::sign(&pk, &message).to_vec()
}

pub fn verify(public_key: Vec<u8>, message: Vec<u8>, signature: Vec<u8>) -> bool {
    let Some(pk) = keypair::pubkey_from_bytes(&public_key) else {
        return false;
    };
    let Ok(sig) = <[u8; 64]>::try_from(signature.as_slice()) else {
        return false;
    };
    keypair::verify(&pk, &message, &sig)
}

pub fn pubkey_to_base58(public_key: Vec<u8>) -> String {
    keypair::pubkey_from_bytes(&public_key)
        .map(|pk| pk.to_string())
        .unwrap_or_default()
}

pub fn is_valid_pubkey(pubkey: String) -> bool {
    keypair::pubkey_from_base58(&pubkey).is_some()
}

pub fn associated_token_account_address(
    owner_pubkey: String,
    mint_pubkey: String,
    token_program_id: String,
) -> Result<String, SquadsFFIError> {
    let owner = parse_pubkey(&owner_pubkey)?;
    let mint = parse_pubkey(&mint_pubkey)?;
    let token_program = parse_pubkey(&token_program_id)?;
    Ok(
        spl_associated_token_account::get_associated_token_address_with_program_id(
            &owner,
            &mint,
            &token_program,
        )
        .to_string(),
    )
}

// -- Squads read FFI surface --

pub use transactions::{
    CreateMultisigCost, PreparedMultisigCreation, PreparedProposalCreation, PreparedTransaction,
    SignatureStatus, SimulationResult, TransactionSubmission, VoteType,
};
pub use types::{
    ActivityItem, DecodedInstruction, MemberInfo, MultisigDetail, MultisigSummary, ProposalDetail,
    ProposalSummary, VaultRef,
};

#[derive(Debug, thiserror::Error)]
pub enum SquadsFFIError {
    #[error("invalid pubkey")]
    InvalidPubkey,
    #[error("invalid signature")]
    InvalidSignature,
    #[error("RPC error: {0}")]
    Rpc(String),
    #[error("invalid account: {0}")]
    InvalidAccount(String),
    #[error("companion transaction account missing")]
    CompanionMissing,
    #[error("invalid transaction: {0}")]
    InvalidTransaction(String),
}

impl From<squads::SquadsError> for SquadsFFIError {
    fn from(e: squads::SquadsError) -> Self {
        match e {
            squads::SquadsError::Rpc(rpc_err) => Self::Rpc(rpc_err.to_string()),
            squads::SquadsError::InvalidAccount(s) => Self::InvalidAccount(s),
            squads::SquadsError::CompanionMissing => Self::CompanionMissing,
        }
    }
}

impl From<transactions::TransactionBuildError> for SquadsFFIError {
    fn from(e: transactions::TransactionBuildError) -> Self {
        match e {
            transactions::TransactionBuildError::Rpc(rpc_err) => Self::Rpc(rpc_err.to_string()),
            transactions::TransactionBuildError::Squads(squads_err) => squads_err.into(),
            transactions::TransactionBuildError::InvalidTransaction(message)
            | transactions::TransactionBuildError::Serialization(message) => {
                Self::InvalidTransaction(message)
            }
            transactions::TransactionBuildError::InvalidSignature => {
                Self::InvalidTransaction("invalid signature".into())
            }
        }
    }
}

fn parse_pubkey(s: &str) -> Result<solana_sdk::pubkey::Pubkey, SquadsFFIError> {
    keypair::pubkey_from_base58(s).ok_or(SquadsFFIError::InvalidPubkey)
}

fn parse_signature(s: &str) -> Result<solana_sdk::signature::Signature, SquadsFFIError> {
    s.parse::<solana_sdk::signature::Signature>()
        .map_err(|_| SquadsFFIError::InvalidSignature)
}

fn make_squads_client(rpc_url: String) -> squads::SquadsClient {
    squads::SquadsClient::new(rpc::RpcClient::new(rpc_url))
}

pub fn squads_get_multisig(
    rpc_url: String,
    multisig_address: String,
) -> Result<MultisigDetail, SquadsFFIError> {
    let address = parse_pubkey(&multisig_address)?;
    let client = make_squads_client(rpc_url);
    let multisig = client.get_multisig(&address)?;
    let vault_indices = client.discover_vault_indices(&address)?;
    Ok(types::multisig_detail(
        &address,
        &multisig,
        &client.program_id(),
        &vault_indices,
    ))
}

pub fn squads_get_membership(
    rpc_url: String,
    member_pubkey: String,
) -> Result<Vec<MultisigSummary>, SquadsFFIError> {
    let member = parse_pubkey(&member_pubkey)?;
    let client = make_squads_client(rpc_url);
    let hits = client.get_membership(&member)?;
    Ok(hits
        .into_iter()
        .map(|(addr, ms)| types::multisig_summary(&addr, &ms))
        .collect())
}

pub fn squads_get_proposals_range(
    rpc_url: String,
    multisig_address: String,
    from_index: u64,
    to_index: u64,
) -> Result<Vec<ProposalSummary>, SquadsFFIError> {
    let address = parse_pubkey(&multisig_address)?;
    let client = make_squads_client(rpc_url);
    let multisig = client.get_multisig(&address)?;
    let proposals = client.get_proposals_range(&address, from_index, to_index)?;
    Ok(proposals
        .into_iter()
        .map(|(idx, p)| types::proposal_summary(idx, &p, multisig.threshold))
        .collect())
}

pub fn squads_get_proposal(
    rpc_url: String,
    multisig_address: String,
    transaction_index: u64,
) -> Result<ProposalDetail, SquadsFFIError> {
    let address = parse_pubkey(&multisig_address)?;
    let client = make_squads_client(rpc_url);
    let multisig = client.get_multisig(&address)?;
    let pwc = client.get_proposal(&address, transaction_index)?;
    let companion = match &pwc.companion {
        squads::ProposalCompanion::Vault(vault) => types::ProposalCompanionRef::Vault(vault),
        squads::ProposalCompanion::Config(config) => types::ProposalCompanionRef::Config(config),
    };
    Ok(types::proposal_detail(
        transaction_index,
        &pwc.proposal,
        multisig.threshold,
        &companion,
        Some(&pwc.companion_address),
    ))
}

pub fn squads_get_vault_pda(
    multisig_address: String,
    vault_index: u8,
) -> Result<String, SquadsFFIError> {
    let address = parse_pubkey(&multisig_address)?;
    Ok(squads::SquadsClient::derive_vault_pda(&address, vault_index).to_string())
}

pub fn squads_get_activity(
    rpc_url: String,
    multisig_address: String,
    before_signature: Option<String>,
    limit: u32,
) -> Result<Vec<ActivityItem>, SquadsFFIError> {
    let address = parse_pubkey(&multisig_address)?;
    let before = before_signature
        .as_deref()
        .map(parse_signature)
        .transpose()?;
    let client = make_squads_client(rpc_url);
    Ok(client
        .get_activity(&address, before, limit)?
        .iter()
        .map(types::activity_item)
        .collect())
}

pub fn squads_build_vote_transaction(
    rpc_url: String,
    multisig_address: String,
    transaction_index: u64,
    member_pubkey: String,
    vote: VoteType,
) -> Result<PreparedTransaction, SquadsFFIError> {
    let multisig = parse_pubkey(&multisig_address)?;
    let member = parse_pubkey(&member_pubkey)?;
    let rpc = rpc::RpcClient::new(rpc_url);
    Ok(transactions::build_vote_transaction(
        rpc,
        multisig,
        transaction_index,
        member,
        vote,
    )?)
}

pub fn squads_build_sol_transfer_proposal_transaction(
    rpc_url: String,
    multisig_address: String,
    vault_index: u8,
    member_pubkey: String,
    recipient_pubkey: String,
    lamports: u64,
    memo: Option<String>,
) -> Result<PreparedProposalCreation, SquadsFFIError> {
    let multisig = parse_pubkey(&multisig_address)?;
    let member = parse_pubkey(&member_pubkey)?;
    let recipient = parse_pubkey(&recipient_pubkey)?;
    let rpc = rpc::RpcClient::new(rpc_url);
    Ok(transactions::build_sol_transfer_proposal_transaction(
        rpc,
        multisig,
        vault_index,
        member,
        recipient,
        lamports,
        memo,
    )?)
}

pub fn squads_build_token_transfer_proposal_transaction(
    params: TokenTransferProposalParams,
) -> Result<PreparedProposalCreation, SquadsFFIError> {
    let multisig = parse_pubkey(&params.multisig_address)?;
    let member = parse_pubkey(&params.member_pubkey)?;
    let recipient_owner = parse_pubkey(&params.recipient_owner_pubkey)?;
    let mint = parse_pubkey(&params.mint_pubkey)?;
    let token_program_id = parse_pubkey(&params.token_program_id)?;
    let rpc = rpc::RpcClient::new(params.rpc_url);
    Ok(transactions::build_token_transfer_proposal_transaction(
        rpc,
        transactions::TokenTransferProposalRequest {
            multisig,
            vault_index: params.vault_index,
            member,
            recipient_owner,
            mint,
            amount: params.amount,
            decimals: params.decimals,
            token_program_id,
            memo: params.memo,
        },
    )?)
}

pub fn squads_build_execute_transaction(
    rpc_url: String,
    multisig_address: String,
    transaction_index: u64,
    member_pubkey: String,
) -> Result<PreparedTransaction, SquadsFFIError> {
    let multisig = parse_pubkey(&multisig_address)?;
    let member = parse_pubkey(&member_pubkey)?;
    let rpc = rpc::RpcClient::new(rpc_url);
    Ok(transactions::build_execute_transaction(
        rpc,
        multisig,
        transaction_index,
        member,
    )?)
}

pub fn squads_simulate_signed_transaction(
    rpc_url: String,
    message_bytes: Vec<u8>,
    signature_bytes: Vec<u8>,
) -> Result<SimulationResult, SquadsFFIError> {
    let rpc = rpc::RpcClient::new(rpc_url);
    Ok(transactions::simulate_signed_transaction(
        rpc,
        message_bytes,
        signature_bytes,
    )?)
}

pub fn squads_send_signed_transaction(
    rpc_url: String,
    message_bytes: Vec<u8>,
    signature_bytes: Vec<u8>,
) -> Result<TransactionSubmission, SquadsFFIError> {
    let rpc = rpc::RpcClient::new(rpc_url);
    Ok(transactions::send_signed_transaction(
        rpc,
        message_bytes,
        signature_bytes,
    )?)
}

pub fn squads_build_create_multisig_transaction(
    rpc_url: String,
    creator_pubkey: String,
    member_pubkeys: Vec<String>,
    threshold: u16,
) -> Result<PreparedMultisigCreation, SquadsFFIError> {
    let creator = parse_pubkey(&creator_pubkey)?;
    let members = member_pubkeys
        .iter()
        .map(|m| parse_pubkey(m))
        .collect::<Result<Vec<_>, _>>()?;
    let rpc = rpc::RpcClient::new(rpc_url);
    Ok(transactions::build_create_multisig_transaction(
        rpc, creator, members, threshold,
    )?)
}

pub fn squads_estimate_create_multisig_cost(
    rpc_url: String,
    creator_pubkey: String,
    member_pubkeys: Vec<String>,
    threshold: u16,
) -> Result<CreateMultisigCost, SquadsFFIError> {
    let creator = parse_pubkey(&creator_pubkey)?;
    let members = member_pubkeys
        .iter()
        .map(|m| parse_pubkey(m))
        .collect::<Result<Vec<_>, _>>()?;
    let rpc = rpc::RpcClient::new(rpc_url);
    Ok(transactions::estimate_create_multisig_cost(
        rpc, creator, members, threshold,
    )?)
}

pub fn squads_send_multisig_create_transaction(
    rpc_url: String,
    message_bytes: Vec<u8>,
    creator_signature: Vec<u8>,
    create_key_pubkey: String,
    create_key_signature: Vec<u8>,
) -> Result<TransactionSubmission, SquadsFFIError> {
    let create_key = parse_pubkey(&create_key_pubkey)?;
    let rpc = rpc::RpcClient::new(rpc_url);
    Ok(transactions::send_multisig_create_transaction(
        rpc,
        message_bytes,
        creator_signature,
        create_key,
        create_key_signature,
    )?)
}

pub fn request_devnet_airdrop(
    rpc_url: String,
    address: String,
    lamports: u64,
) -> Result<String, SquadsFFIError> {
    let pubkey = parse_pubkey(&address)?;
    let rpc = rpc::RpcClient::new(rpc_url);
    let signature = rpc
        .request_airdrop(&pubkey, lamports)
        .map_err(|e| SquadsFFIError::Rpc(e.to_string()))?;
    Ok(signature.to_string())
}

pub fn get_sol_balance(rpc_url: String, address: String) -> Result<u64, SquadsFFIError> {
    let pubkey = parse_pubkey(&address)?;
    let rpc = rpc::RpcClient::new(rpc_url);
    rpc.get_balance(&pubkey)
        .map_err(|e| SquadsFFIError::Rpc(e.to_string()))
}

pub fn squads_get_signature_status(
    rpc_url: String,
    signature: String,
) -> Result<SignatureStatus, SquadsFFIError> {
    let signature = parse_signature(&signature)?;
    let rpc = rpc::RpcClient::new(rpc_url);
    Ok(transactions::get_signature_status(rpc, signature)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_solana_pubkeys() {
        let pubkey = solana_sdk::pubkey::Pubkey::new_unique().to_string();
        assert!(is_valid_pubkey(pubkey));
        assert!(is_valid_pubkey(
            "11111111111111111111111111111111".to_string()
        ));
        assert!(!is_valid_pubkey(String::new()));
        assert!(!is_valid_pubkey("0".repeat(32)));
        assert!(!is_valid_pubkey("not-a-solana-address".to_string()));
    }

    #[test]
    fn derives_associated_token_account_addresses() {
        let owner = solana_sdk::pubkey::Pubkey::new_unique();
        let mint = solana_sdk::pubkey::Pubkey::new_unique();
        let expected_spl =
            spl_associated_token_account::get_associated_token_address_with_program_id(
                &owner,
                &mint,
                &spl_token::id(),
            )
            .to_string();
        let expected_token_2022 =
            spl_associated_token_account::get_associated_token_address_with_program_id(
                &owner,
                &mint,
                &spl_token_2022::id(),
            )
            .to_string();

        assert_eq!(
            associated_token_account_address(
                owner.to_string(),
                mint.to_string(),
                spl_token::id().to_string()
            )
            .unwrap(),
            expected_spl
        );
        assert_eq!(
            associated_token_account_address(
                owner.to_string(),
                mint.to_string(),
                spl_token_2022::id().to_string()
            )
            .unwrap(),
            expected_token_2022
        );
        assert!(matches!(
            associated_token_account_address(
                "not-a-pubkey".to_string(),
                mint.to_string(),
                spl_token::id().to_string()
            ),
            Err(SquadsFFIError::InvalidPubkey)
        ));
    }
}
