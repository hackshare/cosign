//! Thin wrapper around `solana_client::rpc_client::RpcClient` exposing only
//! the calls Cosign needs, with our own error type for FFI portability.

use std::{net::IpAddr, time::Duration};

use base64::{Engine, engine::general_purpose::STANDARD as BASE64_STANDARD};
use serde_json::{Value, json};
use solana_account_decoder::UiAccountEncoding;
use solana_client::{
    client_error::{ClientError, reqwest},
    rpc_client::{RpcClient as SolanaRpcClient, RpcClientConfig},
    rpc_config::{RpcAccountInfoConfig, RpcProgramAccountsConfig},
    rpc_filter::RpcFilterType,
    rpc_request::RpcRequest,
};
use solana_rpc_client::http_sender::HttpSender;
use solana_sdk::{
    account::Account,
    commitment_config::{CommitmentConfig, CommitmentLevel},
    hash::Hash,
    message::Message,
    pubkey::Pubkey,
    signature::Signature,
    transaction::Transaction,
};

#[derive(Debug, thiserror::Error)]
pub enum RpcError {
    #[error("RPC call failed: {0}")]
    Client(String),
    #[error("invalid signature: {0}")]
    InvalidSignature(String),
}

impl From<ClientError> for RpcError {
    fn from(e: ClientError) -> Self {
        Self::Client(e.to_string())
    }
}

pub struct RpcClient {
    inner: SolanaRpcClient,
}

pub struct RpcSimulationSnapshot {
    pub err: Option<String>,
    pub logs: Vec<String>,
}

pub struct RpcSignatureStatusSnapshot {
    pub slot: Option<u64>,
    pub status: String,
    pub err: Option<String>,
}

/// One page of a `getProgramAccountsV2` scan: the decoded accounts, the cursor for
/// the next page (None when pagination is complete), and the context slot.
pub struct ProgramAccountsPage {
    pub accounts: Vec<(Pubkey, Vec<u8>)>,
    pub pagination_key: Option<String>,
    pub slot: u64,
}

impl RpcClient {
    pub fn new(url: String) -> Self {
        Self::new_with_timeout(url, Duration::from_secs(30))
    }

    pub fn new_with_timeout(url: String, timeout: Duration) -> Self {
        Self {
            inner: build_solana_rpc_client(url, timeout),
        }
    }

    pub fn get_account(&self, pubkey: &Pubkey) -> Result<Account, RpcError> {
        Ok(self.inner.get_account(pubkey)?)
    }

    pub fn get_multiple_accounts(
        &self,
        pubkeys: &[Pubkey],
    ) -> Result<Vec<Option<Account>>, RpcError> {
        Ok(self.inner.get_multiple_accounts(pubkeys)?)
    }

    pub fn get_program_accounts_with_filters(
        &self,
        program_id: &Pubkey,
        filters: Vec<RpcFilterType>,
    ) -> Result<Vec<(Pubkey, Account)>, RpcError> {
        let config = RpcProgramAccountsConfig {
            filters: Some(filters),
            account_config: RpcAccountInfoConfig {
                encoding: Some(UiAccountEncoding::Base64),
                ..Default::default()
            },
            ..Default::default()
        };
        Ok(self
            .inner
            .get_program_accounts_with_config(program_id, config)?)
    }

    pub fn get_signatures_for_address(
        &self,
        address: &Pubkey,
        before: Option<Signature>,
        limit: usize,
    ) -> Result<
        Vec<solana_client::rpc_response::RpcConfirmedTransactionStatusWithSignature>,
        RpcError,
    > {
        let config = solana_client::rpc_client::GetConfirmedSignaturesForAddress2Config {
            before,
            until: None,
            limit: Some(limit),
            commitment: Some(CommitmentConfig::confirmed()),
        };
        Ok(self
            .inner
            .get_signatures_for_address_with_config(address, config)?)
    }

    pub fn get_latest_blockhash(&self) -> Result<Hash, RpcError> {
        Ok(self.inner.get_latest_blockhash()?)
    }

    pub fn get_balance(&self, pubkey: &Pubkey) -> Result<u64, RpcError> {
        Ok(self.inner.get_balance(pubkey)?)
    }

    pub fn request_airdrop(&self, pubkey: &Pubkey, lamports: u64) -> Result<Signature, RpcError> {
        Ok(self.inner.request_airdrop(pubkey, lamports)?)
    }

    pub fn get_fee_for_message(&self, message: &Message) -> Result<u64, RpcError> {
        Ok(self.inner.get_fee_for_message(message)?)
    }

    pub fn get_minimum_balance_for_rent_exemption(&self, data_len: usize) -> Result<u64, RpcError> {
        Ok(self
            .inner
            .get_minimum_balance_for_rent_exemption(data_len)?)
    }

    pub fn simulate_transaction(
        &self,
        transaction: &Transaction,
    ) -> Result<RpcSimulationSnapshot, RpcError> {
        let config = solana_client::rpc_config::RpcSimulateTransactionConfig {
            sig_verify: true,
            replace_recent_blockhash: false,
            commitment: Some(CommitmentConfig::confirmed()),
            ..Default::default()
        };
        let response = self
            .inner
            .simulate_transaction_with_config(transaction, config)?;
        Ok(RpcSimulationSnapshot {
            err: response.value.err.map(|err| format!("{err:?}")),
            logs: response.value.logs.unwrap_or_default(),
        })
    }

    pub fn simulate_transaction_without_signature_verification(
        &self,
        transaction: &Transaction,
    ) -> Result<RpcSimulationSnapshot, RpcError> {
        let config = solana_client::rpc_config::RpcSimulateTransactionConfig {
            sig_verify: false,
            replace_recent_blockhash: false,
            commitment: Some(CommitmentConfig::confirmed()),
            ..Default::default()
        };
        let response = self
            .inner
            .simulate_transaction_with_config(transaction, config)?;
        Ok(RpcSimulationSnapshot {
            err: response.value.err.map(|err| format!("{err:?}")),
            logs: response.value.logs.unwrap_or_default(),
        })
    }

    pub fn send_transaction(&self, transaction: &Transaction) -> Result<Signature, RpcError> {
        let config = solana_client::rpc_config::RpcSendTransactionConfig {
            skip_preflight: false,
            preflight_commitment: Some(CommitmentLevel::Confirmed),
            ..Default::default()
        };
        Ok(self
            .inner
            .send_transaction_with_config(transaction, config)?)
    }

    pub fn get_signature_status(
        &self,
        signature: &Signature,
    ) -> Result<RpcSignatureStatusSnapshot, RpcError> {
        let response = self.inner.get_signature_statuses(&[*signature])?;
        let Some(status) = response.value.into_iter().next().flatten() else {
            return Ok(RpcSignatureStatusSnapshot {
                slot: None,
                status: "pending".into(),
                err: None,
            });
        };

        let err = status.err.as_ref().map(|err| format!("{err:?}"));
        let status_label = if err.is_some() {
            "failed".into()
        } else if let Some(confirmation_status) = status.confirmation_status {
            format!("{confirmation_status:?}").to_lowercase()
        } else if status.confirmations.is_none() {
            "finalized".into()
        } else {
            "confirmed".into()
        };

        Ok(RpcSignatureStatusSnapshot {
            slot: Some(status.slot),
            status: status_label,
            err,
        })
    }

    /// Fetch one page of Helius `getProgramAccountsV2`. Paginate by passing the
    /// returned `pagination_key` back in until a page comes back with no accounts.
    /// `changed_since_slot` limits the result to accounts modified at/after a slot.
    pub fn get_program_accounts_v2_page(
        &self,
        program_id: &Pubkey,
        memcmp_offset: usize,
        memcmp_bytes_base58: &str,
        limit: usize,
        pagination_key: Option<&str>,
        changed_since_slot: Option<u64>,
    ) -> Result<ProgramAccountsPage, RpcError> {
        let mut config = serde_json::Map::new();
        config.insert("encoding".into(), json!("base64"));
        config.insert("commitment".into(), json!("confirmed"));
        config.insert("withContext".into(), json!(true));
        config.insert("limit".into(), json!(limit));
        config.insert(
            "filters".into(),
            json!([{ "memcmp": { "offset": memcmp_offset, "bytes": memcmp_bytes_base58 } }]),
        );
        if let Some(key) = pagination_key {
            config.insert("paginationKey".into(), json!(key));
        }
        if let Some(slot) = changed_since_slot {
            config.insert("changedSinceSlot".into(), json!(slot));
        }
        let params = json!([program_id.to_string(), Value::Object(config)]);
        let result: Value = self.inner.send(
            RpcRequest::Custom {
                method: "getProgramAccountsV2",
            },
            params,
        )?;
        Ok(parse_v2_page(result))
    }
}

fn build_solana_rpc_client(url: String, timeout: Duration) -> SolanaRpcClient {
    let mut builder = reqwest::Client::builder()
        .no_proxy()
        .default_headers(HttpSender::default_headers())
        .timeout(timeout)
        .pool_idle_timeout(timeout);
    if is_loopback_https_url(&url) {
        builder = builder.danger_accept_invalid_certs(true);
    }

    let http_client = builder.build().expect("build Solana RPC HTTP client");
    let sender = HttpSender::new_with_client(url, http_client);
    SolanaRpcClient::new_sender(
        sender,
        RpcClientConfig::with_commitment(CommitmentConfig::confirmed()),
    )
}

fn is_loopback_https_url(url: &str) -> bool {
    let Ok(parsed) = reqwest::Url::parse(url) else {
        return false;
    };
    if parsed.scheme() != "https" {
        return false;
    }

    parsed
        .host_str()
        .map(|host| {
            let host = host.trim_start_matches('[').trim_end_matches(']');
            host.eq_ignore_ascii_case("localhost")
                || host
                    .parse::<IpAddr>()
                    .map(|address| address.is_loopback())
                    .unwrap_or(false)
        })
        .unwrap_or(false)
}

/// Parse a `getProgramAccountsV2` result (the `result` field, with `withContext`)
/// into a `ProgramAccountsPage`. Malformed entries are skipped rather than failing
/// the whole page.
fn parse_v2_page(result: Value) -> ProgramAccountsPage {
    let slot = result["context"]["slot"].as_u64().unwrap_or(0);
    let value = &result["value"];
    let pagination_key = value["paginationKey"].as_str().map(str::to_owned);
    let mut accounts = Vec::new();
    if let Some(entries) = value["accounts"].as_array() {
        for entry in entries {
            let Some(pubkey_str) = entry["pubkey"].as_str() else {
                continue;
            };
            let Ok(pubkey) = pubkey_str.parse::<Pubkey>() else {
                continue;
            };
            let Some(data_b64) = entry["account"]["data"][0].as_str() else {
                continue;
            };
            let Ok(data) = BASE64_STANDARD.decode(data_b64) else {
                continue;
            };
            accounts.push((pubkey, data));
        }
    }
    ProgramAccountsPage {
        accounts,
        pagination_key,
        slot,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rpc_client_constructs_with_url() {
        let client = RpcClient::new("https://api.devnet.solana.com".to_string());
        let _ = client; // Construction alone is the smoke; live RPC calls live in integration tests.
    }

    #[test]
    fn rpc_client_constructs_with_timeout() {
        let client = RpcClient::new_with_timeout(
            "https://api.devnet.solana.com".to_string(),
            Duration::from_secs(30),
        );
        let _ = client;
    }

    #[test]
    fn client_error_maps_to_rpc_error() {
        let err = ClientError::from(std::io::Error::other("boom"));
        let mapped: RpcError = err.into();
        assert!(matches!(mapped, RpcError::Client(_)));
    }

    #[test]
    fn loopback_https_detection_is_narrow() {
        assert!(is_loopback_https_url("https://localhost:59120"));
        assert!(is_loopback_https_url("https://127.0.0.1:59120"));
        assert!(is_loopback_https_url("https://[::1]:59120"));
        assert!(!is_loopback_https_url("http://localhost:59120"));
        assert!(!is_loopback_https_url("https://devnet.helius-rpc.com"));
        assert!(!is_loopback_https_url("not a url"));
    }

    #[test]
    fn parse_v2_page_extracts_accounts_key_and_slot() {
        use base64::{Engine, engine::general_purpose::STANDARD};
        let pk = Pubkey::new_unique();
        let data = STANDARD.encode([1u8, 2, 3, 4]);
        let result = serde_json::json!({
            "context": { "slot": 424242u64 },
            "value": {
                "accounts": [
                    { "pubkey": pk.to_string(),
                      "account": { "data": [data, "base64"], "owner": "x",
                                   "lamports": 0u64, "executable": false, "rentEpoch": 0u64 } }
                ],
                "paginationKey": "NEXTKEY"
            }
        });
        let page = parse_v2_page(result);
        assert_eq!(page.slot, 424242);
        assert_eq!(page.pagination_key.as_deref(), Some("NEXTKEY"));
        assert_eq!(page.accounts.len(), 1);
        assert_eq!(page.accounts[0].0, pk);
        assert_eq!(page.accounts[0].1, vec![1, 2, 3, 4]);
    }

    #[test]
    fn parse_v2_page_empty_end_of_pagination() {
        let result = serde_json::json!({
            "context": { "slot": 5u64 },
            "value": { "accounts": [], "paginationKey": serde_json::Value::Null }
        });
        let page = parse_v2_page(result);
        assert!(page.accounts.is_empty());
        assert_eq!(page.pagination_key, None);
        assert_eq!(page.slot, 5);
    }
}
