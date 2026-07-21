use std::{
    collections::{BTreeSet, HashMap},
    env,
    error::Error,
    io::{self, Read, Write},
    net::{IpAddr, SocketAddr, TcpListener, TcpStream},
    path::PathBuf,
    sync::{
        Arc, Condvar, Mutex, OnceLock,
        atomic::{AtomicUsize, Ordering},
    },
    time::{Duration, Instant},
};

use base64::{Engine, engine::general_purpose::STANDARD as BASE64_STANDARD};
use cosign_core::{
    rpc::RpcClient,
    squads::{ProposalCompanion, SquadsClient},
    transactions,
    types::{self, ConfigActionInfo, DecodedInstruction, ProposalCompanionRef, ProposalDetail},
};
use serde_json::{Value, json, value::RawValue};
use sha2::{Digest, Sha256};
use solana_client::client_error::reqwest;
use solana_sdk::{
    address_lookup_table::instruction::ProgramInstruction as AddressLookupTableInstruction,
    loader_upgradeable_instruction::UpgradeableLoaderInstruction,
    nonce::State as NonceState,
    pubkey::Pubkey,
    signature::Signature,
    stake::{
        instruction::StakeInstruction,
        state::{Authorized, StakeAuthorize},
    },
    system_instruction::SystemInstruction,
    transaction::{Transaction, VersionedTransaction},
};
use squads_multisig::{
    anchor_lang::Discriminator,
    squads_multisig_program::instruction::{
        ConfigTransactionExecute as ConfigTransactionExecuteData,
        ProposalApprove as ProposalApproveData, ProposalCancel as ProposalCancelData,
        ProposalCreate as ProposalCreateData, ProposalReject as ProposalRejectData,
        VaultTransactionExecute as VaultTransactionExecuteData,
    },
    state::{Multisig, Permission},
};
use url::form_urlencoded;

const DEFAULT_BIND_ADDR: &str = "127.0.0.1:8787";
const RPC_TIMEOUT: Duration = Duration::from_secs(30);
const DEFAULT_MAX_REQUEST_BODY_BYTES: usize = 2 * 1024 * 1024;
const MAX_REQUEST_HEADERS_BYTES: usize = 16 * 1024;
const DEFAULT_ACTIVITY_LIMIT: u32 = 50;
const MAX_ACTIVITY_LIMIT: u32 = 100;
const MAX_PROPOSAL_RANGE: u64 = 100;
const SYSTEM_PROGRAM_ID: &str = "11111111111111111111111111111111";
const SPL_TOKEN_PROGRAM_ID: &str = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA";
const TOKEN_2022_PROGRAM_ID: &str = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb";
const ASSOCIATED_TOKEN_ACCOUNT_PROGRAM_ID: &str = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL";
const MEMO_PROGRAM_ID: &str = "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr";
const MEMO_LEGACY_PROGRAM_ID: &str = "Memo1UhkJRfHyvLMcVucJwxXeuD728EqVDDwQDxFMNo";
const COMPUTE_BUDGET_PROGRAM_ID: &str = "ComputeBudget111111111111111111111111111111";
const STAKE_PROGRAM_ID: &str = "Stake11111111111111111111111111111111111111";
const ADDRESS_LOOKUP_TABLE_PROGRAM_ID: &str = "AddressLookupTab1e1111111111111111111111111";
const SQUADS_PROGRAM_ID: &str = "SQDS4ep65T869zMMBKyuUq6aD6EgTu8psMjkvj52pCf";
const BPF_UPGRADEABLE_LOADER_PROGRAM_ID: &str = "BPFLoaderUpgradeab1e11111111111111111111111";
const RPC_ALLOW_ALL_METHODS: &str = "*";
const DEFAULT_RPC_ALLOWED_METHODS: &[&str] = &[
    "getAccountInfo",
    "getAssetsByOwner",
    "getBalance",
    "getFeeForMessage",
    "getLatestBlockhash",
    "getMinimumBalanceForRentExemption",
    "getMultipleAccounts",
    "getProgramAccounts",
    "getSignatureStatuses",
    "getSignaturesForAddress",
    "getTokenAccountsByOwner",
    "getVersion",
    "sendTransaction",
    "simulateTransaction",
];

const DECODE_REGISTRY_BUNDLE: &str = include_str!("../../registry/decode-registry.json");
const DECODE_REGISTRY_SIGNATURE: &str = include_str!("../../registry/decode-registry.sig");

// Process-wide handle to the membership index, populated once at startup by
// main() if COSIGN_INDEX_DB_PATH is configured. Absent that, member reads
// fall back to live RPC (see resolve_member_squads).
#[cfg(feature = "relay-index")]
static MEMBERSHIP_INDEX: OnceLock<cosign_core::membership_index::MembershipIndex> = OnceLock::new();

#[cfg(feature = "landing")]
const LANDING_HTML: &str = include_str!("../../static/index.html");
#[cfg(feature = "landing")]
const PRIVACY_HTML: &str = include_str!("../../static/privacy.html");
#[cfg(feature = "landing")]
const FAVICON_SVG: &str = include_str!("../../static/favicon.svg");

// Product screenshots used by the landing page, served from /assets/*.png and
// baked into the binary so the page stays self-contained.
#[cfg(feature = "landing")]
const LANDING_ASSETS: &[(&str, &[u8])] = &[
    (
        "/assets/08-proposal-detail.png",
        include_bytes!("../../static/assets/08-proposal-detail.png"),
    ),
    (
        "/assets/10-proposal-signing-sheet.png",
        include_bytes!("../../static/assets/10-proposal-signing-sheet.png"),
    ),
    (
        "/assets/38-proposal-idl-confidence.png",
        include_bytes!("../../static/assets/38-proposal-idl-confidence.png"),
    ),
    (
        "/assets/35-add-yubikey.png",
        include_bytes!("../../static/assets/35-add-yubikey.png"),
    ),
    (
        "/assets/32-add-signer-chooser.png",
        include_bytes!("../../static/assets/32-add-signer-chooser.png"),
    ),
    (
        "/assets/41-import-recovery-phrase.png",
        include_bytes!("../../static/assets/41-import-recovery-phrase.png"),
    ),
    (
        "/assets/37-signer-detail.png",
        include_bytes!("../../static/assets/37-signer-detail.png"),
    ),
    (
        "/assets/12-transaction-inspection.png",
        include_bytes!("../../static/assets/12-transaction-inspection.png"),
    ),
    (
        "/assets/11-proposal-receipt.png",
        include_bytes!("../../static/assets/11-proposal-receipt.png"),
    ),
];

/// Cap on concurrent request-handler threads: a backstop against a connection flood
/// spawning unbounded threads. Normal and warmup traffic stay far below this; past
/// the cap the relay sheds load with a 503 rather than exhausting memory.
const MAX_CONCURRENT_REQUESTS: usize = 512;
static ACTIVE_REQUESTS: AtomicUsize = AtomicUsize::new(0);

/// How many live membership scans may run at once. Each is a full getProgramAccounts
/// that loads every Multisig account into memory, so a burst during index warmup
/// could exhaust the machine; bound it. The indexer thread runs its own build scan
/// ungated, so the true peak is this value plus one. Reads served from the warm index
/// are cheap and are NOT gated by this.
const LIVE_MEMBERSHIP_SCAN_PERMITS: usize = 2;
static LIVE_MEMBERSHIP_SCAN: Semaphore = Semaphore::new(LIVE_MEMBERSHIP_SCAN_PERMITS);

/// Decrements the in-flight request count when a handler thread finishes, including
/// on panic (Drop runs during unwinding).
struct RequestGuard;

impl Drop for RequestGuard {
    fn drop(&mut self) {
        ACTIVE_REQUESTS.fetch_sub(1, Ordering::Relaxed);
    }
}

/// WebSocket `/ws` proxies are long-lived, so they cannot share the short-request
/// concurrency cap (they would exhaust it immediately). They get their own, smaller
/// bound; without it, held-open `/ws` connections spawn unbounded detached threads,
/// because each proxy outlives the request handler that started it.
const MAX_WS_PROXIES: usize = 128;
static ACTIVE_WS_PROXIES: AtomicUsize = AtomicUsize::new(0);

/// Decrements the live WebSocket-proxy count when a proxy thread finishes, including
/// on panic. Moved into the pump thread so the count reflects proxies actually
/// running, not requests that merely started one.
struct WsProxyGuard;

impl Drop for WsProxyGuard {
    fn drop(&mut self) {
        ACTIVE_WS_PROXIES.fetch_sub(1, Ordering::Relaxed);
    }
}

/// A minimal counting semaphore (std has none) to bound concurrent expensive work.
struct Semaphore {
    permits: Mutex<usize>,
    available: Condvar,
}

impl Semaphore {
    const fn new(permits: usize) -> Self {
        Self {
            permits: Mutex::new(permits),
            available: Condvar::new(),
        }
    }

    /// Block (on the caller's thread only) until a permit is free, then take it. The
    /// permit is returned when the guard drops.
    fn acquire(&self) -> SemaphorePermit<'_> {
        let mut permits = self
            .permits
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        while *permits == 0 {
            permits = self
                .available
                .wait(permits)
                .unwrap_or_else(|poison| poison.into_inner());
        }
        *permits -= 1;
        SemaphorePermit { semaphore: self }
    }
}

struct SemaphorePermit<'a> {
    semaphore: &'a Semaphore,
}

impl Drop for SemaphorePermit<'_> {
    fn drop(&mut self) {
        *self
            .semaphore
            .permits
            .lock()
            .unwrap_or_else(|poison| poison.into_inner()) += 1;
        self.semaphore.available.notify_one();
    }
}

fn main() -> Result<(), Box<dyn Error>> {
    load_env_files();
    let config = RelayConfig::from_env()?;

    #[cfg(feature = "relay-index")]
    if let (Some(db_path), Some(rpc_url)) = (config.index_db_path.clone(), config.rpc_url.clone()) {
        match cosign_core::membership_index::MembershipIndex::open(&db_path) {
            Ok(index) => {
                let index_ref = MEMBERSHIP_INDEX.get_or_init(|| index);
                cosign_core::membership_indexer::spawn(
                    index_ref,
                    rpc_url,
                    config.web_socket_url.clone(),
                );
                println!("Membership index active: {db_path}");
            }
            Err(error) => {
                eprintln!("Membership index disabled ({error}); serving member reads live")
            }
        }
    }

    let config = Arc::new(config);
    let rate_limiter = Arc::new(Mutex::new(RateLimiter::new(config.rate_limits)));
    let listener = TcpListener::bind(config.bind_addr)?;

    println!("Cosign relay listening on http://{}", config.bind_addr);
    println!("Health route: /_health");
    println!("Capabilities route: /cosign/v1/capabilities");
    println!("Member Squads route: /cosign/v1/members/<MEMBER>/squads");
    println!("Squad detail route: /cosign/v1/squads/<SQUAD>");
    println!("Squad proposals route: /cosign/v1/squads/<SQUAD>/proposals?from=<FROM>&to=<TO>");
    println!("Squad proposal route: /cosign/v1/squads/<SQUAD>/proposals/<INDEX>");
    println!("Account activity route: /cosign/v1/accounts/<ADDRESS>/activity");
    println!("Transaction status route: /cosign/v1/transactions/<SIGNATURE>/status");
    println!(
        "Proposal inspection route: /cosign/v1/squads/<SQUAD>/transactions/<INDEX>/inspection"
    );
    println!("Transaction inspection route: /cosign/v1/transactions/<SIGNATURE>/inspection");

    // Handle each connection on its own thread so a slow request (for example a live
    // membership scan) can never block health checks or other requests.
    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                if ACTIVE_REQUESTS.fetch_add(1, Ordering::Relaxed) >= MAX_CONCURRENT_REQUESTS {
                    ACTIVE_REQUESTS.fetch_sub(1, Ordering::Relaxed);
                    shed_over_capacity(stream);
                    continue;
                }
                let config = Arc::clone(&config);
                let rate_limiter = Arc::clone(&rate_limiter);
                let spawned = std::thread::Builder::new().spawn(move || {
                    let _guard = RequestGuard;
                    if let Err(error) = handle_connection(stream, &config, &rate_limiter) {
                        eprintln!("relay request failed: {error}");
                    }
                });
                if let Err(error) = spawned {
                    ACTIVE_REQUESTS.fetch_sub(1, Ordering::Relaxed);
                    eprintln!("relay handler spawn failed: {error}");
                }
            }
            Err(error) => eprintln!("relay accept failed: {error}"),
        }
    }

    Ok(())
}

/// Reject a connection that arrives past the concurrency cap with a 503, rather than
/// spawning an unbounded number of handler threads.
fn shed_over_capacity(mut stream: TcpStream) {
    let response = error_response(503, ResponseFormat::Html, "relay temporarily at capacity");
    let _ = write_response(&mut stream, response);
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct RelayConfig {
    bind_addr: SocketAddr,
    rpc_url: Option<String>,
    web_socket_url: Option<String>,
    explorer_rpc_url: Option<String>,
    rpc_allowed_methods: BTreeSet<String>,
    rate_limits: RelayRateLimits,
    // When set, GET requests for the marketing paths return a 301 to this base
    // instead of serving the landing page, so a non-canonical host (the devnet
    // relay) points visitors at the single canonical site without affecting its
    // RPC/API role.
    landing_redirect: Option<String>,
    // Filesystem path to the SQLite membership index (a Fly volume mount in prod).
    // When unset, the relay runs without an index and serves member reads live.
    index_db_path: Option<String>,
}

impl RelayConfig {
    fn from_env() -> Result<Self, RelayError> {
        let rpc_url = env::var("COSIGN_RELAY_RPC_URL")
            .or_else(|_| env::var("COSIGN_DEVNET_RPC_URL"))
            .ok()
            .filter(|value| !value.trim().is_empty());
        // Upstream Solana WebSocket the relay proxies to. Defaults to the WS form
        // of the RPC URL (Helius serves both on the same host + api-key).
        let web_socket_url = env::var("COSIGN_RELAY_WEBSOCKET_URL")
            .ok()
            .filter(|value| !value.trim().is_empty())
            .or_else(|| rpc_url.as_deref().and_then(derive_ws_url));
        Ok(Self {
            bind_addr: env::var("COSIGN_RELAY_BIND_ADDR")
                .unwrap_or_else(|_| DEFAULT_BIND_ADDR.to_string())
                .parse()
                .map_err(|_| RelayError::BadRequest("invalid COSIGN_RELAY_BIND_ADDR".into()))?,
            rpc_url,
            web_socket_url,
            explorer_rpc_url: env::var("COSIGN_RELAY_EXPLORER_RPC_URL")
                .ok()
                .filter(|value| !value.trim().is_empty()),
            rpc_allowed_methods: rpc_allowed_methods_from_env(),
            rate_limits: RelayRateLimits::from_env()?,
            landing_redirect: env::var("COSIGN_LANDING_REDIRECT")
                .ok()
                .filter(|value| !value.trim().is_empty())
                .map(|value| value.trim_end_matches('/').to_string()),
            index_db_path: env::var("COSIGN_INDEX_DB_PATH")
                .ok()
                .filter(|value| !value.trim().is_empty()),
        })
    }

    fn rpc_url(&self) -> Result<String, RelayError> {
        if let Some(rpc_url) = &self.rpc_url {
            return Ok(rpc_url.clone());
        }

        Err(RelayError::BadRequest(
            "relay upstream RPC is not configured; set COSIGN_RELAY_RPC_URL".into(),
        ))
    }

    fn capabilities(&self) -> Vec<&'static str> {
        if self.rpc_url.is_some() {
            vec![
                "rpc_passthrough",
                "squads_indexing",
                "squad_detail",
                "squad_proposals",
                "proposal_detail",
                "account_activity",
                "transaction_status",
                "proposal_inspection",
                "executed_transaction_inspection",
                "known_program_decoding",
                "program_idl",
                "decode_registry",
                "mint_metadata",
                "action_effects",
                "rpc_method_filtering",
                "transaction_attribution",
                "asset_pricing",
            ]
        } else {
            Vec::new()
        }
    }

    fn is_rpc_method_allowed(&self, method: &str) -> bool {
        self.rpc_allowed_methods.contains(RPC_ALLOW_ALL_METHODS)
            || self.rpc_allowed_methods.contains(method)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct RelayRateLimits {
    enabled: bool,
    window: Duration,
    requests_per_window: u32,
    rpc_method_requests_per_window: u32,
    send_transaction_identity_requests_per_window: u32,
    max_request_body_bytes: usize,
}

impl RelayRateLimits {
    fn from_env() -> Result<Self, RelayError> {
        Ok(Self {
            enabled: env_bool("COSIGN_RELAY_RATE_LIMIT_ENABLED", true)?,
            window: Duration::from_secs(env_u64("COSIGN_RELAY_RATE_LIMIT_WINDOW_SECONDS", 60)?),
            requests_per_window: env_u32("COSIGN_RELAY_RATE_LIMIT_REQUESTS_PER_WINDOW", 600)?,
            rpc_method_requests_per_window: env_u32(
                "COSIGN_RELAY_RATE_LIMIT_RPC_METHODS_PER_WINDOW",
                300,
            )?,
            send_transaction_identity_requests_per_window: env_u32(
                "COSIGN_RELAY_RATE_LIMIT_SEND_TRANSACTIONS_PER_WINDOW",
                30,
            )?,
            max_request_body_bytes: env_usize(
                "COSIGN_RELAY_MAX_REQUEST_BODY_BYTES",
                DEFAULT_MAX_REQUEST_BODY_BYTES,
            )?,
        })
    }
}

impl Default for RelayRateLimits {
    fn default() -> Self {
        Self {
            enabled: true,
            window: Duration::from_secs(60),
            requests_per_window: 600,
            rpc_method_requests_per_window: 300,
            send_transaction_identity_requests_per_window: 30,
            max_request_body_bytes: DEFAULT_MAX_REQUEST_BODY_BYTES,
        }
    }
}

#[derive(Debug)]
struct RateLimiter {
    limits: RelayRateLimits,
    buckets: HashMap<RateLimitKey, RateLimitBucket>,
}

impl RateLimiter {
    fn new(limits: RelayRateLimits) -> Self {
        Self {
            limits,
            buckets: HashMap::new(),
        }
    }

    fn check_request(
        &mut self,
        client_ip: Option<IpAddr>,
        request: &HttpRequest,
        inspection: Option<&RpcPassthroughInspection>,
    ) -> Result<(), RelayError> {
        self.check_request_at(client_ip, request, inspection, Instant::now())
    }

    fn check_request_at(
        &mut self,
        client_ip: Option<IpAddr>,
        request: &HttpRequest,
        inspection: Option<&RpcPassthroughInspection>,
        now: Instant,
    ) -> Result<(), RelayError> {
        if !self.limits.enabled {
            return Ok(());
        }

        self.prune(now);

        let client = rate_limit_client(client_ip);
        self.check_bucket(
            RateLimitKey::Client {
                client: client.clone(),
            },
            self.limits.requests_per_window,
            now,
            "request rate limit exceeded",
        )?;

        if request.method == "POST"
            && request.path == "/"
            && let Some(inspection) = inspection
        {
            for method in &inspection.methods {
                self.check_bucket(
                    RateLimitKey::RpcMethod {
                        client: client.clone(),
                        method: method.clone(),
                    },
                    self.limits.rpc_method_requests_per_window,
                    now,
                    "RPC method rate limit exceeded",
                )?;
            }
            for submitted in &inspection.submitted_transactions {
                self.check_submitted_transaction_identity(submitted, now)?;
            }
        }

        Ok(())
    }

    fn check_submitted_transaction_identity(
        &mut self,
        submitted: &SubmittedTransactionIdentity,
        now: Instant,
    ) -> Result<(), RelayError> {
        if let Some(fee_payer) = &submitted.fee_payer {
            self.check_bucket(
                RateLimitKey::FeePayer {
                    fee_payer: fee_payer.clone(),
                },
                self.limits.send_transaction_identity_requests_per_window,
                now,
                "sendTransaction fee payer rate limit exceeded",
            )?;
        }

        for signer in &submitted.signers {
            self.check_bucket(
                RateLimitKey::Signer {
                    signer: signer.clone(),
                },
                self.limits.send_transaction_identity_requests_per_window,
                now,
                "sendTransaction signer rate limit exceeded",
            )?;
        }

        Ok(())
    }

    fn check_bucket(
        &mut self,
        key: RateLimitKey,
        limit: u32,
        now: Instant,
        message: &str,
    ) -> Result<(), RelayError> {
        if limit == 0 {
            return Ok(());
        }

        let bucket = self.buckets.entry(key).or_insert(RateLimitBucket {
            window_started_at: now,
            count: 0,
        });

        if now.duration_since(bucket.window_started_at) >= self.limits.window {
            bucket.window_started_at = now;
            bucket.count = 0;
        }

        if bucket.count >= limit {
            return Err(RelayError::RateLimited(message.into()));
        }

        bucket.count += 1;
        Ok(())
    }

    fn prune(&mut self, now: Instant) {
        let window = self.limits.window;
        self.buckets
            .retain(|_, bucket| now.duration_since(bucket.window_started_at) < window);
    }
}

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
enum RateLimitKey {
    Client { client: String },
    RpcMethod { client: String, method: String },
    FeePayer { fee_payer: String },
    Signer { signer: String },
}

#[derive(Clone, Debug)]
struct RateLimitBucket {
    window_started_at: Instant,
    count: u32,
}

fn rate_limit_client(client_ip: Option<IpAddr>) -> String {
    client_ip
        .map(|ip| ip.to_string())
        .unwrap_or_else(|| "unknown".into())
}

fn rpc_allowed_methods_from_env() -> BTreeSet<String> {
    let mut methods = default_rpc_allowed_methods();

    if let Ok(value) = env::var("COSIGN_RELAY_RPC_ALLOWED_METHODS") {
        for method in value
            .split(',')
            .map(str::trim)
            .filter(|method| !method.is_empty())
        {
            if method == RPC_ALLOW_ALL_METHODS {
                return BTreeSet::from([RPC_ALLOW_ALL_METHODS.to_string()]);
            }
            methods.insert(method.to_string());
        }
    }

    methods
}

fn default_rpc_allowed_methods() -> BTreeSet<String> {
    DEFAULT_RPC_ALLOWED_METHODS
        .iter()
        .map(|method| (*method).to_string())
        .collect()
}

fn env_bool(name: &str, default: bool) -> Result<bool, RelayError> {
    let Ok(value) = env::var(name) else {
        return Ok(default);
    };
    match value.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" => Ok(true),
        "0" | "false" | "no" => Ok(false),
        _ => Err(RelayError::BadRequest(format!("invalid {name}"))),
    }
}

fn env_u32(name: &str, default: u32) -> Result<u32, RelayError> {
    let Ok(value) = env::var(name) else {
        return Ok(default);
    };
    value
        .trim()
        .parse()
        .map_err(|_| RelayError::BadRequest(format!("invalid {name}")))
}

fn env_u64(name: &str, default: u64) -> Result<u64, RelayError> {
    let Ok(value) = env::var(name) else {
        return Ok(default);
    };
    value
        .trim()
        .parse()
        .map_err(|_| RelayError::BadRequest(format!("invalid {name}")))
}

fn env_usize(name: &str, default: usize) -> Result<usize, RelayError> {
    let Ok(value) = env::var(name) else {
        return Ok(default);
    };
    value
        .trim()
        .parse()
        .map_err(|_| RelayError::BadRequest(format!("invalid {name}")))
}

#[derive(Debug, Eq, PartialEq)]
struct HttpRequest {
    method: String,
    path: String,
    query: Option<String>,
    body: Vec<u8>,
    host: Option<String>,
    /// Present when this is a WebSocket upgrade request (the Sec-WebSocket-Key).
    websocket_key: Option<String>,
    if_none_match: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct RpcPassthroughInspection {
    methods: Vec<String>,
    submitted_transactions: Vec<SubmittedTransactionIdentity>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct SubmittedTransactionIdentity {
    signature: String,
    fee_payer: Option<String>,
    signers: Vec<String>,
    encoding: String,
}

#[derive(Debug, Eq, PartialEq)]
struct ProposalInspectionRequest {
    squad: Pubkey,
    transaction_index: u64,
    query: InspectionQuery,
}

#[derive(Debug, Eq, PartialEq)]
struct TransactionInspectionRequest {
    signature: Signature,
    query: InspectionQuery,
}

#[derive(Debug, Eq, PartialEq)]
struct TransactionStatusRequest {
    signature: Signature,
}

#[derive(Debug, Eq, PartialEq)]
struct MemberSquadsRequest {
    member: Pubkey,
}

#[derive(Debug, Eq, PartialEq)]
struct SquadDetailRequest {
    squad: Pubkey,
}

#[derive(Debug, Eq, PartialEq)]
struct SquadProposalsRequest {
    squad: Pubkey,
    from_index: u64,
    to_index: u64,
}

#[derive(Debug, Eq, PartialEq)]
struct SquadProposalRequest {
    squad: Pubkey,
    transaction_index: u64,
}

#[derive(Debug, Eq, PartialEq)]
struct AccountActivityRequest {
    address: Pubkey,
    before: Option<Signature>,
    limit: u32,
}

#[derive(Debug, Eq, PartialEq)]
enum InspectionRequest {
    Proposal(ProposalInspectionRequest),
    Transaction(TransactionInspectionRequest),
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct InspectionQuery {
    format: ResponseFormat,
}

impl InspectionQuery {
    fn parse(query: Option<&str>) -> Self {
        let mut parsed = Self {
            format: ResponseFormat::Html,
        };

        let Some(query) = query else {
            return parsed;
        };

        for (key, value) in form_urlencoded::parse(query.as_bytes()) {
            match key.as_ref() {
                "format" if value.eq_ignore_ascii_case("json") => {
                    parsed.format = ResponseFormat::Json;
                }
                _ => {}
            }
        }

        parsed
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
enum ResponseFormat {
    #[default]
    Html,
    Json,
}

#[derive(Debug, thiserror::Error)]
enum RelayError {
    #[error("{0}")]
    BadRequest(String),
    #[error("{0}")]
    Forbidden(String),
    #[error("not found")]
    NotFound,
    #[error("{0}")]
    RateLimited(String),
    #[error("{0}")]
    Rpc(String),
    #[error("{0}")]
    Io(#[from] io::Error),
}

fn handle_connection(
    mut stream: TcpStream,
    config: &RelayConfig,
    rate_limiter: &Mutex<RateLimiter>,
) -> Result<(), RelayError> {
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;
    // A client that stops reading must not pin this handler thread (and its
    // MAX_CONCURRENT_REQUESTS slot) indefinitely, which would let slow readers
    // exhaust the pool. Bound writes as well as reads.
    stream.set_write_timeout(Some(Duration::from_secs(30)))?;
    let client_ip = stream.peer_addr().ok().map(|address| address.ip());
    let Some(request) = read_request(&mut stream, config.rate_limits.max_request_body_bytes)?
    else {
        return Ok(());
    };

    // WebSocket upgrade on /ws → proxy to the upstream Solana WS on its own thread.
    if request.path == "/ws"
        && let Some(key) = request.websocket_key.clone()
    {
        let rate = check_rate_limit(rate_limiter, client_ip, &request, None);
        return start_ws_proxy(stream, &key, config, rate);
    }

    // Inspect the RPC passthrough body once, before taking the rate-limiter lock, so
    // parsing and transaction decoding never run while the shared mutex is held.
    let inspection = if request.method == "POST" && request.path == "/" {
        match inspect_rpc_passthrough_request(config, &request.body) {
            Ok(inspection) => Some(inspection),
            Err(error) => {
                let response = relay_json_error_response(error);
                eprintln!("{} {} -> {}", request.method, request.path, response.status);
                return write_response(&mut stream, response);
            }
        }
    } else {
        None
    };

    let response = match check_rate_limit(rate_limiter, client_ip, &request, inspection.as_ref()) {
        Ok(()) => handle_request_with_client(&request, config, client_ip),
        Err(error) if request.method == "POST" && request.path == "/" => {
            relay_json_error_response(error)
        }
        Err(error) => relay_error_response(error, request.query.as_deref()),
    };
    eprintln!("{} {} -> {}", request.method, request.path, response.status);
    write_response(&mut stream, response)
}

/// Lock the shared rate limiter for the check only, never across request handling, so
/// a slow request cannot serialize the whole relay behind the limiter mutex. The RPC
/// passthrough body is inspected by the caller before locking and the result passed in,
/// so no request parsing happens under the lock.
fn check_rate_limit(
    rate_limiter: &Mutex<RateLimiter>,
    client_ip: Option<IpAddr>,
    request: &HttpRequest,
    inspection: Option<&RpcPassthroughInspection>,
) -> Result<(), RelayError> {
    rate_limiter
        .lock()
        .unwrap_or_else(|poison| poison.into_inner())
        .check_request(client_ip, request, inspection)
}

fn handle_request_with_client(
    request: &HttpRequest,
    config: &RelayConfig,
    client_ip: Option<IpAddr>,
) -> HttpResponse {
    if request.method == "POST" && request.path == "/" {
        return match proxy_rpc_request(config, &request.body, client_ip) {
            Ok(response) => response,
            Err(error) => relay_json_error_response(error),
        };
    }

    if request.method == "GET" && request.path == "/_health" {
        return health_response();
    }

    if request.method == "GET"
        && let Some(base) = config.landing_redirect.as_deref()
        && is_landing_path(&request.path)
    {
        return redirect_response(format!("{base}{}", request.path));
    }

    #[cfg(feature = "landing")]
    if request.method == "GET" && request.path == "/" {
        return html_response(200, LANDING_HTML.to_string());
    }

    #[cfg(feature = "landing")]
    if request.method == "GET" && request.path == "/privacy" {
        return html_response(200, PRIVACY_HTML.to_string());
    }

    #[cfg(feature = "landing")]
    if request.method == "GET" && request.path == "/favicon.svg" {
        return HttpResponse {
            status: 200,
            reason: reason_phrase(200),
            content_type: "image/svg+xml; charset=utf-8",
            body: FAVICON_SVG.as_bytes().to_vec(),
            extra_headers: Vec::new(),
        };
    }

    #[cfg(feature = "landing")]
    if request.method == "GET"
        && let Some((_, bytes)) = LANDING_ASSETS
            .iter()
            .find(|(path, _)| *path == request.path)
    {
        return HttpResponse {
            status: 200,
            reason: reason_phrase(200),
            content_type: "image/png",
            body: bytes.to_vec(),
            extra_headers: Vec::new(),
        };
    }

    if request.method == "GET" && request.path == "/cosign/v1/capabilities" {
        return capabilities_response(config, request.host.as_deref());
    }

    if request.method == "GET" && request.path == "/cosign/v1/prices" {
        return prices_response(request.query.as_deref());
    }

    if request.method == "GET" && request.path == "/cosign/v1/release" {
        return release_response();
    }

    if request.method == "GET" && request.path == "/cosign/v1/decode-registry" {
        return decode_registry_response();
    }

    if request.method == "GET"
        && let Some(account) = parse_mint_metadata_request(&request.path)
    {
        return match resolve_mint_metadata(config, &account) {
            Ok(metadata) => mint_metadata_json_response(&metadata),
            Err(RelayError::NotFound) => mint_metadata_not_found_response(),
            Err(error) => relay_error_response(error, request.query.as_deref()),
        };
    }

    if request.method != "GET" {
        return error_response(405, ResponseFormat::Html, "method not allowed");
    }

    match parse_member_squads_request(&request.path) {
        Ok(parsed) => {
            return match resolve_member_squads(config, &parsed) {
                Ok((result, source)) => {
                    member_squads_json_response(&parsed.member, &result, source)
                }
                Err(error) => relay_error_response(error, request.query.as_deref()),
            };
        }
        Err(RelayError::NotFound) => {}
        Err(error) => return relay_error_response(error, request.query.as_deref()),
    }

    match parse_squad_proposals_request(&request.path, request.query.as_deref()) {
        Ok(parsed) => {
            return match resolve_squad_proposals(config, &parsed) {
                Ok(result) => squad_proposals_json_response(&parsed, &result),
                Err(error) => relay_error_response(error, request.query.as_deref()),
            };
        }
        Err(RelayError::NotFound) => {}
        Err(error) => return relay_error_response(error, request.query.as_deref()),
    }

    match parse_squad_proposal_request(&request.path) {
        Ok(parsed) => {
            return match resolve_squad_proposal(config, &parsed) {
                Ok(result) => squad_proposal_json_response(&parsed.squad, &result),
                Err(error) => relay_error_response(error, request.query.as_deref()),
            };
        }
        Err(RelayError::NotFound) => {}
        Err(error) => return relay_error_response(error, request.query.as_deref()),
    }

    match parse_squad_detail_request(&request.path) {
        Ok(parsed) => {
            return match resolve_squad_detail(config, &parsed) {
                Ok(result) => squad_detail_json_response(&result),
                Err(error) => relay_error_response(error, request.query.as_deref()),
            };
        }
        Err(RelayError::NotFound) => {}
        Err(error) => return relay_error_response(error, request.query.as_deref()),
    }

    match parse_account_activity_request(&request.path, request.query.as_deref()) {
        Ok(parsed) => {
            return match resolve_account_activity(config, &parsed) {
                Ok(result) => account_activity_json_response(&parsed, &result),
                Err(error) => relay_error_response(error, request.query.as_deref()),
            };
        }
        Err(RelayError::NotFound) => {}
        Err(error) => return relay_error_response(error, request.query.as_deref()),
    }

    match parse_transaction_status_request(&request.path) {
        Ok(parsed) => {
            return match resolve_transaction_status(config, &parsed) {
                Ok(result) => transaction_status_json_response(&parsed.signature, &result),
                Err(error) => relay_error_response(error, request.query.as_deref()),
            };
        }
        Err(RelayError::NotFound) => {}
        Err(error) => return relay_error_response(error, request.query.as_deref()),
    }

    match parse_program_idl_request(&request.path) {
        Ok(parsed) => {
            return match resolve_program_idl(config, &parsed.program) {
                Ok(idl) if if_none_match_hits(request.if_none_match.as_deref(), &idl.hash) => {
                    not_modified_response(&idl.hash, IDL_CACHE_MAX_AGE_SECS)
                }
                Ok(idl) => program_idl_json_response(&idl),
                Err(RelayError::NotFound) => program_idl_not_found_response(),
                Err(error) => relay_error_response(error, request.query.as_deref()),
            };
        }
        Err(RelayError::NotFound) => {}
        Err(error) => return relay_error_response(error, request.query.as_deref()),
    }

    let parsed = match parse_inspection_request(&request.path, request.query.as_deref()) {
        Ok(request) => request,
        Err(error) => return relay_error_response(error, request.query.as_deref()),
    };

    match parsed {
        InspectionRequest::Proposal(parsed) => match resolve_proposal(config, &parsed) {
            Ok(result) => match parsed.query.format {
                ResponseFormat::Html => proposal_inspection_html_response(&result),
                ResponseFormat::Json => proposal_inspection_json_response(&result),
            },
            Err(error) => relay_error_response(error, request.query.as_deref()),
        },
        InspectionRequest::Transaction(parsed) => match resolve_transaction(config, &parsed) {
            Ok(result) => match parsed.query.format {
                ResponseFormat::Html => transaction_inspection_html_response(&result),
                ResponseFormat::Json => transaction_inspection_json_response(&result),
            },
            Err(error) => relay_error_response(error, request.query.as_deref()),
        },
    }
}

fn proxy_rpc_request(
    config: &RelayConfig,
    body: &[u8],
    client_ip: Option<IpAddr>,
) -> Result<HttpResponse, RelayError> {
    let Some(rpc_url) = &config.rpc_url else {
        return Err(RelayError::BadRequest(
            "relay RPC passthrough requires COSIGN_RELAY_RPC_URL".into(),
        ));
    };

    let inspection = inspect_rpc_passthrough_request(config, body)?;
    for submitted in &inspection.submitted_transactions {
        log_submitted_transaction(client_ip, submitted);
    }

    let client = reqwest::blocking::Client::builder()
        .no_proxy()
        .timeout(RPC_TIMEOUT)
        .build()
        .map_err(|error| RelayError::Rpc(error.to_string()))?;
    let response = client
        .post(rpc_url)
        .header("content-type", "application/json")
        .body(body.to_vec())
        .send()
        .map_err(|error| RelayError::Rpc(error.to_string()))?;
    let status = response.status().as_u16();
    let body = response
        .bytes()
        .map_err(|error| RelayError::Rpc(error.to_string()))?
        .to_vec();

    Ok(HttpResponse {
        status,
        reason: reason_phrase(status),
        content_type: "application/json; charset=utf-8",
        body,
        extra_headers: Vec::new(),
    })
}

fn inspect_rpc_passthrough_request(
    config: &RelayConfig,
    body: &[u8],
) -> Result<RpcPassthroughInspection, RelayError> {
    let payload = serde_json::from_slice::<Value>(body)
        .map_err(|_| RelayError::BadRequest("invalid JSON-RPC request body".into()))?;

    let requests = match &payload {
        Value::Array(requests) if !requests.is_empty() => requests.as_slice(),
        Value::Array(_) => {
            return Err(RelayError::BadRequest(
                "empty JSON-RPC batches are not supported".into(),
            ));
        }
        request => std::slice::from_ref(request),
    };

    let mut methods = Vec::with_capacity(requests.len());
    let mut submitted_transactions = Vec::new();
    for request in requests {
        let method = request
            .get("method")
            .and_then(Value::as_str)
            .ok_or_else(|| RelayError::BadRequest("JSON-RPC request is missing method".into()))?;

        if !config.is_rpc_method_allowed(method) {
            return Err(RelayError::Forbidden(format!(
                "RPC method {method} is not allowed by this relay"
            )));
        }

        methods.push(method.to_string());
        if method == "sendTransaction" {
            submitted_transactions.push(submitted_transaction_identity(request)?);
        }
    }

    Ok(RpcPassthroughInspection {
        methods,
        submitted_transactions,
    })
}

fn submitted_transaction_identity(
    request: &Value,
) -> Result<SubmittedTransactionIdentity, RelayError> {
    let params = request
        .get("params")
        .and_then(Value::as_array)
        .ok_or_else(|| RelayError::BadRequest("sendTransaction params must be an array".into()))?;
    let encoded_transaction = params.first().and_then(Value::as_str).ok_or_else(|| {
        RelayError::BadRequest("sendTransaction is missing transaction data".into())
    })?;
    let encoding = params
        .get(1)
        .and_then(|value| value.get("encoding"))
        .and_then(Value::as_str)
        .unwrap_or("base58");

    let transaction_bytes = decode_encoded_transaction(encoded_transaction, encoding)?;
    transaction_identity_from_bytes(&transaction_bytes, encoding).ok_or_else(|| {
        RelayError::BadRequest("sendTransaction contains an invalid transaction".into())
    })
}

fn decode_encoded_transaction(value: &str, encoding: &str) -> Result<Vec<u8>, RelayError> {
    match encoding.to_ascii_lowercase().as_str() {
        "base64" => BASE64_STANDARD
            .decode(value)
            .map_err(|_| RelayError::BadRequest("sendTransaction base64 is invalid".into())),
        "base58" => bs58::decode(value)
            .into_vec()
            .map_err(|_| RelayError::BadRequest("sendTransaction base58 is invalid".into())),
        other => Err(RelayError::BadRequest(format!(
            "sendTransaction encoding {other} is not supported by this relay"
        ))),
    }
}

fn transaction_identity_from_bytes(
    bytes: &[u8],
    encoding: &str,
) -> Option<SubmittedTransactionIdentity> {
    if let Ok(transaction) = bincode::deserialize::<VersionedTransaction>(bytes) {
        let signature = transaction.signatures.first()?.to_string();
        let required_signers = transaction.message.header().num_required_signatures as usize;
        let static_keys = transaction.message.static_account_keys();
        let signers = static_keys
            .iter()
            .take(required_signers)
            .map(ToString::to_string)
            .collect::<Vec<_>>();
        return Some(SubmittedTransactionIdentity {
            signature,
            fee_payer: static_keys.first().map(ToString::to_string),
            signers,
            encoding: encoding.to_string(),
        });
    }

    let transaction = bincode::deserialize::<Transaction>(bytes).ok()?;
    let signature = transaction.signatures.first()?.to_string();
    let required_signers = transaction.message.header.num_required_signatures as usize;
    let signers = transaction
        .message
        .account_keys
        .iter()
        .take(required_signers)
        .map(ToString::to_string)
        .collect::<Vec<_>>();
    Some(SubmittedTransactionIdentity {
        signature,
        fee_payer: transaction
            .message
            .account_keys
            .first()
            .map(ToString::to_string),
        signers,
        encoding: encoding.to_string(),
    })
}

fn log_submitted_transaction(client_ip: Option<IpAddr>, submitted: &SubmittedTransactionIdentity) {
    let event = submitted_transaction_log_event(client_ip, submitted);
    let line = serde_json::to_string(&event)
        .unwrap_or_else(|_| "{\"event\":\"rpc_send_transaction\"}".into());
    eprintln!("{line}");
}

fn submitted_transaction_log_event(
    client_ip: Option<IpAddr>,
    submitted: &SubmittedTransactionIdentity,
) -> Value {
    json!({
        "event": "rpc_send_transaction",
        "clientIp": client_ip.map(|ip| ip.to_string()),
        "signature": &submitted.signature,
        "feePayer": &submitted.fee_payer,
        "signers": &submitted.signers,
        "encoding": &submitted.encoding
    })
}

fn resolve_member_squads(
    config: &RelayConfig,
    request: &MemberSquadsRequest,
) -> Result<(Vec<types::MultisigSummary>, &'static str), RelayError> {
    #[cfg(feature = "relay-index")]
    if let Some(hits) = read_membership_index(&request.member) {
        return Ok((hits, "index"));
    }

    // Live fallback: a full getProgramAccounts scan that loads every Multisig account
    // into memory. Bound how many run at once so a burst during index warmup cannot
    // exhaust the machine. Cheap index reads above are not gated by this.
    let _permit = LIVE_MEMBERSHIP_SCAN.acquire();

    // The index may have become fresh while we waited for a permit; prefer it.
    #[cfg(feature = "relay-index")]
    if let Some(hits) = read_membership_index(&request.member) {
        return Ok((hits, "index"));
    }

    let rpc_url = config.rpc_url()?;
    let client = SquadsClient::new(RpcClient::new(rpc_url));
    let hits = client
        .get_membership(&request.member)
        .map_err(|error| RelayError::Rpc(error.to_string()))?;
    let summaries = hits
        .iter()
        .map(|(address, multisig)| types::multisig_summary(address, multisig))
        .collect();
    Ok((summaries, "live"))
}

/// Read a member's squads from the index when it is warm and fresh. Returns None if
/// there is no index, it is not fresh, or the query errors, so the caller falls back
/// to a live scan.
#[cfg(feature = "relay-index")]
fn read_membership_index(member: &Pubkey) -> Option<Vec<types::MultisigSummary>> {
    let index = MEMBERSHIP_INDEX.get()?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    if !index.is_fresh(now) {
        return None;
    }
    index.squads_for_member(member).ok()
}

fn resolve_squad_detail(
    config: &RelayConfig,
    request: &SquadDetailRequest,
) -> Result<types::MultisigDetail, RelayError> {
    let rpc_url = config.rpc_url()?;
    let client = SquadsClient::new(RpcClient::new(rpc_url));
    let multisig = client
        .get_multisig(&request.squad)
        .map_err(|error| RelayError::Rpc(error.to_string()))?;
    let vault_indices = client
        .discover_vault_indices(&request.squad)
        .map_err(|error| RelayError::Rpc(error.to_string()))?;
    Ok(types::multisig_detail(
        &request.squad,
        &multisig,
        &client.program_id(),
        &vault_indices,
    ))
}

fn resolve_squad_proposals(
    config: &RelayConfig,
    request: &SquadProposalsRequest,
) -> Result<Vec<types::ProposalSummary>, RelayError> {
    let rpc_url = config.rpc_url()?;
    let client = SquadsClient::new(RpcClient::new(rpc_url));
    let multisig = client
        .get_multisig(&request.squad)
        .map_err(|error| RelayError::Rpc(error.to_string()))?;
    client
        .get_proposals_range(&request.squad, request.from_index, request.to_index)
        .map(|proposals| {
            proposals
                .iter()
                .map(|(index, proposal)| {
                    types::proposal_summary(*index, proposal, multisig.threshold)
                })
                .collect()
        })
        .map_err(|error| RelayError::Rpc(error.to_string()))
}

fn resolve_squad_proposal(
    config: &RelayConfig,
    request: &SquadProposalRequest,
) -> Result<types::ProposalDetail, RelayError> {
    let rpc_url = config.rpc_url()?;
    let client = SquadsClient::new(RpcClient::new(rpc_url));
    let multisig = client
        .get_multisig(&request.squad)
        .map_err(|error| RelayError::Rpc(error.to_string()))?;
    let proposal = client
        .get_proposal(&request.squad, request.transaction_index)
        .map_err(|error| RelayError::Rpc(error.to_string()))?;
    let companion = match &proposal.companion {
        ProposalCompanion::Vault(vault) => ProposalCompanionRef::Vault(vault),
        ProposalCompanion::Config(config) => ProposalCompanionRef::Config(config),
    };
    Ok(types::proposal_detail(
        request.transaction_index,
        &proposal.proposal,
        multisig.threshold,
        &companion,
        Some(&proposal.companion_address),
    ))
}

fn resolve_account_activity(
    config: &RelayConfig,
    request: &AccountActivityRequest,
) -> Result<Vec<ActivityInspectionItem>, RelayError> {
    let rpc_url = config.rpc_url()?;
    let client = SquadsClient::new(RpcClient::new(rpc_url.clone()));
    let items = client
        .get_activity(&request.address, request.before, request.limit)
        .map_err(|error| RelayError::Rpc(error.to_string()))?;

    Ok(items
        .iter()
        .map(types::activity_item)
        .map(|item| {
            let action = activity_action(&rpc_url, &item);
            ActivityInspectionItem { item, action }
        })
        .collect())
}

fn activity_action(rpc_url: &str, item: &types::ActivityItem) -> Option<InspectionAction> {
    if item.error.is_some() {
        return None;
    }

    let transaction = fetch_transaction_json(rpc_url, &item.signature).ok()??;
    let mut action = action_from_transaction_json(&transaction);
    resolve_missing_transfer_assets(&mut action, rpc_url);
    (action.confidence != "low").then_some(action)
}

fn resolve_transaction_status(
    config: &RelayConfig,
    request: &TransactionStatusRequest,
) -> Result<transactions::SignatureStatus, RelayError> {
    let rpc_url = config.rpc_url()?;
    transactions::get_signature_status(RpcClient::new(rpc_url), request.signature)
        .map_err(|error| RelayError::Rpc(error.to_string()))
}

fn resolve_proposal(
    config: &RelayConfig,
    request: &ProposalInspectionRequest,
) -> Result<ProposalInspection, RelayError> {
    let rpc_url = config.rpc_url()?;
    let client = SquadsClient::new(RpcClient::new(rpc_url.clone()));
    let multisig = client
        .get_multisig(&request.squad)
        .map_err(|error| RelayError::Rpc(error.to_string()))?;
    let proposal = client
        .get_proposal(&request.squad, request.transaction_index)
        .map_err(|error| RelayError::Rpc(error.to_string()))?;
    let companion = match &proposal.companion {
        ProposalCompanion::Vault(vault) => ProposalCompanionRef::Vault(vault),
        ProposalCompanion::Config(config) => ProposalCompanionRef::Config(config),
    };
    let detail = types::proposal_detail(
        request.transaction_index,
        &proposal.proposal,
        multisig.threshold,
        &companion,
        Some(&proposal.companion_address),
    );
    let simulation = simulate_execution(&rpc_url, request, &multisig, &proposal.companion, &detail);

    let mut action = action_from_decoded_instructions(&decoded_proposal_instructions(&detail));
    resolve_missing_transfer_assets(&mut action, &rpc_url);

    Ok(ProposalInspection {
        squad: request.squad.to_string(),
        detail,
        action,
        cluster: None,
        simulation,
    })
}

fn resolve_transaction(
    config: &RelayConfig,
    request: &TransactionInspectionRequest,
) -> Result<TransactionInspection, RelayError> {
    let rpc_url = config.rpc_url()?;
    let signature = request.signature.to_string();
    let status =
        transactions::get_signature_status(RpcClient::new(rpc_url.clone()), request.signature)
            .map_err(|error| RelayError::Rpc(error.to_string()))?;
    let transaction = fetch_transaction_json(&rpc_url, &signature)?;
    let status = TransactionStatusSummary {
        status: status.status,
        slot: transaction
            .as_ref()
            .and_then(|value| value.get("slot").and_then(Value::as_u64))
            .or(status.slot),
        block_time: transaction
            .as_ref()
            .and_then(|value| value.get("blockTime").and_then(Value::as_i64)),
        error: transaction
            .as_ref()
            .and_then(transaction_error)
            .or(status.err),
    };
    let logs = transaction
        .as_ref()
        .map(transaction_logs)
        .unwrap_or_default();
    let mut action = transaction
        .as_ref()
        .map(action_from_transaction_json)
        .unwrap_or_else(|| {
            InspectionAction::unknown("Transaction details are not available from RPC.")
        });
    resolve_missing_transfer_assets(&mut action, &rpc_url);

    Ok(TransactionInspection {
        signature,
        cluster: None,
        status,
        action,
        logs,
    })
}

struct ParsedIdlAccount {
    authority: Pubkey,
    idl_json: Vec<u8>,
}

/// Anchor's canonical IDL account address: a seed account owned by the program's
/// base signer. Reading it is trusting the same party that deploys the program.
fn derive_idl_address(program_id: &Pubkey) -> Option<Pubkey> {
    let base = Pubkey::find_program_address(&[], program_id).0;
    Pubkey::create_with_seed(&base, "anchor:idl", program_id).ok()
}

/// Layout: [8 discriminator][32 authority][4 data_len LE][data_len zlib(IDL JSON)].
/// A too-short or truncated account is treated as "no usable IDL" (NotFound) so
/// the caller falls through a tier rather than surfacing an error. A `data_len`
/// of 0 decodes to an empty `idl_json`, which `resolve_program_idl` then fails
/// to parse as JSON, so a degenerate account still fails safe rather than
/// serving an empty IDL.
fn parse_idl_account(data: &[u8]) -> Result<ParsedIdlAccount, RelayError> {
    const HEADER_LEN: usize = 8 + 32 + 4;
    if data.len() < HEADER_LEN {
        return Err(RelayError::NotFound);
    }

    let authority = Pubkey::try_from(&data[8..40]).map_err(|_| RelayError::NotFound)?;
    let data_len = u32::from_le_bytes([data[40], data[41], data[42], data[43]]) as usize;

    let end = HEADER_LEN
        .checked_add(data_len)
        .ok_or(RelayError::NotFound)?;
    if data.len() < end {
        return Err(RelayError::NotFound);
    }
    let compressed = &data[HEADER_LEN..end];

    let mut idl_json = Vec::new();
    std::io::Read::read_to_end(
        &mut flate2::read::ZlibDecoder::new(compressed),
        &mut idl_json,
    )
    .map_err(|error| RelayError::Rpc(format!("idl decompression failed: {error}")))?;

    Ok(ParsedIdlAccount {
        authority,
        idl_json,
    })
}

#[derive(Clone)]
struct FetchedIdl {
    program: String,
    idl_json: Box<RawValue>,
    hash: String,
    slot: u64,
    authority: String,
}

/// An `IDL_CACHE` entry: either a resolved IDL, or a remembered miss (no
/// derivable PDA / no account at that PDA) so repeated lookups for the same
/// absent IDL don't keep hitting RPC.
#[derive(Clone)]
enum IdlCacheEntry {
    Found(FetchedIdl),
    Missing,
}

fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hasher
        .finalize()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

/// Raw JSON-RPC getAccountInfo. Returns (account data bytes, slot), or None when
/// the account does not exist.
fn fetch_account_info(
    rpc_url: &str,
    address: &Pubkey,
) -> Result<Option<(Vec<u8>, u64)>, RelayError> {
    let client = reqwest::blocking::Client::builder()
        .no_proxy()
        .timeout(RPC_TIMEOUT)
        .build()
        .map_err(|error| RelayError::Rpc(error.to_string()))?;
    let response = client
        .post(rpc_url)
        .json(&json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getAccountInfo",
            "params": [
                address.to_string(),
                { "encoding": "base64", "commitment": "confirmed" }
            ]
        }))
        .send()
        .map_err(|error| RelayError::Rpc(error.to_string()))?;

    let status = response.status();
    let body: Value = response
        .json()
        .map_err(|error| RelayError::Rpc(error.to_string()))?;
    if !status.is_success() {
        return Err(RelayError::Rpc(format!(
            "getAccountInfo returned HTTP {}",
            status.as_u16()
        )));
    }
    if let Some(error) = body.get("error") {
        return Err(RelayError::Rpc(error.to_string()));
    }

    let result = &body["result"];
    let slot = result["context"]["slot"].as_u64().unwrap_or(0);
    let value = &result["value"];
    if value.is_null() {
        return Ok(None);
    }
    let data_b64 = value["data"][0]
        .as_str()
        .ok_or_else(|| RelayError::Rpc("getAccountInfo value.data missing".into()))?;
    let data = BASE64_STANDARD
        .decode(data_b64)
        .map_err(|error| RelayError::Rpc(error.to_string()))?;
    Ok(Some((data, slot)))
}

#[derive(Debug, PartialEq)]
enum SplAccount {
    Mint { decimals: u8 },
    TokenAccount { mint: Pubkey },
}

/// Classifies raw account data as an SPL Mint (82 bytes; decimals at offset 44) or
/// SPL Token Account (165 bytes; mint at bytes 0..32). Token-2022 base layouts share
/// these sizes; extended accounts (len > 165) carry an AccountType byte at offset 165
/// (1 = Mint, 2 = Account). Anything else fails safe to None.
fn parse_spl_account(data: &[u8]) -> Option<SplAccount> {
    match data.len() {
        82 => Some(SplAccount::Mint { decimals: data[44] }),
        165 => Some(SplAccount::TokenAccount {
            mint: Pubkey::try_from(&data[0..32]).ok()?,
        }),
        len if len > 165 => match data[165] {
            1 => Some(SplAccount::Mint { decimals: data[44] }),
            2 => Some(SplAccount::TokenAccount {
                mint: Pubkey::try_from(&data[0..32]).ok()?,
            }),
            _ => None,
        },
        _ => None,
    }
}

const WELL_KNOWN_MINT_SYMBOLS: &[(&str, &str)] = &[
    ("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", "USDC"),
    ("Es9vMFrzaCERmJfrF4H2FYD4KConky11McCe8BenwNYB", "USDT"),
    ("J1toso1uCk3RLmjorhTtrVwY9HJ7X8V9yYac6Y7kGCPn", "JitoSOL"),
    ("mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So", "mSOL"),
];

fn well_known_mint_symbol(mint: &str) -> Option<&'static str> {
    WELL_KNOWN_MINT_SYMBOLS
        .iter()
        .find(|(address, _)| *address == mint)
        .map(|(_, symbol)| *symbol)
}

struct MintMetadata {
    account: String,
    mint: String,
    decimals: u8,
    symbol: Option<&'static str>,
}

/// Reads `token_account` and returns the mint it holds. `Ok(None)` when the
/// account is absent or is not an SPL token account; `Err` only on RPC failure —
/// letting callers separate "not a token account" from "couldn't reach RPC".
fn read_token_account_mint(
    rpc_url: &str,
    token_account: &Pubkey,
) -> Result<Option<Pubkey>, RelayError> {
    let Some((data, _slot)) = fetch_account_info(rpc_url, token_account)? else {
        return Ok(None);
    };
    Ok(match parse_spl_account(&data) {
        Some(SplAccount::TokenAccount { mint }) => Some(mint),
        _ => None,
    })
}

/// Reads `mint` and returns its decimals. `Ok(None)` when the account is absent
/// or is not an SPL mint; `Err` only on RPC failure.
fn read_mint_decimals(rpc_url: &str, mint: &Pubkey) -> Result<Option<u8>, RelayError> {
    let Some((data, _slot)) = fetch_account_info(rpc_url, mint)? else {
        return Ok(None);
    };
    Ok(match parse_spl_account(&data) {
        Some(SplAccount::Mint { decimals }) => Some(decimals),
        _ => None,
    })
}

/// Resolves `account` (either a mint itself, or a token account holding one) to
/// its `(mint, decimals)`. NotFound when the account is absent, is not an SPL
/// mint/token account, or a token account's mint can't be read as a mint. RPC
/// failures propagate as `Rpc` errors rather than NotFound. Shared by the
/// `/mints/{account}` endpoint and the transfer-asset post-pass.
fn resolve_mint_and_decimals(rpc_url: &str, account: &Pubkey) -> Result<(Pubkey, u8), RelayError> {
    let (data, _slot) = fetch_account_info(rpc_url, account)?.ok_or(RelayError::NotFound)?;
    match parse_spl_account(&data).ok_or(RelayError::NotFound)? {
        SplAccount::Mint { decimals } => Ok((*account, decimals)),
        SplAccount::TokenAccount { mint } => {
            let decimals = read_mint_decimals(rpc_url, &mint)?.ok_or(RelayError::NotFound)?;
            Ok((mint, decimals))
        }
    }
}

/// Reads the queried account; if it is a token account, reads its mint for decimals.
/// NotFound when the account does not exist or is not an SPL mint/token account.
fn resolve_mint_metadata(config: &RelayConfig, account: &str) -> Result<MintMetadata, RelayError> {
    let account_key: Pubkey = account
        .parse()
        .map_err(|_| RelayError::BadRequest("invalid account address".into()))?;
    let rpc_url = config.rpc_url()?;
    let (mint_key, decimals) = resolve_mint_and_decimals(&rpc_url, &account_key)?;
    let mint = mint_key.to_string();
    let symbol = well_known_mint_symbol(&mint);
    Ok(MintMetadata {
        account: account.to_string(),
        mint,
        decimals,
        symbol,
    })
}

/// Derives, fetches, and parses a program's on-chain Anchor IDL, returning a
/// content-hashed, cached snapshot. Successful resolves are served from cache
/// for `IDL_CACHE_TTL`; a program with no usable IDL is negative-cached for
/// `IDL_NEGATIVE_CACHE_TTL` so repeated misses don't keep hitting RPC. Other
/// errors (bad config, RPC failure) are never cached.
fn resolve_program_idl(config: &RelayConfig, program: &str) -> Result<FetchedIdl, RelayError> {
    let program_id: Pubkey = program
        .parse()
        .map_err(|_| RelayError::BadRequest("invalid program address".into()))?;

    let cache = IDL_CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    {
        let guard = cache.lock().unwrap_or_else(|e| e.into_inner());
        match guard.get(program) {
            Some((IdlCacheEntry::Found(cached), fetched_at))
                if fetched_at.elapsed() < IDL_CACHE_TTL =>
            {
                return Ok(cached.clone());
            }
            Some((IdlCacheEntry::Missing, fetched_at))
                if fetched_at.elapsed() < IDL_NEGATIVE_CACHE_TTL =>
            {
                return Err(RelayError::NotFound);
            }
            _ => {}
        }
    }

    let outcome = fetch_and_parse_program_idl(config, &program_id);

    let mut guard = cache.lock().unwrap_or_else(|e| e.into_inner());
    match &outcome {
        Ok(fetched) => insert_idl_cache_entry(
            &mut guard,
            program.to_string(),
            IdlCacheEntry::Found(fetched.clone()),
        ),
        Err(RelayError::NotFound) => {
            insert_idl_cache_entry(&mut guard, program.to_string(), IdlCacheEntry::Missing)
        }
        Err(_) => {}
    }
    drop(guard);

    outcome
}

/// Derives the IDL PDA, fetches the account over RPC, and parses/hashes its
/// content. Pulled out of `resolve_program_idl` so the cache lock is never
/// held across the RPC round-trip.
fn fetch_and_parse_program_idl(
    config: &RelayConfig,
    program_id: &Pubkey,
) -> Result<FetchedIdl, RelayError> {
    let idl_address = derive_idl_address(program_id).ok_or(RelayError::NotFound)?;
    let rpc_url = config.rpc_url()?;
    let (data, slot) = fetch_account_info(&rpc_url, &idl_address)?.ok_or(RelayError::NotFound)?;
    let parsed = parse_idl_account(&data)?;
    let idl_json: Box<RawValue> = serde_json::from_slice(&parsed.idl_json)
        .map_err(|error| RelayError::Rpc(format!("idl is not valid json: {error}")))?;
    // Hash the bytes RawValue actually captured (not the pre-parse buffer), so
    // the hash can never drift from what gets served in the response body.
    let hash = sha256_hex(idl_json.get().as_bytes());

    Ok(FetchedIdl {
        program: program_id.to_string(),
        idl_json,
        hash,
        slot,
        authority: parsed.authority.to_string(),
    })
}

static IDL_CACHE: OnceLock<Mutex<HashMap<String, (IdlCacheEntry, Instant)>>> = OnceLock::new();
const IDL_CACHE_TTL: Duration = Duration::from_secs(60 * 60);
const IDL_NEGATIVE_CACHE_TTL: Duration = Duration::from_secs(5 * 60);
/// Upper bound on distinct program addresses tracked in `IDL_CACHE`, so a
/// stream of distinct (or bogus) program addresses can't grow it unbounded.
const MAX_IDL_CACHE_ENTRIES: usize = 512;
/// `Cache-Control: max-age` advertised on 200s and 304s for `/idl` responses.
const IDL_CACHE_MAX_AGE_SECS: u64 = 60 * 60;

/// Inserts `entry` for `key`, first dropping any cache entries whose own TTL
/// has elapsed and then, if the map is still at capacity, evicting the oldest
/// remaining entry.
fn insert_idl_cache_entry(
    cache: &mut HashMap<String, (IdlCacheEntry, Instant)>,
    key: String,
    entry: IdlCacheEntry,
) {
    cache.retain(|_, (existing, fetched_at)| {
        let ttl = match existing {
            IdlCacheEntry::Found(_) => IDL_CACHE_TTL,
            IdlCacheEntry::Missing => IDL_NEGATIVE_CACHE_TTL,
        };
        fetched_at.elapsed() < ttl
    });

    if cache.len() >= MAX_IDL_CACHE_ENTRIES
        && let Some(oldest_key) = cache
            .iter()
            .min_by_key(|(_, (_, fetched_at))| *fetched_at)
            .map(|(key, _)| key.clone())
    {
        cache.remove(&oldest_key);
    }

    cache.insert(key, (entry, Instant::now()));
}

fn fetch_transaction_json(rpc_url: &str, signature: &str) -> Result<Option<Value>, RelayError> {
    let client = reqwest::blocking::Client::builder()
        .no_proxy()
        .timeout(RPC_TIMEOUT)
        .build()
        .map_err(|error| RelayError::Rpc(error.to_string()))?;
    let response = client
        .post(rpc_url)
        .json(&json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getTransaction",
            "params": [
                signature,
                {
                    "encoding": "jsonParsed",
                    "commitment": "confirmed",
                    "maxSupportedTransactionVersion": 0
                }
            ]
        }))
        .send()
        .map_err(|error| RelayError::Rpc(error.to_string()))?;
    let status = response.status();
    let body: Value = response
        .json()
        .map_err(|error| RelayError::Rpc(error.to_string()))?;

    if !status.is_success() {
        return Err(RelayError::Rpc(format!(
            "getTransaction returned HTTP {}",
            status.as_u16()
        )));
    }
    if let Some(error) = body.get("error") {
        return Err(RelayError::Rpc(error.to_string()));
    }

    Ok(body.get("result").filter(|value| !value.is_null()).cloned())
}

struct ProposalInspection {
    squad: String,
    detail: ProposalDetail,
    action: InspectionAction,
    cluster: Option<String>,
    simulation: SimulationSummary,
}

struct TransactionInspection {
    signature: String,
    cluster: Option<String>,
    status: TransactionStatusSummary,
    action: InspectionAction,
    logs: Vec<String>,
}

struct ActivityInspectionItem {
    item: types::ActivityItem,
    action: Option<InspectionAction>,
}

#[derive(Debug, Eq, PartialEq)]
struct TransactionStatusSummary {
    status: String,
    slot: Option<u64>,
    block_time: Option<i64>,
    error: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct InspectionAction {
    classification: String,
    summary: String,
    confidence: String,
    effects: Vec<InspectionEffect>,
    warnings: Vec<InspectionWarning>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct InspectionEffect {
    kind: String,
    summary: String,
    program: Option<String>,
    asset: Option<String>,
    amount: Option<String>,
    source: Option<String>,
    destination: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct InspectionWarning {
    severity: String,
    code: String,
    message: String,
}

struct SimulationSummary {
    status: SimulationStatus,
    message: String,
    error: Option<String>,
    logs: Vec<String>,
    fee_payer: Option<String>,
    recent_blockhash: Option<String>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum SimulationStatus {
    Succeeded,
    Failed,
    Blocked,
    NotApplicable,
}

impl SimulationStatus {
    fn as_str(self) -> &'static str {
        match self {
            Self::Succeeded => "succeeded",
            Self::Failed => "failed",
            Self::Blocked => "blocked",
            Self::NotApplicable => "not_applicable",
        }
    }
}

fn simulate_execution(
    rpc_url: &str,
    request: &ProposalInspectionRequest,
    multisig: &Multisig,
    companion: &ProposalCompanion,
    detail: &ProposalDetail,
) -> SimulationSummary {
    if detail.status != "Approved" {
        return SimulationSummary::blocked(format!(
            "Execution simulation requires an approved proposal. Current status: {}.",
            detail.status
        ));
    }

    if !matches!(companion, ProposalCompanion::Vault(_)) {
        return SimulationSummary::not_applicable(
            "Config proposal simulation is not supported yet.",
        );
    }

    let Some(member) = execute_member(multisig) else {
        return SimulationSummary::blocked("No execute-capable member was found for this Squad.");
    };

    let prepared = match transactions::build_execute_transaction(
        RpcClient::new(rpc_url.to_string()),
        request.squad,
        request.transaction_index,
        member,
    ) {
        Ok(prepared) => prepared,
        Err(error) => {
            return SimulationSummary::failed(
                "Unable to build the Squads execute transaction.",
                error.to_string(),
                Vec::new(),
                None,
                None,
            );
        }
    };

    let message_bytes = prepared.message_bytes;
    let fee_payer = prepared.fee_payer;
    let recent_blockhash = prepared.recent_blockhash;

    match transactions::simulate_unsigned_message(
        RpcClient::new(rpc_url.to_string()),
        message_bytes,
    ) {
        Ok(result) => {
            let status = if result.err.is_some() {
                SimulationStatus::Failed
            } else {
                SimulationStatus::Succeeded
            };
            SimulationSummary {
                status,
                message: if status == SimulationStatus::Succeeded {
                    "Execution simulation completed successfully.".into()
                } else {
                    "Execution simulation completed with an on-chain error.".into()
                },
                error: result.err,
                logs: result.logs,
                fee_payer: Some(fee_payer),
                recent_blockhash: Some(recent_blockhash),
            }
        }
        Err(error) => SimulationSummary::failed(
            "Unable to simulate the Squads execute transaction.",
            error.to_string(),
            Vec::new(),
            Some(fee_payer),
            Some(recent_blockhash),
        ),
    }
}

impl SimulationSummary {
    fn blocked(message: impl Into<String>) -> Self {
        Self {
            status: SimulationStatus::Blocked,
            message: message.into(),
            error: None,
            logs: Vec::new(),
            fee_payer: None,
            recent_blockhash: None,
        }
    }

    fn not_applicable(message: impl Into<String>) -> Self {
        Self {
            status: SimulationStatus::NotApplicable,
            message: message.into(),
            error: None,
            logs: Vec::new(),
            fee_payer: None,
            recent_blockhash: None,
        }
    }

    fn failed(
        message: impl Into<String>,
        error: String,
        logs: Vec<String>,
        fee_payer: Option<String>,
        recent_blockhash: Option<String>,
    ) -> Self {
        Self {
            status: SimulationStatus::Failed,
            message: message.into(),
            error: Some(error),
            logs,
            fee_payer,
            recent_blockhash,
        }
    }
}

fn execute_member(multisig: &Multisig) -> Option<Pubkey> {
    multisig
        .members
        .iter()
        .find(|member| member.permissions.has(Permission::Execute))
        .map(|member| member.key)
}

fn decoded_proposal_instructions(detail: &ProposalDetail) -> Vec<DecodedInstruction> {
    detail
        .instructions
        .iter()
        .map(decode_known_instruction)
        .collect()
}

fn decode_known_instruction(instruction: &DecodedInstruction) -> DecodedInstruction {
    let Some(data) = bytes_from_hex(&instruction.raw_data_hex) else {
        return instruction.clone();
    };

    if is_system_program(&instruction.program) {
        return decode_system_instruction(instruction, &data);
    }
    if is_token_program(&instruction.program) {
        return decode_token_instruction(instruction, &data);
    }
    if is_associated_token_account_program(&instruction.program) {
        return decode_associated_token_account_instruction(instruction, &data);
    }
    if is_memo_program(&instruction.program) {
        return decode_memo_instruction(instruction, &data);
    }
    if is_compute_budget_program(&instruction.program) {
        return decode_compute_budget_instruction(instruction, &data);
    }
    if is_stake_program(&instruction.program) {
        return decode_stake_instruction(instruction, &data);
    }
    if is_address_lookup_table_program(&instruction.program) {
        return decode_address_lookup_table_instruction(instruction, &data);
    }
    if is_upgradeable_loader_program(&instruction.program) {
        return decode_upgradeable_loader_instruction(instruction, &data);
    }

    instruction.clone()
}

fn decode_system_instruction(instruction: &DecodedInstruction, data: &[u8]) -> DecodedInstruction {
    if let Some(decoded) = decode_system_admin_instruction(instruction, data) {
        return decoded;
    }

    match read_u32_le(data, 0) {
        Some(0) => {
            let Some(lamports) = read_u64_le(data, 4) else {
                return instruction.clone();
            };
            let Some(space) = read_u64_le(data, 12) else {
                return instruction.clone();
            };
            let Some(owner) = pubkey_from_data(data, 20) else {
                return instruction.clone();
            };
            if is_nonce_account_creation(space, &owner) {
                return DecodedInstruction {
                    program: "System Program".into(),
                    kind: "create_nonce_account".into(),
                    summary: format!("Create nonce account with {}", format_lamports(lamports)),
                    accounts: instruction.accounts.clone(),
                    raw_data_hex: instruction.raw_data_hex.clone(),
                    config_action: None,
                };
            }
            DecodedInstruction {
                program: "System Program".into(),
                kind: "create_account".into(),
                summary: format!(
                    "Create account with {}, {space} bytes",
                    format_lamports(lamports)
                ),
                accounts: instruction.accounts.clone(),
                raw_data_hex: instruction.raw_data_hex.clone(),
                config_action: None,
            }
        }
        Some(2) => {
            let Some(lamports) = read_u64_le(data, 4) else {
                return instruction.clone();
            };
            DecodedInstruction {
                program: "System Program".into(),
                kind: "transfer".into(),
                summary: format!("Transfer {}", format_lamports(lamports)),
                accounts: instruction.accounts.clone(),
                raw_data_hex: instruction.raw_data_hex.clone(),
                config_action: None,
            }
        }
        _ => instruction.clone(),
    }
}

fn decode_system_admin_instruction(
    instruction: &DecodedInstruction,
    data: &[u8],
) -> Option<DecodedInstruction> {
    let system_instruction = bincode::deserialize::<SystemInstruction>(data).ok()?;
    let (kind, summary) = match system_instruction {
        SystemInstruction::CreateAccount {
            lamports,
            space,
            owner,
        } if is_nonce_account_creation(space, &owner) => (
            "create_nonce_account",
            format!("Create nonce account with {}", format_lamports(lamports)),
        ),
        SystemInstruction::CreateAccountWithSeed {
            lamports,
            space,
            owner,
            ..
        } if is_nonce_account_creation(space, &owner) => (
            "create_nonce_account_with_seed",
            format!(
                "Create seeded nonce account with {}",
                format_lamports(lamports)
            ),
        ),
        SystemInstruction::CreateAccountWithSeed {
            lamports,
            space,
            owner,
            ..
        } => (
            "create_account_with_seed",
            format!(
                "Create seeded account with {}, {space} bytes, owner {owner}",
                format_lamports(lamports)
            ),
        ),
        SystemInstruction::Assign { owner } => {
            ("assign", format!("Assign account owner to {owner}"))
        }
        SystemInstruction::AdvanceNonceAccount => ("advance_nonce_account", "Advance nonce".into()),
        SystemInstruction::WithdrawNonceAccount(lamports) => (
            "withdraw_nonce_account",
            format!("Withdraw {} from nonce account", format_lamports(lamports)),
        ),
        SystemInstruction::AssignWithSeed { owner, .. } => (
            "assign_with_seed",
            format!("Assign seeded account owner to {owner}"),
        ),
        SystemInstruction::Allocate { space } => (
            "allocate",
            format!("Allocate {space} bytes for system account"),
        ),
        SystemInstruction::AllocateWithSeed { space, owner, .. } => (
            "allocate_with_seed",
            format!("Allocate {space} bytes for seeded account owned by {owner}"),
        ),
        SystemInstruction::TransferWithSeed { lamports, .. } => (
            "transfer_with_seed",
            format!("Transfer {} from seeded account", format_lamports(lamports)),
        ),
        SystemInstruction::InitializeNonceAccount(authority) => (
            "initialize_nonce_account",
            format!("Initialize nonce authority {authority}"),
        ),
        SystemInstruction::AuthorizeNonceAccount(authority) => (
            "authorize_nonce_account",
            format!("Authorize nonce authority {authority}"),
        ),
        SystemInstruction::UpgradeNonceAccount => {
            ("upgrade_nonce_account", "Upgrade nonce account".into())
        }
        _ => return None,
    };

    Some(DecodedInstruction {
        program: "System Program".into(),
        kind: kind.into(),
        summary,
        accounts: instruction.accounts.clone(),
        raw_data_hex: instruction.raw_data_hex.clone(),
        config_action: None,
    })
}

fn decode_token_instruction(instruction: &DecodedInstruction, data: &[u8]) -> DecodedInstruction {
    let (kind, summary) = match data.first().copied() {
        Some(3) => {
            let Some(amount) = read_u64_le(data, 1) else {
                return instruction.clone();
            };
            ("transfer", format!("Transfer {amount} base units"))
        }
        Some(4) => {
            let Some(amount) = read_u64_le(data, 1) else {
                return instruction.clone();
            };
            ("approve", format!("Approve {amount} base units"))
        }
        Some(5) => ("revoke", "Revoke token delegate".into()),
        Some(6) => {
            let authority_type = data
                .get(1)
                .map(|value| token_authority_type_label(*value))
                .unwrap_or("authority");
            if read_u32_le(data, 2).is_none() {
                return instruction.clone();
            }
            let summary = match coption_pubkey_from_token_data(data, 2) {
                Some(authority) => format!("Set token {authority_type} to {authority}"),
                None => format!("Clear token {authority_type}"),
            };
            ("set_authority", summary)
        }
        Some(7) => {
            let Some(amount) = read_u64_le(data, 1) else {
                return instruction.clone();
            };
            ("mint_to", format!("Mint {amount} base units"))
        }
        Some(8) => {
            let Some(amount) = read_u64_le(data, 1) else {
                return instruction.clone();
            };
            ("burn", format!("Burn {amount} base units"))
        }
        Some(9) => ("close_account", "Close token account".into()),
        Some(10) => ("freeze_account", "Freeze token account".into()),
        Some(11) => ("thaw_account", "Thaw token account".into()),
        Some(12) if data.len() >= 10 => {
            let Some(amount) = read_u64_le(data, 1) else {
                return instruction.clone();
            };
            let decimals = data[9];
            (
                "transfer_checked",
                format!(
                    "Transfer {} tokens",
                    format_decimal_amount(amount, decimals)
                ),
            )
        }
        Some(13) if data.len() >= 10 => {
            let Some(amount) = read_u64_le(data, 1) else {
                return instruction.clone();
            };
            let decimals = data[9];
            (
                "approve_checked",
                format!("Approve {} tokens", format_decimal_amount(amount, decimals)),
            )
        }
        Some(14) if data.len() >= 10 => {
            let Some(amount) = read_u64_le(data, 1) else {
                return instruction.clone();
            };
            let decimals = data[9];
            (
                "mint_to_checked",
                format!("Mint {} tokens", format_decimal_amount(amount, decimals)),
            )
        }
        Some(15) if data.len() >= 10 => {
            let Some(amount) = read_u64_le(data, 1) else {
                return instruction.clone();
            };
            let decimals = data[9];
            (
                "burn_checked",
                format!("Burn {} tokens", format_decimal_amount(amount, decimals)),
            )
        }
        _ => return instruction.clone(),
    };

    DecodedInstruction {
        program: token_program_label(&instruction.program).into(),
        kind: kind.into(),
        summary,
        accounts: instruction.accounts.clone(),
        raw_data_hex: instruction.raw_data_hex.clone(),
        config_action: None,
    }
}

fn decode_associated_token_account_instruction(
    instruction: &DecodedInstruction,
    data: &[u8],
) -> DecodedInstruction {
    let (kind, summary) = match data.first().copied() {
        None | Some(0) => ("create", "Create associated token account"),
        Some(1) => (
            "create_idempotent",
            "Create associated token account if needed",
        ),
        Some(2) => ("recover_nested", "Recover nested associated token account"),
        _ => return instruction.clone(),
    };

    DecodedInstruction {
        program: "Associated Token Account Program".into(),
        kind: kind.into(),
        summary: summary.into(),
        accounts: instruction.accounts.clone(),
        raw_data_hex: instruction.raw_data_hex.clone(),
        config_action: None,
    }
}

fn decode_memo_instruction(instruction: &DecodedInstruction, data: &[u8]) -> DecodedInstruction {
    let memo = String::from_utf8_lossy(data).trim().to_string();
    let summary = if memo.is_empty() {
        "Memo".into()
    } else {
        format!("Memo: {}", short_text(&memo, 80))
    };

    DecodedInstruction {
        program: "Memo Program".into(),
        kind: "memo".into(),
        summary,
        accounts: instruction.accounts.clone(),
        raw_data_hex: instruction.raw_data_hex.clone(),
        config_action: None,
    }
}

fn decode_compute_budget_instruction(
    instruction: &DecodedInstruction,
    data: &[u8],
) -> DecodedInstruction {
    let (kind, summary) = match data.first().copied() {
        Some(0) => {
            let Some(units) = read_u32_le(data, 1) else {
                return instruction.clone();
            };
            let Some(additional_fee) = read_u32_le(data, 5) else {
                return instruction.clone();
            };
            (
                "request_units_deprecated",
                format!("Request {units} compute units with {additional_fee} additional fee"),
            )
        }
        Some(1) => {
            let Some(bytes) = read_u32_le(data, 1) else {
                return instruction.clone();
            };
            (
                "request_heap_frame",
                format!("Request {bytes} byte heap frame"),
            )
        }
        Some(2) => {
            let Some(units) = read_u32_le(data, 1) else {
                return instruction.clone();
            };
            (
                "set_compute_unit_limit",
                format!("Set compute unit limit to {units}"),
            )
        }
        Some(3) => {
            let Some(micro_lamports) = read_u64_le(data, 1) else {
                return instruction.clone();
            };
            (
                "set_compute_unit_price",
                format!("Set compute unit price to {micro_lamports} micro-lamports"),
            )
        }
        _ => return instruction.clone(),
    };

    DecodedInstruction {
        program: "Compute Budget Program".into(),
        kind: kind.into(),
        summary,
        accounts: instruction.accounts.clone(),
        raw_data_hex: instruction.raw_data_hex.clone(),
        config_action: None,
    }
}

fn decode_stake_instruction(instruction: &DecodedInstruction, data: &[u8]) -> DecodedInstruction {
    let Ok(stake_instruction) = bincode::deserialize::<StakeInstruction>(data) else {
        return instruction.clone();
    };
    let (kind, summary) = stake_instruction_label(&stake_instruction, &instruction.accounts);

    DecodedInstruction {
        program: "Stake Program".into(),
        kind: kind.into(),
        summary,
        accounts: instruction.accounts.clone(),
        raw_data_hex: instruction.raw_data_hex.clone(),
        config_action: None,
    }
}

fn decode_address_lookup_table_instruction(
    instruction: &DecodedInstruction,
    data: &[u8],
) -> DecodedInstruction {
    let Ok(lookup_table_instruction) = bincode::deserialize::<AddressLookupTableInstruction>(data)
    else {
        return instruction.clone();
    };
    let (kind, summary) =
        address_lookup_table_label(&lookup_table_instruction, &instruction.accounts);

    DecodedInstruction {
        program: "Address Lookup Table Program".into(),
        kind: kind.into(),
        summary,
        accounts: instruction.accounts.clone(),
        raw_data_hex: instruction.raw_data_hex.clone(),
        config_action: None,
    }
}

fn decode_upgradeable_loader_instruction(
    instruction: &DecodedInstruction,
    data: &[u8],
) -> DecodedInstruction {
    let Ok(loader_instruction) = bincode::deserialize::<UpgradeableLoaderInstruction>(data) else {
        return instruction.clone();
    };
    let (kind, summary) = upgradeable_loader_label(&loader_instruction, &instruction.accounts);

    DecodedInstruction {
        program: "BPF Upgradeable Loader".into(),
        kind: kind.into(),
        summary,
        accounts: instruction.accounts.clone(),
        raw_data_hex: instruction.raw_data_hex.clone(),
        config_action: None,
    }
}

fn action_from_decoded_instructions(instructions: &[DecodedInstruction]) -> InspectionAction {
    let effects = instructions
        .iter()
        .filter_map(effect_from_instruction)
        .collect::<Vec<_>>();
    let unknown_count = instructions
        .iter()
        .filter(|instruction| effect_from_instruction(instruction).is_none())
        .filter(|instruction| !is_known_non_effect_instruction(instruction))
        .count();
    InspectionAction::from_effects(effects, unknown_count)
}

fn effect_from_instruction(instruction: &DecodedInstruction) -> Option<InspectionEffect> {
    let data = bytes_from_hex(&instruction.raw_data_hex)?;

    if is_system_program(&instruction.program) {
        if instruction.kind == "transfer" {
            let lamports = read_u64_le(&data, 4)?;
            return Some(InspectionEffect {
                kind: "sol_transfer".into(),
                summary: format!("Transfer {}", format_lamports(lamports)),
                program: Some("System Program".into()),
                asset: Some("SOL".into()),
                amount: Some(format_lamports(lamports)),
                source: instruction.accounts.first().cloned(),
                destination: instruction.accounts.get(1).cloned(),
            });
        }
        return system_admin_effect_from_instruction(instruction, &data);
    }

    if is_token_program(&instruction.program) {
        return token_effect_from_instruction(instruction, &data);
    }

    if is_associated_token_account_program(&instruction.program) {
        return Some(InspectionEffect {
            kind: "associated_token_account_create".into(),
            summary: instruction.summary.clone(),
            program: Some("Associated Token Account Program".into()),
            asset: instruction.accounts.get(3).cloned(),
            amount: None,
            source: instruction.accounts.first().cloned(),
            destination: instruction.accounts.get(1).cloned(),
        });
    }

    if is_squads_program(&instruction.program) {
        return squads_effect_from_instruction(instruction);
    }

    if is_stake_program(&instruction.program) {
        return stake_effect_from_raw_instruction(&data, &instruction.accounts);
    }

    if is_address_lookup_table_program(&instruction.program) {
        return address_lookup_table_effect_from_raw_instruction(&data, &instruction.accounts);
    }

    if is_upgradeable_loader_program(&instruction.program) {
        return upgradeable_loader_effect_from_raw_instruction(&data, &instruction.accounts);
    }

    None
}

fn system_admin_effect_from_instruction(
    instruction: &DecodedInstruction,
    data: &[u8],
) -> Option<InspectionEffect> {
    let system_instruction = bincode::deserialize::<SystemInstruction>(data).ok()?;
    match system_instruction {
        SystemInstruction::CreateAccount {
            lamports,
            space,
            owner,
        } if is_nonce_account_creation(space, &owner) => Some(InspectionEffect {
            kind: "nonce_account_create".into(),
            summary: format!("Create nonce account with {}", format_lamports(lamports)),
            program: Some("System Program".into()),
            asset: Some("SOL".into()),
            amount: Some(format_lamports(lamports)),
            source: instruction.accounts.first().cloned(),
            destination: instruction.accounts.get(1).cloned(),
        }),
        SystemInstruction::CreateAccountWithSeed {
            lamports,
            space,
            owner,
            ..
        } if is_nonce_account_creation(space, &owner) => Some(InspectionEffect {
            kind: "nonce_account_create".into(),
            summary: format!(
                "Create seeded nonce account with {}",
                format_lamports(lamports)
            ),
            program: Some("System Program".into()),
            asset: Some("SOL".into()),
            amount: Some(format_lamports(lamports)),
            source: instruction.accounts.first().cloned(),
            destination: instruction.accounts.get(1).cloned(),
        }),
        SystemInstruction::CreateAccountWithSeed {
            lamports,
            space,
            owner,
            ..
        } => Some(InspectionEffect {
            kind: "system_account_create".into(),
            summary: format!(
                "Create seeded account with {}, {space} bytes, owner {owner}",
                format_lamports(lamports)
            ),
            program: Some("System Program".into()),
            asset: Some(owner.to_string()),
            amount: Some(format_lamports(lamports)),
            source: instruction.accounts.first().cloned(),
            destination: instruction.accounts.get(1).cloned(),
        }),
        SystemInstruction::Assign { owner } => Some(InspectionEffect {
            kind: "system_account_owner_change".into(),
            summary: format!("Assign account owner to {owner}"),
            program: Some("System Program".into()),
            asset: None,
            amount: None,
            source: instruction.accounts.first().cloned(),
            destination: Some(owner.to_string()),
        }),
        SystemInstruction::AdvanceNonceAccount => Some(InspectionEffect {
            kind: "nonce_advance".into(),
            summary: "Advance nonce".into(),
            program: Some("System Program".into()),
            asset: None,
            amount: None,
            source: instruction.accounts.first().cloned(),
            destination: instruction.accounts.get(2).cloned(),
        }),
        SystemInstruction::WithdrawNonceAccount(lamports) => Some(InspectionEffect {
            kind: "nonce_withdraw".into(),
            summary: format!("Withdraw {} from nonce account", format_lamports(lamports)),
            program: Some("System Program".into()),
            asset: Some("SOL".into()),
            amount: Some(format_lamports(lamports)),
            source: instruction.accounts.first().cloned(),
            destination: instruction.accounts.get(1).cloned(),
        }),
        SystemInstruction::AssignWithSeed { owner, .. } => Some(InspectionEffect {
            kind: "system_account_owner_change".into(),
            summary: format!("Assign seeded account owner to {owner}"),
            program: Some("System Program".into()),
            asset: None,
            amount: None,
            source: instruction.accounts.first().cloned(),
            destination: Some(owner.to_string()),
        }),
        SystemInstruction::Allocate { space } => Some(InspectionEffect {
            kind: "system_account_allocate".into(),
            summary: format!("Allocate {space} bytes for system account"),
            program: Some("System Program".into()),
            asset: None,
            amount: None,
            source: instruction.accounts.first().cloned(),
            destination: instruction.accounts.first().cloned(),
        }),
        SystemInstruction::AllocateWithSeed { space, owner, .. } => Some(InspectionEffect {
            kind: "system_account_allocate".into(),
            summary: format!("Allocate {space} bytes for seeded account owned by {owner}"),
            program: Some("System Program".into()),
            asset: Some(owner.to_string()),
            amount: None,
            source: instruction.accounts.first().cloned(),
            destination: instruction.accounts.first().cloned(),
        }),
        SystemInstruction::TransferWithSeed { lamports, .. } => Some(InspectionEffect {
            kind: "sol_transfer".into(),
            summary: format!("Transfer {} from seeded account", format_lamports(lamports)),
            program: Some("System Program".into()),
            asset: Some("SOL".into()),
            amount: Some(format_lamports(lamports)),
            source: instruction.accounts.first().cloned(),
            destination: instruction.accounts.get(2).cloned(),
        }),
        SystemInstruction::InitializeNonceAccount(authority) => Some(InspectionEffect {
            kind: "nonce_authority_change".into(),
            summary: format!("Initialize nonce authority {authority}"),
            program: Some("System Program".into()),
            asset: None,
            amount: None,
            source: instruction.accounts.first().cloned(),
            destination: Some(authority.to_string()),
        }),
        SystemInstruction::AuthorizeNonceAccount(authority) => Some(InspectionEffect {
            kind: "nonce_authority_change".into(),
            summary: format!("Authorize nonce authority {authority}"),
            program: Some("System Program".into()),
            asset: None,
            amount: None,
            source: instruction.accounts.get(1).cloned(),
            destination: Some(authority.to_string()),
        }),
        SystemInstruction::UpgradeNonceAccount => Some(InspectionEffect {
            kind: "nonce_upgrade".into(),
            summary: "Upgrade nonce account".into(),
            program: Some("System Program".into()),
            asset: None,
            amount: None,
            source: instruction.accounts.first().cloned(),
            destination: instruction.accounts.first().cloned(),
        }),
        _ => None,
    }
}

fn token_effect_from_instruction(
    instruction: &DecodedInstruction,
    data: &[u8],
) -> Option<InspectionEffect> {
    if instruction.kind == "transfer_checked" {
        let amount = read_u64_le(data, 1)?;
        let decimals = *data.get(9)?;
        let display_amount = format_decimal_amount(amount, decimals);
        return Some(InspectionEffect {
            kind: "token_transfer".into(),
            summary: format!("Transfer {display_amount} tokens"),
            program: Some(token_program_label(&instruction.program).into()),
            asset: instruction.accounts.get(1).cloned(),
            amount: Some(display_amount),
            source: instruction.accounts.first().cloned(),
            destination: instruction.accounts.get(2).cloned(),
        });
    }

    if instruction.kind == "transfer" {
        let amount = read_u64_le(data, 1)?;
        return Some(InspectionEffect {
            kind: "token_transfer".into(),
            summary: format!("Transfer {amount} base units"),
            program: Some(token_program_label(&instruction.program).into()),
            asset: None,
            amount: Some(format!("{amount} base units")),
            source: instruction.accounts.first().cloned(),
            destination: instruction.accounts.get(1).cloned(),
        });
    }

    match data.first().copied()? {
        4 => token_delegate_effect(
            "token_approve",
            format!("Approve {} base units", read_u64_le(data, 1)?),
            instruction,
            Some(format!("{} base units", read_u64_le(data, 1)?)),
            0,
            1,
        ),
        5 => token_account_effect("token_revoke", "Revoke token delegate", instruction, 0),
        6 => token_set_authority_effect(instruction, data),
        7 => token_mint_burn_effect(
            "token_mint",
            format!("Mint {} base units", read_u64_le(data, 1)?),
            instruction,
            Some(format!("{} base units", read_u64_le(data, 1)?)),
            0,
            1,
            2,
        ),
        8 => token_mint_burn_effect(
            "token_burn",
            format!("Burn {} base units", read_u64_le(data, 1)?),
            instruction,
            Some(format!("{} base units", read_u64_le(data, 1)?)),
            1,
            0,
            2,
        ),
        9 => Some(InspectionEffect {
            kind: "token_account_close".into(),
            summary: "Close token account".into(),
            program: Some(token_program_label(&instruction.program).into()),
            asset: None,
            amount: None,
            source: instruction.accounts.first().cloned(),
            destination: instruction.accounts.get(1).cloned(),
        }),
        10 => token_account_effect(
            "token_account_freeze",
            "Freeze token account",
            instruction,
            0,
        ),
        11 => token_account_effect("token_account_thaw", "Thaw token account", instruction, 0),
        13 => {
            let amount = read_u64_le(data, 1)?;
            let decimals = *data.get(9)?;
            let display_amount = format_decimal_amount(amount, decimals);
            token_delegate_effect(
                "token_approve",
                format!("Approve {display_amount} tokens"),
                instruction,
                Some(display_amount),
                0,
                2,
            )
        }
        14 => {
            let amount = read_u64_le(data, 1)?;
            let decimals = *data.get(9)?;
            let display_amount = format_decimal_amount(amount, decimals);
            token_mint_burn_effect(
                "token_mint",
                format!("Mint {display_amount} tokens"),
                instruction,
                Some(display_amount),
                0,
                1,
                2,
            )
        }
        15 => {
            let amount = read_u64_le(data, 1)?;
            let decimals = *data.get(9)?;
            let display_amount = format_decimal_amount(amount, decimals);
            token_mint_burn_effect(
                "token_burn",
                format!("Burn {display_amount} tokens"),
                instruction,
                Some(display_amount),
                1,
                0,
                2,
            )
        }
        _ => None,
    }
}

fn token_delegate_effect(
    kind: &str,
    summary: String,
    instruction: &DecodedInstruction,
    amount: Option<String>,
    source_index: usize,
    delegate_index: usize,
) -> Option<InspectionEffect> {
    Some(InspectionEffect {
        kind: kind.into(),
        summary,
        program: Some(token_program_label(&instruction.program).into()),
        asset: token_mint_for_instruction(instruction),
        amount,
        source: instruction.accounts.get(source_index).cloned(),
        destination: instruction.accounts.get(delegate_index).cloned(),
    })
}

fn token_mint_burn_effect(
    kind: &str,
    summary: String,
    instruction: &DecodedInstruction,
    amount: Option<String>,
    mint_index: usize,
    account_index: usize,
    authority_index: usize,
) -> Option<InspectionEffect> {
    Some(InspectionEffect {
        kind: kind.into(),
        summary,
        program: Some(token_program_label(&instruction.program).into()),
        asset: instruction.accounts.get(mint_index).cloned(),
        amount,
        source: instruction.accounts.get(authority_index).cloned(),
        destination: instruction.accounts.get(account_index).cloned(),
    })
}

fn token_account_effect(
    kind: &str,
    summary: &str,
    instruction: &DecodedInstruction,
    account_index: usize,
) -> Option<InspectionEffect> {
    Some(InspectionEffect {
        kind: kind.into(),
        summary: summary.into(),
        program: Some(token_program_label(&instruction.program).into()),
        asset: token_mint_for_instruction(instruction),
        amount: None,
        source: instruction.accounts.get(account_index).cloned(),
        destination: None,
    })
}

fn token_set_authority_effect(
    instruction: &DecodedInstruction,
    data: &[u8],
) -> Option<InspectionEffect> {
    let authority_type = data
        .get(1)
        .map(|value| token_authority_type_label(*value))
        .unwrap_or("authority");
    let new_authority = coption_pubkey_from_token_data(data, 2);
    let summary = match new_authority.as_deref() {
        Some(authority) => format!("Set token {authority_type} to {authority}"),
        None => format!("Clear token {authority_type}"),
    };

    Some(InspectionEffect {
        kind: "token_authority_change".into(),
        summary,
        program: Some(token_program_label(&instruction.program).into()),
        asset: token_mint_for_instruction(instruction),
        amount: None,
        source: instruction.accounts.get(1).cloned(),
        destination: new_authority.or_else(|| instruction.accounts.first().cloned()),
    })
}

fn token_mint_for_instruction(instruction: &DecodedInstruction) -> Option<String> {
    if matches!(
        instruction.kind.as_str(),
        "transfer_checked" | "approve_checked" | "mint_to_checked" | "burn_checked"
    ) {
        instruction.accounts.get(1).cloned()
    } else {
        None
    }
}

fn stake_instruction_label(
    instruction: &StakeInstruction,
    accounts: &[String],
) -> (&'static str, String) {
    match instruction {
        StakeInstruction::Initialize(authorized, _) => (
            "stake_initialize",
            stake_initialize_summary(authorized, accounts),
        ),
        StakeInstruction::Authorize(new_authority, authority_type) => (
            "stake_authority_change",
            format!(
                "Set stake {} authority to {new_authority}",
                stake_authority_label(authority_type)
            ),
        ),
        StakeInstruction::DelegateStake => (
            "stake_delegate",
            format!(
                "Delegate stake{}",
                accounts
                    .get(1)
                    .map(|vote| format!(" to {vote}"))
                    .unwrap_or_default()
            ),
        ),
        StakeInstruction::Split(lamports) => (
            "stake_split",
            format!("Split {} stake", format_lamports(*lamports)),
        ),
        StakeInstruction::Withdraw(lamports) => (
            "stake_withdraw",
            format!("Withdraw {} from stake", format_lamports(*lamports)),
        ),
        StakeInstruction::Deactivate => ("stake_deactivate", "Deactivate stake".into()),
        StakeInstruction::SetLockup(_) => ("stake_lockup_change", "Set stake lockup".into()),
        StakeInstruction::Merge => ("stake_merge", "Merge stake accounts".into()),
        StakeInstruction::AuthorizeWithSeed(args) => (
            "stake_authority_change",
            format!(
                "Set stake {} authority to {}",
                stake_authority_label(&args.stake_authorize),
                args.new_authorized_pubkey
            ),
        ),
        StakeInstruction::InitializeChecked => (
            "stake_initialize",
            format!(
                "Initialize stake account with staker {} and withdrawer {}",
                accounts
                    .get(2)
                    .map(String::as_str)
                    .unwrap_or("stake authority"),
                accounts
                    .get(3)
                    .map(String::as_str)
                    .unwrap_or("withdraw authority")
            ),
        ),
        StakeInstruction::AuthorizeChecked(authority_type) => (
            "stake_authority_change",
            format!(
                "Set stake {} authority to {}",
                stake_authority_label(authority_type),
                accounts
                    .get(3)
                    .map(String::as_str)
                    .unwrap_or("new authority")
            ),
        ),
        StakeInstruction::AuthorizeCheckedWithSeed(args) => (
            "stake_authority_change",
            format!(
                "Set stake {} authority to {}",
                stake_authority_label(&args.stake_authorize),
                accounts
                    .get(3)
                    .map(String::as_str)
                    .unwrap_or("new authority")
            ),
        ),
        StakeInstruction::SetLockupChecked(_) => ("stake_lockup_change", "Set stake lockup".into()),
        StakeInstruction::GetMinimumDelegation => (
            "stake_minimum_delegation",
            "Get minimum stake delegation".into(),
        ),
        StakeInstruction::DeactivateDelinquent => (
            "stake_deactivate",
            format!(
                "Deactivate delinquent stake{}",
                accounts
                    .get(1)
                    .map(|vote| format!(" for vote account {vote}"))
                    .unwrap_or_default()
            ),
        ),
        StakeInstruction::Redelegate => (
            "stake_redelegate",
            format!(
                "Redelegate stake{}",
                accounts
                    .get(2)
                    .map(|vote| format!(" to {vote}"))
                    .unwrap_or_default()
            ),
        ),
    }
}

fn stake_initialize_summary(authorized: &Authorized, accounts: &[String]) -> String {
    format!(
        "Initialize stake account{} with staker {} and withdrawer {}",
        accounts
            .first()
            .map(|stake| format!(" {stake}"))
            .unwrap_or_default(),
        authorized.staker,
        authorized.withdrawer
    )
}

fn stake_authority_label(authority_type: &StakeAuthorize) -> &'static str {
    match authority_type {
        StakeAuthorize::Staker => "staker",
        StakeAuthorize::Withdrawer => "withdraw",
    }
}

fn stake_effect_from_raw_instruction(data: &[u8], accounts: &[String]) -> Option<InspectionEffect> {
    let instruction = bincode::deserialize::<StakeInstruction>(data).ok()?;
    let (kind, summary) = stake_instruction_label(&instruction, accounts);
    let (asset, amount, source, destination) = stake_effect_accounts(&instruction, accounts);

    Some(InspectionEffect {
        kind: kind.into(),
        summary,
        program: Some("Stake Program".into()),
        asset,
        amount,
        source,
        destination,
    })
}

fn stake_effect_accounts(
    instruction: &StakeInstruction,
    accounts: &[String],
) -> (
    Option<String>,
    Option<String>,
    Option<String>,
    Option<String>,
) {
    match instruction {
        StakeInstruction::Initialize(..) | StakeInstruction::InitializeChecked => (
            accounts.first().cloned(),
            None,
            accounts.get(2).cloned(),
            accounts.first().cloned(),
        ),
        StakeInstruction::Authorize(new_authority, _) => (
            accounts.first().cloned(),
            None,
            accounts.get(2).cloned(),
            Some(new_authority.to_string()),
        ),
        StakeInstruction::AuthorizeWithSeed(args) => (
            accounts.first().cloned(),
            None,
            accounts.get(1).cloned(),
            Some(args.new_authorized_pubkey.to_string()),
        ),
        StakeInstruction::AuthorizeChecked(_) | StakeInstruction::AuthorizeCheckedWithSeed(_) => (
            accounts.first().cloned(),
            None,
            accounts
                .get(2)
                .cloned()
                .or_else(|| accounts.get(1).cloned()),
            accounts.get(3).cloned(),
        ),
        StakeInstruction::DelegateStake => (
            accounts.first().cloned(),
            None,
            accounts.get(5).cloned(),
            accounts.get(1).cloned(),
        ),
        StakeInstruction::Split(lamports) => (
            Some("SOL".into()),
            Some(format_lamports(*lamports)),
            accounts.first().cloned(),
            accounts.get(1).cloned(),
        ),
        StakeInstruction::Withdraw(lamports) => (
            Some("SOL".into()),
            Some(format_lamports(*lamports)),
            accounts.first().cloned(),
            accounts.get(1).cloned(),
        ),
        StakeInstruction::Deactivate | StakeInstruction::DeactivateDelinquent => (
            accounts.first().cloned(),
            None,
            accounts.get(2).cloned(),
            accounts.first().cloned(),
        ),
        StakeInstruction::SetLockup(_) | StakeInstruction::SetLockupChecked(_) => (
            accounts.first().cloned(),
            None,
            accounts.get(1).cloned(),
            accounts.first().cloned(),
        ),
        StakeInstruction::Merge => (
            accounts.first().cloned(),
            None,
            accounts.get(1).cloned(),
            accounts.first().cloned(),
        ),
        StakeInstruction::GetMinimumDelegation => (None, None, None, None),
        StakeInstruction::Redelegate => (
            accounts.first().cloned(),
            None,
            accounts.first().cloned(),
            accounts
                .get(1)
                .cloned()
                .or_else(|| accounts.get(2).cloned()),
        ),
    }
}

fn address_lookup_table_label(
    instruction: &AddressLookupTableInstruction,
    _accounts: &[String],
) -> (&'static str, String) {
    match instruction {
        AddressLookupTableInstruction::CreateLookupTable { .. } => {
            ("lookup_table_create", "Create address lookup table".into())
        }
        AddressLookupTableInstruction::FreezeLookupTable => {
            ("lookup_table_freeze", "Freeze address lookup table".into())
        }
        AddressLookupTableInstruction::ExtendLookupTable { new_addresses } => (
            "lookup_table_extend",
            format!(
                "Extend address lookup table with {}",
                address_count_label(new_addresses.len())
            ),
        ),
        AddressLookupTableInstruction::DeactivateLookupTable => (
            "lookup_table_deactivate",
            "Deactivate address lookup table".into(),
        ),
        AddressLookupTableInstruction::CloseLookupTable => {
            ("lookup_table_close", "Close address lookup table".into())
        }
    }
}

fn address_lookup_table_effect_from_raw_instruction(
    data: &[u8],
    accounts: &[String],
) -> Option<InspectionEffect> {
    let instruction = bincode::deserialize::<AddressLookupTableInstruction>(data).ok()?;
    let (kind, summary) = address_lookup_table_label(&instruction, accounts);
    let (asset, amount, source, destination) =
        address_lookup_table_effect_accounts(&instruction, accounts);

    Some(InspectionEffect {
        kind: kind.into(),
        summary,
        program: Some("Address Lookup Table Program".into()),
        asset,
        amount,
        source,
        destination,
    })
}

fn address_lookup_table_effect_accounts(
    instruction: &AddressLookupTableInstruction,
    accounts: &[String],
) -> (
    Option<String>,
    Option<String>,
    Option<String>,
    Option<String>,
) {
    match instruction {
        AddressLookupTableInstruction::CreateLookupTable { .. } => (
            accounts.first().cloned(),
            None,
            accounts.get(2).cloned(),
            accounts.first().cloned(),
        ),
        AddressLookupTableInstruction::FreezeLookupTable
        | AddressLookupTableInstruction::DeactivateLookupTable => (
            accounts.first().cloned(),
            None,
            accounts.get(1).cloned(),
            accounts.first().cloned(),
        ),
        AddressLookupTableInstruction::ExtendLookupTable { new_addresses } => (
            accounts.first().cloned(),
            Some(address_count_label(new_addresses.len())),
            accounts.get(1).cloned(),
            accounts.first().cloned(),
        ),
        AddressLookupTableInstruction::CloseLookupTable => (
            accounts.first().cloned(),
            None,
            accounts.first().cloned(),
            accounts.get(2).cloned(),
        ),
    }
}

fn address_count_label(count: usize) -> String {
    if count == 1 {
        "1 address".into()
    } else {
        format!("{count} addresses")
    }
}

fn upgradeable_loader_label(
    instruction: &UpgradeableLoaderInstruction,
    accounts: &[String],
) -> (&'static str, String) {
    match instruction {
        UpgradeableLoaderInstruction::InitializeBuffer => (
            "program_buffer_initialize",
            "Initialize program buffer".into(),
        ),
        UpgradeableLoaderInstruction::Write { offset, bytes } => (
            "program_buffer_write",
            format!(
                "Write {} bytes to program buffer at offset {offset}",
                bytes.len()
            ),
        ),
        UpgradeableLoaderInstruction::DeployWithMaxDataLen { max_data_len } => (
            "program_deploy",
            format!(
                "Deploy upgradeable program{} with max data length {max_data_len}",
                accounts
                    .get(2)
                    .map(|program| format!(" {program}"))
                    .unwrap_or_default()
            ),
        ),
        UpgradeableLoaderInstruction::Upgrade => (
            "program_upgrade",
            format!(
                "Upgrade program{}",
                accounts
                    .get(1)
                    .map(|program| format!(" {program}"))
                    .unwrap_or_default()
            ),
        ),
        UpgradeableLoaderInstruction::SetAuthority => match accounts.get(2) {
            Some(authority) => (
                "program_upgrade_authority_change",
                format!("Set upgrade authority to {authority}"),
            ),
            None => (
                "program_upgrade_authority_change",
                "Clear upgrade authority".into(),
            ),
        },
        UpgradeableLoaderInstruction::SetAuthorityChecked => (
            "program_upgrade_authority_change",
            format!(
                "Set upgrade authority to {}",
                accounts
                    .get(2)
                    .map(String::as_str)
                    .unwrap_or("new authority")
            ),
        ),
        UpgradeableLoaderInstruction::Close => {
            ("program_close", "Close upgradeable loader account".into())
        }
        UpgradeableLoaderInstruction::ExtendProgram { additional_bytes } => (
            "program_extend",
            format!("Extend program by {additional_bytes} bytes"),
        ),
    }
}

fn upgradeable_loader_effect_accounts(
    instruction: &UpgradeableLoaderInstruction,
    accounts: &[String],
) -> (Option<String>, Option<String>, Option<String>) {
    match instruction {
        UpgradeableLoaderInstruction::InitializeBuffer => (
            accounts.first().cloned(),
            accounts.get(1).cloned(),
            accounts.first().cloned(),
        ),
        UpgradeableLoaderInstruction::Write { .. } => (
            accounts.first().cloned(),
            accounts.get(1).cloned(),
            accounts.first().cloned(),
        ),
        UpgradeableLoaderInstruction::DeployWithMaxDataLen { .. } => (
            accounts.get(2).cloned(),
            accounts.get(3).cloned(),
            accounts.get(2).cloned(),
        ),
        UpgradeableLoaderInstruction::Upgrade => (
            accounts.get(1).cloned(),
            accounts.get(2).cloned(),
            accounts.get(1).cloned(),
        ),
        UpgradeableLoaderInstruction::SetAuthority
        | UpgradeableLoaderInstruction::SetAuthorityChecked => (
            accounts.first().cloned(),
            accounts.get(1).cloned(),
            accounts.get(2).cloned(),
        ),
        UpgradeableLoaderInstruction::Close => (
            accounts.first().cloned(),
            accounts.first().cloned(),
            accounts.get(1).cloned(),
        ),
        UpgradeableLoaderInstruction::ExtendProgram { .. } => (
            accounts.get(1).cloned(),
            accounts.get(3).cloned(),
            accounts.first().cloned(),
        ),
    }
}

fn token_authority_type_label(value: u8) -> &'static str {
    match value {
        0 => "mint authority",
        1 => "freeze authority",
        2 => "account owner",
        3 => "close authority",
        _ => "authority",
    }
}

fn coption_pubkey_from_token_data(data: &[u8], offset: usize) -> Option<String> {
    let tag = read_u32_le(data, offset)?;
    if tag == 0 {
        return None;
    }
    pubkey_from_data(data, offset + 4).map(|pubkey| pubkey.to_string())
}

fn squads_effect_from_instruction(instruction: &DecodedInstruction) -> Option<InspectionEffect> {
    let kind = match instruction.kind.as_str() {
        "add_member" => "squads_add_member",
        "remove_member" => "squads_remove_member",
        "change_threshold" => "squads_change_threshold",
        "set_time_lock" => "squads_set_time_lock",
        "add_spending_limit" => "squads_add_spending_limit",
        "remove_spending_limit" => "squads_remove_spending_limit",
        "set_rent_collector" => "squads_set_rent_collector",
        "config" => "squads_config",
        _ => return None,
    };

    Some(InspectionEffect {
        kind: kind.into(),
        summary: instruction.summary.clone(),
        program: Some("Squads".into()),
        asset: None,
        amount: None,
        source: None,
        destination: instruction.accounts.first().cloned(),
    })
}

fn is_known_non_effect_instruction(instruction: &DecodedInstruction) -> bool {
    is_memo_program(&instruction.program) || is_compute_budget_program(&instruction.program)
}

fn action_from_transaction_json(transaction: &Value) -> InspectionAction {
    let mut effects = Vec::new();
    collect_effects_from_instruction_array(
        transaction.pointer("/transaction/message/instructions"),
        &mut effects,
    );

    if let Some(groups) = transaction
        .pointer("/meta/innerInstructions")
        .and_then(Value::as_array)
    {
        for group in groups {
            collect_effects_from_instruction_array(group.get("instructions"), &mut effects);
        }
    }

    InspectionAction::from_effects(effects, 0)
}

/// jsonParsed non-checked `transfer` instructions carry `source`/`destination`/
/// `amount`/`authority` but no `mint`, so `token_effect_from_parsed_instruction`
/// leaves `asset` empty for those legs. Reports whether an effect is one of
/// those unresolved transfer legs worth attempting to fix up: already-resolved
/// effects (checked transfers, or anything with `asset` set) and non-transfer
/// effects are left alone.
fn transfer_asset_needs_resolution(effect: &InspectionEffect) -> bool {
    effect.kind == "token_transfer" && effect.asset.is_none()
}

/// Post-pass over an already-assembled action's effects: for token-transfer legs
/// that jsonParsed (or the decoded path) left blank, fills in `asset` (the mint
/// address) by reading each transfer's `source` token account, and — when the
/// mint's decimals are also readable — rewrites the raw `"<n> base units"` amount
/// into the same trimmed decimal form a checked transfer already shows.
///
/// Fail-safe, layered: if the mint can't be resolved at all, `asset` stays `None`
/// and the amount is untouched (exactly as before this pass ran). If the mint
/// resolves but its decimals don't, `asset` is set and the amount is left as
/// `"<n> base units"` — a partial improvement that is never worse than before.
/// No failure panics.
///
/// Reads are cached by source account within a single call so a swap with several
/// transfers sharing a source doesn't re-fetch the same accounts.
fn resolve_missing_transfer_assets(action: &mut InspectionAction, rpc_url: &str) {
    let mut resolved_by_source: HashMap<String, Option<(String, Option<u8>)>> = HashMap::new();
    for effect in &mut action.effects {
        if !transfer_asset_needs_resolution(effect) {
            continue;
        }
        let Some(source) = effect.source.clone() else {
            continue;
        };
        let resolved = resolved_by_source
            .entry(source.clone())
            .or_insert_with(|| resolve_transfer_mint(rpc_url, &source))
            .clone();
        let Some((mint, decimals)) = resolved else {
            continue;
        };
        effect.asset = Some(mint);
        if let Some(decimals) = decimals {
            reformat_transfer_amount_as_decimal(effect, decimals);
        }
    }
}

/// Resolves a transfer's `source` token account to `(mint_address, decimals)`.
/// The mint address — the value the on-device cross-check needs — is resolved
/// first; decimals are a secondary lookup used only to pretty-print the amount,
/// so a mint that resolves without readable decimals still returns
/// `Some((mint, None))`. `None` only when the mint itself can't be resolved
/// (bad address, missing account, RPC error, or not a token account).
fn resolve_transfer_mint(rpc_url: &str, source: &str) -> Option<(String, Option<u8>)> {
    let source_key: Pubkey = source.parse().ok()?;
    let mint = read_token_account_mint(rpc_url, &source_key)
        .ok()
        .flatten()?;
    let decimals = read_mint_decimals(rpc_url, &mint).ok().flatten();
    Some((mint.to_string(), decimals))
}

/// Rewrites a resolved non-checked transfer's raw `"<n> base units"` amount into
/// the trimmed decimal form a checked transfer already uses (e.g. `"1.5"`), and
/// updates the summary to match. A no-op if the amount isn't the expected
/// base-units shape or `n` doesn't parse as `u64`, so the raw display survives
/// unchanged rather than being corrupted.
fn reformat_transfer_amount_as_decimal(effect: &mut InspectionEffect, decimals: u8) {
    let Some(base_units) = effect
        .amount
        .as_deref()
        .and_then(|amount| amount.strip_suffix(" base units"))
        .and_then(|digits| digits.parse::<u64>().ok())
    else {
        return;
    };
    let display = format_decimal_amount(base_units, decimals);
    effect.summary = token_amount_summary("Transfer", &display);
    effect.amount = Some(display);
}

fn collect_effects_from_instruction_array(
    value: Option<&Value>,
    effects: &mut Vec<InspectionEffect>,
) {
    let Some(instructions) = value.and_then(Value::as_array) else {
        return;
    };

    for instruction in instructions {
        if let Some(effect) = effect_from_parsed_instruction(instruction) {
            effects.push(effect);
        }
    }
}

fn effect_from_parsed_instruction(instruction: &Value) -> Option<InspectionEffect> {
    let program = instruction.get("program").and_then(Value::as_str);
    let program_id = instruction.get("programId").and_then(Value::as_str);

    if program_id.is_some_and(is_squads_program) {
        return squads_effect_from_json_instruction(instruction);
    }

    if program_id.is_some_and(is_upgradeable_loader_program) {
        return upgradeable_loader_effect_from_json_instruction(instruction);
    }

    if program_id.is_some_and(is_stake_program) {
        return stake_effect_from_json_instruction(instruction);
    }

    if program_id.is_some_and(is_address_lookup_table_program) {
        return address_lookup_table_effect_from_json_instruction(instruction);
    }

    let parsed = instruction.get("parsed")?;
    let kind = parsed.get("type").and_then(Value::as_str)?;
    let info = parsed.get("info")?;

    if matches!(program, Some("system")) || matches!(program_id, Some(SYSTEM_PROGRAM_ID)) {
        return system_effect_from_parsed_instruction(kind, info);
    }

    if matches!(program, Some("spl-token"))
        || matches!(
            program_id,
            Some(SPL_TOKEN_PROGRAM_ID | TOKEN_2022_PROGRAM_ID)
        )
    {
        return token_effect_from_parsed_instruction(kind, info, program_id);
    }

    if matches!(program, Some("spl-associated-token-account"))
        || matches!(program_id, Some(ASSOCIATED_TOKEN_ACCOUNT_PROGRAM_ID))
    {
        return associated_token_account_effect_from_parsed_instruction(kind, info);
    }

    None
}

fn system_effect_from_parsed_instruction(kind: &str, info: &Value) -> Option<InspectionEffect> {
    match kind {
        "createAccount" | "createAccountWithSeed" => {
            let lamports = info.get("lamports").and_then(Value::as_u64)?;
            let space = info.get("space").and_then(Value::as_u64)?;
            let owner = info.get("owner").and_then(Value::as_str)?;
            let is_nonce = owner == SYSTEM_PROGRAM_ID && space == NonceState::size() as u64;
            let (effect_kind, summary) = if is_nonce {
                (
                    "nonce_account_create",
                    if kind == "createAccountWithSeed" {
                        format!(
                            "Create seeded nonce account with {}",
                            format_lamports(lamports)
                        )
                    } else {
                        format!("Create nonce account with {}", format_lamports(lamports))
                    },
                )
            } else {
                (
                    "system_account_create",
                    if kind == "createAccountWithSeed" {
                        format!(
                            "Create seeded account with {}, {space} bytes, owner {owner}",
                            format_lamports(lamports)
                        )
                    } else {
                        format!(
                            "Create account with {}, {space} bytes, owner {owner}",
                            format_lamports(lamports)
                        )
                    },
                )
            };
            Some(InspectionEffect {
                kind: effect_kind.into(),
                summary,
                program: Some("System Program".into()),
                asset: if is_nonce {
                    Some("SOL".into())
                } else {
                    Some(owner.into())
                },
                amount: Some(format_lamports(lamports)),
                source: first_string(info, &["source"]),
                destination: first_string(info, &["newAccount"]),
            })
        }
        "transfer" => {
            let lamports = info.get("lamports").and_then(Value::as_u64)?;
            Some(InspectionEffect {
                kind: "sol_transfer".into(),
                summary: format!("Transfer {}", format_lamports(lamports)),
                program: Some("System Program".into()),
                asset: Some("SOL".into()),
                amount: Some(format_lamports(lamports)),
                source: info.get("source").and_then(Value::as_str).map(String::from),
                destination: info
                    .get("destination")
                    .and_then(Value::as_str)
                    .map(String::from),
            })
        }
        "assign" | "assignWithSeed" => {
            let owner = info.get("owner").and_then(Value::as_str)?;
            let summary = if kind == "assignWithSeed" {
                format!("Assign seeded account owner to {owner}")
            } else {
                format!("Assign account owner to {owner}")
            };
            Some(InspectionEffect {
                kind: "system_account_owner_change".into(),
                summary,
                program: Some("System Program".into()),
                asset: None,
                amount: None,
                source: info
                    .get("account")
                    .and_then(Value::as_str)
                    .map(String::from),
                destination: Some(owner.into()),
            })
        }
        "advanceNonce" => Some(InspectionEffect {
            kind: "nonce_advance".into(),
            summary: "Advance nonce".into(),
            program: Some("System Program".into()),
            asset: None,
            amount: None,
            source: first_string(info, &["nonceAccount"]),
            destination: first_string(info, &["nonceAuthority"]),
        }),
        "withdrawFromNonce" => {
            let lamports = info.get("lamports").and_then(Value::as_u64)?;
            Some(InspectionEffect {
                kind: "nonce_withdraw".into(),
                summary: format!("Withdraw {} from nonce account", format_lamports(lamports)),
                program: Some("System Program".into()),
                asset: Some("SOL".into()),
                amount: Some(format_lamports(lamports)),
                source: first_string(info, &["nonceAccount"]),
                destination: first_string(info, &["destination"]),
            })
        }
        "initializeNonce" | "authorizeNonce" => {
            let authority = first_string(info, &["newAuthorized", "nonceAuthority"])?;
            let summary = if kind == "initializeNonce" {
                format!("Initialize nonce authority {authority}")
            } else {
                format!("Authorize nonce authority {authority}")
            };
            let source = if kind == "initializeNonce" {
                first_string(info, &["nonceAccount"])
            } else {
                first_string(info, &["nonceAuthority", "nonceAccount"])
            };
            Some(InspectionEffect {
                kind: "nonce_authority_change".into(),
                summary,
                program: Some("System Program".into()),
                asset: None,
                amount: None,
                source,
                destination: Some(authority),
            })
        }
        "upgradeNonce" => Some(InspectionEffect {
            kind: "nonce_upgrade".into(),
            summary: "Upgrade nonce account".into(),
            program: Some("System Program".into()),
            asset: None,
            amount: None,
            source: first_string(info, &["nonceAccount"]),
            destination: first_string(info, &["nonceAccount"]),
        }),
        "allocate" | "allocateWithSeed" => {
            let space = info.get("space").and_then(Value::as_u64)?;
            let owner = info.get("owner").and_then(Value::as_str);
            let summary = match owner {
                Some(owner) => {
                    format!("Allocate {space} bytes for seeded account owned by {owner}")
                }
                None => format!("Allocate {space} bytes for system account"),
            };
            Some(InspectionEffect {
                kind: "system_account_allocate".into(),
                summary,
                program: Some("System Program".into()),
                asset: owner.map(String::from),
                amount: None,
                source: first_string(info, &["account"]),
                destination: first_string(info, &["account"]),
            })
        }
        "transferWithSeed" => {
            let lamports = info.get("lamports").and_then(Value::as_u64)?;
            Some(InspectionEffect {
                kind: "sol_transfer".into(),
                summary: format!("Transfer {} from seeded account", format_lamports(lamports)),
                program: Some("System Program".into()),
                asset: Some("SOL".into()),
                amount: Some(format_lamports(lamports)),
                source: first_string(info, &["source"]),
                destination: first_string(info, &["destination"]),
            })
        }
        _ => None,
    }
}

fn token_effect_from_parsed_instruction(
    kind: &str,
    info: &Value,
    program_id: Option<&str>,
) -> Option<InspectionEffect> {
    let amount = parsed_token_amount(info);

    match kind {
        "transfer" | "transferChecked" => {
            let display_amount = amount.as_deref()?;
            Some(InspectionEffect {
                kind: "token_transfer".into(),
                summary: token_amount_summary("Transfer", display_amount),
                program: program_id.map(token_program_label).map(String::from),
                asset: info.get("mint").and_then(Value::as_str).map(String::from),
                amount,
                source: info.get("source").and_then(Value::as_str).map(String::from),
                destination: info
                    .get("destination")
                    .and_then(Value::as_str)
                    .map(String::from),
            })
        }
        "approve" | "approveChecked" => {
            let display_amount = amount.as_deref()?;
            Some(InspectionEffect {
                kind: "token_approve".into(),
                summary: token_amount_summary("Approve", display_amount),
                program: program_id.map(token_program_label).map(String::from),
                asset: info.get("mint").and_then(Value::as_str).map(String::from),
                amount,
                source: info.get("source").and_then(Value::as_str).map(String::from),
                destination: info
                    .get("delegate")
                    .and_then(Value::as_str)
                    .map(String::from),
            })
        }
        "mintTo" | "mintToChecked" => {
            let display_amount = amount.as_deref()?;
            Some(InspectionEffect {
                kind: "token_mint".into(),
                summary: token_amount_summary("Mint", display_amount),
                program: program_id.map(token_program_label).map(String::from),
                asset: info.get("mint").and_then(Value::as_str).map(String::from),
                amount,
                source: first_string(info, &["mintAuthority", "authority"]),
                destination: first_string(info, &["account", "destination"]),
            })
        }
        "burn" | "burnChecked" => {
            let display_amount = amount.as_deref()?;
            Some(InspectionEffect {
                kind: "token_burn".into(),
                summary: token_amount_summary("Burn", display_amount),
                program: program_id.map(token_program_label).map(String::from),
                asset: info.get("mint").and_then(Value::as_str).map(String::from),
                amount,
                source: first_string(info, &["account", "source"]),
                destination: info.get("mint").and_then(Value::as_str).map(String::from),
            })
        }
        _ => None,
    }
    .or_else(|| token_non_amount_effect_from_parsed_instruction(kind, info, program_id))
}

fn parsed_token_amount(info: &Value) -> Option<String> {
    info.get("tokenAmount")
        .and_then(|token_amount| token_amount.get("uiAmountString"))
        .and_then(Value::as_str)
        .map(String::from)
        .or_else(|| {
            info.get("amount")
                .and_then(Value::as_str)
                .map(|amount| format!("{amount} base units"))
        })
}

fn token_amount_summary(verb: &str, amount: &str) -> String {
    if amount.ends_with("base units") {
        format!("{verb} {amount}")
    } else {
        format!("{verb} {amount} tokens")
    }
}

fn token_non_amount_effect_from_parsed_instruction(
    kind: &str,
    info: &Value,
    program_id: Option<&str>,
) -> Option<InspectionEffect> {
    match kind {
        "revoke" => Some(InspectionEffect {
            kind: "token_revoke".into(),
            summary: "Revoke token delegate".into(),
            program: program_id.map(token_program_label).map(String::from),
            asset: info.get("mint").and_then(Value::as_str).map(String::from),
            amount: None,
            source: first_string(info, &["source", "account"]),
            destination: None,
        }),
        "setAuthority" => {
            let authority_type = info
                .get("authorityType")
                .and_then(Value::as_str)
                .unwrap_or("authority");
            let new_authority = first_string(info, &["newAuthority"]);
            let summary = match new_authority.as_deref() {
                Some(authority) => format!("Set token {authority_type} to {authority}"),
                None => format!("Clear token {authority_type}"),
            };
            Some(InspectionEffect {
                kind: "token_authority_change".into(),
                summary,
                program: program_id.map(token_program_label).map(String::from),
                asset: info.get("mint").and_then(Value::as_str).map(String::from),
                amount: None,
                source: first_string(info, &["authority", "currentAuthority"]),
                destination: new_authority.or_else(|| first_string(info, &["account"])),
            })
        }
        "closeAccount" => Some(InspectionEffect {
            kind: "token_account_close".into(),
            summary: "Close token account".into(),
            program: program_id.map(token_program_label).map(String::from),
            asset: info.get("mint").and_then(Value::as_str).map(String::from),
            amount: None,
            source: first_string(info, &["account"]),
            destination: first_string(info, &["destination"]),
        }),
        "freezeAccount" => Some(InspectionEffect {
            kind: "token_account_freeze".into(),
            summary: "Freeze token account".into(),
            program: program_id.map(token_program_label).map(String::from),
            asset: info.get("mint").and_then(Value::as_str).map(String::from),
            amount: None,
            source: first_string(info, &["account"]),
            destination: None,
        }),
        "thawAccount" => Some(InspectionEffect {
            kind: "token_account_thaw".into(),
            summary: "Thaw token account".into(),
            program: program_id.map(token_program_label).map(String::from),
            asset: info.get("mint").and_then(Value::as_str).map(String::from),
            amount: None,
            source: first_string(info, &["account"]),
            destination: None,
        }),
        _ => None,
    }
}

fn associated_token_account_effect_from_parsed_instruction(
    kind: &str,
    info: &Value,
) -> Option<InspectionEffect> {
    let summary = match kind {
        "create" => "Create associated token account",
        "createIdempotent" => "Create associated token account if needed",
        "recoverNested" => "Recover nested associated token account",
        _ => return None,
    };

    Some(InspectionEffect {
        kind: "associated_token_account_create".into(),
        summary: summary.into(),
        program: Some("Associated Token Account Program".into()),
        asset: first_string(info, &["mint"]),
        amount: None,
        source: first_string(info, &["source", "fundingAddress", "payer"]),
        destination: first_string(info, &["account", "associatedAccount", "destination"]),
    })
}

fn stake_effect_from_json_instruction(instruction: &Value) -> Option<InspectionEffect> {
    if let Some(data) = instruction_data_bytes_from_json(instruction) {
        let accounts = accounts_from_json_instruction(instruction);
        return stake_effect_from_raw_instruction(&data, &accounts);
    }

    let parsed = instruction.get("parsed")?;
    let kind = parsed.get("type").and_then(Value::as_str)?;
    let info = parsed.get("info")?;
    stake_effect_from_parsed_instruction(kind, info)
}

fn stake_effect_from_parsed_instruction(kind: &str, info: &Value) -> Option<InspectionEffect> {
    match kind {
        "initialize" | "initializeChecked" => Some(InspectionEffect {
            kind: "stake_initialize".into(),
            summary: "Initialize stake account".into(),
            program: Some("Stake Program".into()),
            asset: first_string(info, &["stakeAccount"]),
            amount: None,
            source: first_string(info, &["staker", "withdrawer"]),
            destination: first_string(info, &["stakeAccount"]),
        }),
        "authorize" | "authorizeWithSeed" | "authorizeChecked" | "authorizeCheckedWithSeed" => {
            let authority_type = stake_authority_label_from_info(info);
            let new_authority = first_string(info, &["newAuthority", "newAuthorized"])?;
            Some(InspectionEffect {
                kind: "stake_authority_change".into(),
                summary: format!("Set stake {authority_type} authority to {new_authority}"),
                program: Some("Stake Program".into()),
                asset: first_string(info, &["stakeAccount"]),
                amount: None,
                source: first_string(info, &["authority", "authorityBase"]),
                destination: Some(new_authority),
            })
        }
        "delegate" => Some(InspectionEffect {
            kind: "stake_delegate".into(),
            summary: format!(
                "Delegate stake{}",
                first_string(info, &["voteAccount"])
                    .map(|vote| format!(" to {vote}"))
                    .unwrap_or_default()
            ),
            program: Some("Stake Program".into()),
            asset: first_string(info, &["stakeAccount"]),
            amount: None,
            source: first_string(info, &["stakeAuthority"]),
            destination: first_string(info, &["voteAccount"]),
        }),
        "split" => {
            let lamports = info.get("lamports").and_then(Value::as_u64)?;
            Some(InspectionEffect {
                kind: "stake_split".into(),
                summary: format!("Split {} stake", format_lamports(lamports)),
                program: Some("Stake Program".into()),
                asset: Some("SOL".into()),
                amount: Some(format_lamports(lamports)),
                source: first_string(info, &["stakeAccount"]),
                destination: first_string(info, &["newSplitAccount"]),
            })
        }
        "withdraw" => {
            let lamports = info.get("lamports").and_then(Value::as_u64)?;
            Some(InspectionEffect {
                kind: "stake_withdraw".into(),
                summary: format!("Withdraw {} from stake", format_lamports(lamports)),
                program: Some("Stake Program".into()),
                asset: Some("SOL".into()),
                amount: Some(format_lamports(lamports)),
                source: first_string(info, &["stakeAccount"]),
                destination: first_string(info, &["destination"]),
            })
        }
        "deactivate" | "deactivateDelinquent" => Some(InspectionEffect {
            kind: "stake_deactivate".into(),
            summary: "Deactivate stake".into(),
            program: Some("Stake Program".into()),
            asset: first_string(info, &["stakeAccount"]),
            amount: None,
            source: first_string(info, &["stakeAuthority", "referenceVoteAccount"]),
            destination: first_string(info, &["stakeAccount"]),
        }),
        "setLockup" | "setLockupChecked" => Some(InspectionEffect {
            kind: "stake_lockup_change".into(),
            summary: "Set stake lockup".into(),
            program: Some("Stake Program".into()),
            asset: first_string(info, &["stakeAccount"]),
            amount: None,
            source: first_string(info, &["custodian"]),
            destination: first_string(info, &["stakeAccount"]),
        }),
        "merge" => Some(InspectionEffect {
            kind: "stake_merge".into(),
            summary: "Merge stake accounts".into(),
            program: Some("Stake Program".into()),
            asset: first_string(info, &["destination"]),
            amount: None,
            source: first_string(info, &["source"]),
            destination: first_string(info, &["destination"]),
        }),
        "redelegate" => Some(InspectionEffect {
            kind: "stake_redelegate".into(),
            summary: format!(
                "Redelegate stake{}",
                first_string(info, &["voteAccount"])
                    .map(|vote| format!(" to {vote}"))
                    .unwrap_or_default()
            ),
            program: Some("Stake Program".into()),
            asset: first_string(info, &["stakeAccount"]),
            amount: None,
            source: first_string(info, &["stakeAccount"]),
            destination: first_string(info, &["newStakeAccount", "voteAccount"]),
        }),
        _ => None,
    }
}

fn address_lookup_table_effect_from_json_instruction(
    instruction: &Value,
) -> Option<InspectionEffect> {
    if let Some(data) = instruction_data_bytes_from_json(instruction) {
        let accounts = accounts_from_json_instruction(instruction);
        return address_lookup_table_effect_from_raw_instruction(&data, &accounts);
    }

    let parsed = instruction.get("parsed")?;
    let kind = parsed.get("type").and_then(Value::as_str)?;
    let info = parsed.get("info")?;
    address_lookup_table_effect_from_parsed_instruction(kind, info)
}

fn address_lookup_table_effect_from_parsed_instruction(
    kind: &str,
    info: &Value,
) -> Option<InspectionEffect> {
    match kind {
        "createLookupTable" => Some(InspectionEffect {
            kind: "lookup_table_create".into(),
            summary: "Create address lookup table".into(),
            program: Some("Address Lookup Table Program".into()),
            asset: first_string(info, &["lookupTableAccount"]),
            amount: None,
            source: first_string(info, &["payerAccount"]),
            destination: first_string(info, &["lookupTableAccount"]),
        }),
        "freezeLookupTable" => Some(InspectionEffect {
            kind: "lookup_table_freeze".into(),
            summary: "Freeze address lookup table".into(),
            program: Some("Address Lookup Table Program".into()),
            asset: first_string(info, &["lookupTableAccount"]),
            amount: None,
            source: first_string(info, &["lookupTableAuthority"]),
            destination: first_string(info, &["lookupTableAccount"]),
        }),
        "extendLookupTable" => {
            let count = info
                .get("newAddresses")
                .and_then(Value::as_array)
                .map(Vec::len)
                .unwrap_or_default();
            Some(InspectionEffect {
                kind: "lookup_table_extend".into(),
                summary: format!(
                    "Extend address lookup table with {}",
                    address_count_label(count)
                ),
                program: Some("Address Lookup Table Program".into()),
                asset: first_string(info, &["lookupTableAccount"]),
                amount: Some(address_count_label(count)),
                source: first_string(info, &["lookupTableAuthority"]),
                destination: first_string(info, &["lookupTableAccount"]),
            })
        }
        "deactivateLookupTable" => Some(InspectionEffect {
            kind: "lookup_table_deactivate".into(),
            summary: "Deactivate address lookup table".into(),
            program: Some("Address Lookup Table Program".into()),
            asset: first_string(info, &["lookupTableAccount"]),
            amount: None,
            source: first_string(info, &["lookupTableAuthority"]),
            destination: first_string(info, &["lookupTableAccount"]),
        }),
        "closeLookupTable" => Some(InspectionEffect {
            kind: "lookup_table_close".into(),
            summary: "Close address lookup table".into(),
            program: Some("Address Lookup Table Program".into()),
            asset: first_string(info, &["lookupTableAccount"]),
            amount: None,
            source: first_string(info, &["lookupTableAccount"]),
            destination: first_string(info, &["recipient"]),
        }),
        _ => None,
    }
}

fn squads_effect_from_json_instruction(instruction: &Value) -> Option<InspectionEffect> {
    let data = instruction_data_bytes_from_json(instruction)?;
    let accounts = accounts_from_json_instruction(instruction);
    squads_effect_from_raw_instruction(&data, &accounts)
}

fn upgradeable_loader_effect_from_json_instruction(
    instruction: &Value,
) -> Option<InspectionEffect> {
    if let Some(data) = instruction_data_bytes_from_json(instruction) {
        let accounts = accounts_from_json_instruction(instruction);
        return upgradeable_loader_effect_from_raw_instruction(&data, &accounts);
    }

    let parsed = instruction.get("parsed")?;
    let kind = parsed.get("type").and_then(Value::as_str)?;
    let info = parsed.get("info")?;
    upgradeable_loader_effect_from_parsed_instruction(kind, info)
}

fn upgradeable_loader_effect_from_raw_instruction(
    data: &[u8],
    accounts: &[String],
) -> Option<InspectionEffect> {
    let loader_instruction = bincode::deserialize::<UpgradeableLoaderInstruction>(data).ok()?;
    let (kind, summary) = upgradeable_loader_label(&loader_instruction, accounts);
    let (asset, source, destination) =
        upgradeable_loader_effect_accounts(&loader_instruction, accounts);

    Some(InspectionEffect {
        kind: kind.into(),
        summary,
        program: Some("BPF Upgradeable Loader".into()),
        asset,
        amount: None,
        source,
        destination,
    })
}

fn upgradeable_loader_effect_from_parsed_instruction(
    kind: &str,
    info: &Value,
) -> Option<InspectionEffect> {
    match kind {
        "initializeBuffer" => Some(InspectionEffect {
            kind: "program_buffer_initialize".into(),
            summary: "Initialize program buffer".into(),
            program: Some("BPF Upgradeable Loader".into()),
            asset: first_string(info, &["account"]),
            amount: None,
            source: first_string(info, &["authority"]),
            destination: first_string(info, &["account"]),
        }),
        "write" => {
            let offset = info
                .get("offset")
                .and_then(Value::as_u64)
                .unwrap_or_default();
            let byte_count = info
                .get("bytes")
                .and_then(Value::as_str)
                .and_then(|bytes| BASE64_STANDARD.decode(bytes).ok())
                .map(|bytes| bytes.len());
            let summary = match byte_count {
                Some(byte_count) => {
                    format!("Write {byte_count} bytes to program buffer at offset {offset}")
                }
                None => format!("Write program buffer at offset {offset}"),
            };
            Some(InspectionEffect {
                kind: "program_buffer_write".into(),
                summary,
                program: Some("BPF Upgradeable Loader".into()),
                asset: first_string(info, &["account"]),
                amount: None,
                source: first_string(info, &["authority"]),
                destination: first_string(info, &["account"]),
            })
        }
        "deployWithMaxDataLen" => {
            let max_data_len = info
                .get("maxDataLen")
                .and_then(Value::as_u64)
                .map(|value| format!(" with max data length {value}"))
                .unwrap_or_default();
            Some(InspectionEffect {
                kind: "program_deploy".into(),
                summary: format!("Deploy upgradeable program{max_data_len}"),
                program: Some("BPF Upgradeable Loader".into()),
                asset: first_string(info, &["programAccount"]),
                amount: None,
                source: first_string(info, &["bufferAccount"]),
                destination: first_string(info, &["programAccount"]),
            })
        }
        "upgrade" => {
            let program = first_string(info, &["programAccount"]);
            Some(InspectionEffect {
                kind: "program_upgrade".into(),
                summary: format!(
                    "Upgrade program{}",
                    program
                        .as_deref()
                        .map(|program| format!(" {program}"))
                        .unwrap_or_default()
                ),
                program: Some("BPF Upgradeable Loader".into()),
                asset: program.clone(),
                amount: None,
                source: first_string(info, &["bufferAccount"]),
                destination: program,
            })
        }
        "setAuthority" | "setAuthorityChecked" => {
            let new_authority = first_string(info, &["newAuthority"]);
            let summary = match new_authority.as_deref() {
                Some(authority) => format!("Set upgrade authority to {authority}"),
                None => "Clear upgrade authority".into(),
            };
            Some(InspectionEffect {
                kind: "program_upgrade_authority_change".into(),
                summary,
                program: Some("BPF Upgradeable Loader".into()),
                asset: first_string(info, &["account"]),
                amount: None,
                source: first_string(info, &["authority"]),
                destination: new_authority,
            })
        }
        "close" => Some(InspectionEffect {
            kind: "program_close".into(),
            summary: "Close upgradeable loader account".into(),
            program: Some("BPF Upgradeable Loader".into()),
            asset: first_string(info, &["account", "programAccount"]),
            amount: None,
            source: first_string(info, &["account"]),
            destination: first_string(info, &["recipient"]),
        }),
        "extendProgram" => {
            let additional_bytes = info
                .get("additionalBytes")
                .and_then(Value::as_u64)
                .map(|value| format!(" by {value} bytes"))
                .unwrap_or_default();
            Some(InspectionEffect {
                kind: "program_extend".into(),
                summary: format!("Extend program{additional_bytes}"),
                program: Some("BPF Upgradeable Loader".into()),
                asset: first_string(info, &["programAccount"]),
                amount: None,
                source: first_string(info, &["payerAccount"]),
                destination: first_string(info, &["programDataAccount"]),
            })
        }
        _ => None,
    }
}

fn squads_effect_from_raw_instruction(
    data: &[u8],
    accounts: &[String],
) -> Option<InspectionEffect> {
    let (kind, summary, source, destination) =
        if has_anchor_discriminator::<ProposalApproveData>(data) {
            (
                "squads_proposal_approve",
                "Approve proposal".into(),
                accounts.get(1).cloned(),
                accounts.get(2).cloned(),
            )
        } else if has_anchor_discriminator::<ProposalRejectData>(data) {
            (
                "squads_proposal_reject",
                "Reject proposal".into(),
                accounts.get(1).cloned(),
                accounts.get(2).cloned(),
            )
        } else if has_anchor_discriminator::<ProposalCancelData>(data) {
            (
                "squads_proposal_cancel",
                "Cancel approved proposal".into(),
                accounts.get(1).cloned(),
                accounts.get(2).cloned(),
            )
        } else if has_anchor_discriminator::<VaultTransactionExecuteData>(data) {
            (
                "squads_execute_vault_transaction",
                "Execute vault transaction".into(),
                accounts.get(3).cloned(),
                accounts.get(2).cloned(),
            )
        } else if has_anchor_discriminator::<ConfigTransactionExecuteData>(data) {
            (
                "squads_execute_config_transaction",
                "Execute config transaction".into(),
                accounts.get(1).cloned(),
                accounts.get(3).cloned(),
            )
        } else if has_anchor_discriminator::<ProposalCreateData>(data) {
            let index = read_u64_le(data, 8)
                .map(|index| format!(" {index}"))
                .unwrap_or_default();
            (
                "squads_proposal_create",
                format!("Create proposal{index}"),
                accounts.get(2).cloned(),
                accounts.get(1).cloned(),
            )
        } else {
            return None;
        };

    Some(InspectionEffect {
        kind: kind.into(),
        summary,
        program: Some("Squads".into()),
        asset: None,
        amount: None,
        source,
        destination,
    })
}

fn has_anchor_discriminator<T: Discriminator>(data: &[u8]) -> bool {
    data.get(..8) == Some(T::DISCRIMINATOR.as_slice())
}

fn accounts_from_json_instruction(instruction: &Value) -> Vec<String> {
    instruction
        .get("accounts")
        .and_then(Value::as_array)
        .map(|accounts| {
            accounts
                .iter()
                .filter_map(Value::as_str)
                .map(String::from)
                .collect()
        })
        .unwrap_or_default()
}

fn instruction_data_bytes_from_json(instruction: &Value) -> Option<Vec<u8>> {
    match instruction.get("data")? {
        Value::String(data) => bs58::decode(data).into_vec().ok(),
        Value::Array(values) => {
            let data = values.first().and_then(Value::as_str)?;
            let encoding = values
                .get(1)
                .and_then(Value::as_str)
                .unwrap_or("base58")
                .to_ascii_lowercase();
            match encoding.as_str() {
                "base64" => BASE64_STANDARD.decode(data).ok(),
                "base58" => bs58::decode(data).into_vec().ok(),
                _ => None,
            }
        }
        _ => None,
    }
}

fn inspection_action_summary(
    effects: &[InspectionEffect],
    primary_effects: &[&InspectionEffect],
) -> String {
    if effects.is_empty() {
        return "Review raw instructions before signing.".into();
    }

    if let Some(nonce_create) = effects
        .iter()
        .find(|effect| effect.kind == "nonce_account_create")
    {
        if let Some(authority) = effects
            .iter()
            .find(|effect| effect.kind == "nonce_authority_change")
            .and_then(|effect| effect.destination.as_deref())
        {
            return format!("Create nonce account with authority {authority}");
        }
        return nonce_create.summary.clone();
    }

    if primary_effects.len() == 1 {
        let primary = primary_effects[0];
        if effects
            .iter()
            .any(|effect| effect.kind == "associated_token_account_create")
        {
            return format!(
                "{} and create associated token account if needed",
                primary.summary
            );
        }
        return primary.summary.clone();
    }

    if effects.len() == 1 {
        return effects[0].summary.clone();
    }

    if effects.iter().all(is_squads_config_effect) {
        return format!("{} Squads config changes", effects.len());
    }

    format!("{} recognized effects", effects.len())
}

impl InspectionAction {
    fn from_effects(effects: Vec<InspectionEffect>, unknown_count: usize) -> Self {
        let warnings = action_warnings(&effects, unknown_count);
        let primary_effects = effects
            .iter()
            .filter(|effect| !is_context_effect(effect))
            .collect::<Vec<_>>();
        let classification = if effects.is_empty() {
            "unknown".into()
        } else if effects.len() > 1 && effects.iter().all(is_squads_config_effect) {
            "squads_config_change".into()
        } else if effects
            .iter()
            .any(|effect| effect.kind == "nonce_account_create")
        {
            "nonce_account_create".into()
        } else if primary_effects.len() == 1 {
            primary_effects[0].kind.clone()
        } else if effects.len() == 1 {
            effects[0].kind.clone()
        } else {
            "multi_effect".into()
        };
        let summary = inspection_action_summary(&effects, &primary_effects);
        let confidence = if effects.is_empty() {
            "low"
        } else if warnings.is_empty() {
            "high"
        } else {
            "medium"
        }
        .into();

        Self {
            classification,
            summary,
            confidence,
            effects,
            warnings,
        }
    }

    fn unknown(message: impl Into<String>) -> Self {
        Self {
            classification: "unknown".into(),
            summary: "Review raw instructions before signing.".into(),
            confidence: "low".into(),
            effects: Vec::new(),
            warnings: vec![InspectionWarning {
                severity: "warning".into(),
                code: "unknown_transaction".into(),
                message: message.into(),
            }],
        }
    }
}

fn is_context_effect(effect: &InspectionEffect) -> bool {
    matches!(
        effect.kind.as_str(),
        "associated_token_account_create"
            | "squads_execute_vault_transaction"
            | "squads_execute_config_transaction"
            | "squads_proposal_create"
            | "program_buffer_initialize"
            | "program_buffer_write"
    )
}

fn is_squads_config_effect(effect: &InspectionEffect) -> bool {
    matches!(
        effect.kind.as_str(),
        "squads_add_member"
            | "squads_remove_member"
            | "squads_change_threshold"
            | "squads_set_time_lock"
            | "squads_add_spending_limit"
            | "squads_remove_spending_limit"
            | "squads_set_rent_collector"
            | "squads_config"
    )
}

fn action_warnings(effects: &[InspectionEffect], unknown_count: usize) -> Vec<InspectionWarning> {
    if effects.is_empty() {
        return vec![InspectionWarning {
            severity: "warning".into(),
            code: "unknown_action".into(),
            message: "Cosign could not identify a well-known action.".into(),
        }];
    }

    if unknown_count > 0 {
        return vec![InspectionWarning {
            severity: "info".into(),
            code: "partial_decoding".into(),
            message: format!("{unknown_count} instruction(s) were not recognized."),
        }];
    }

    Vec::new()
}

fn transaction_logs(transaction: &Value) -> Vec<String> {
    transaction
        .pointer("/meta/logMessages")
        .and_then(Value::as_array)
        .map(|logs| {
            logs.iter()
                .filter_map(Value::as_str)
                .map(String::from)
                .collect()
        })
        .unwrap_or_default()
}

fn transaction_error(transaction: &Value) -> Option<String> {
    let err = transaction.pointer("/meta/err")?;
    (!err.is_null()).then(|| err.to_string())
}

fn is_system_program(program: &str) -> bool {
    program == SYSTEM_PROGRAM_ID || program == "System Program"
}

fn is_token_program(program: &str) -> bool {
    matches!(
        program,
        SPL_TOKEN_PROGRAM_ID | TOKEN_2022_PROGRAM_ID | "SPL Token Program" | "Token-2022 Program"
    )
}

fn is_stake_program(program: &str) -> bool {
    matches!(program, STAKE_PROGRAM_ID | "Stake Program" | "stake")
}

fn is_address_lookup_table_program(program: &str) -> bool {
    matches!(
        program,
        ADDRESS_LOOKUP_TABLE_PROGRAM_ID | "Address Lookup Table Program" | "address-lookup-table"
    )
}

fn is_squads_program(program: &str) -> bool {
    program == SQUADS_PROGRAM_ID || program == "Squads"
}

fn is_upgradeable_loader_program(program: &str) -> bool {
    matches!(
        program,
        BPF_UPGRADEABLE_LOADER_PROGRAM_ID | "BPF Upgradeable Loader" | "bpf-upgradeable-loader"
    )
}

fn is_associated_token_account_program(program: &str) -> bool {
    matches!(
        program,
        ASSOCIATED_TOKEN_ACCOUNT_PROGRAM_ID | "Associated Token Account Program"
    )
}

fn is_memo_program(program: &str) -> bool {
    matches!(
        program,
        MEMO_PROGRAM_ID | MEMO_LEGACY_PROGRAM_ID | "Memo Program"
    )
}

fn is_compute_budget_program(program: &str) -> bool {
    matches!(
        program,
        COMPUTE_BUDGET_PROGRAM_ID | "Compute Budget Program"
    )
}

fn token_program_label(program: &str) -> &str {
    match program {
        TOKEN_2022_PROGRAM_ID => "Token-2022 Program",
        _ => "SPL Token Program",
    }
}

fn first_string(value: &Value, keys: &[&str]) -> Option<String> {
    keys.iter()
        .filter_map(|key| value.get(*key).and_then(Value::as_str))
        .next()
        .map(String::from)
}

fn stake_authority_label_from_info(info: &Value) -> &'static str {
    match info
        .get("authorityType")
        .and_then(Value::as_str)
        .map(|value| value.to_ascii_lowercase())
        .as_deref()
    {
        Some("withdrawer" | "withdraw") => "withdraw",
        _ => "staker",
    }
}

fn pubkey_from_data(data: &[u8], offset: usize) -> Option<Pubkey> {
    let bytes = data.get(offset..offset + 32)?;
    let mut pubkey = [0_u8; 32];
    pubkey.copy_from_slice(bytes);
    Some(Pubkey::new_from_array(pubkey))
}

fn is_nonce_account_creation(space: u64, owner: &Pubkey) -> bool {
    space == NonceState::size() as u64 && owner.to_string() == SYSTEM_PROGRAM_ID
}

fn short_text(value: &str, max_chars: usize) -> String {
    if value.chars().count() <= max_chars {
        return value.into();
    }

    let prefix = value.chars().take(max_chars).collect::<String>();
    format!("{prefix}...")
}

fn bytes_from_hex(hex: &str) -> Option<Vec<u8>> {
    let normalized = hex
        .chars()
        .filter(|character| !character.is_whitespace())
        .collect::<String>();
    if !normalized.len().is_multiple_of(2) {
        return None;
    }

    (0..normalized.len())
        .step_by(2)
        .map(|index| u8::from_str_radix(&normalized[index..index + 2], 16).ok())
        .collect()
}

fn read_u32_le(bytes: &[u8], offset: usize) -> Option<u32> {
    let bytes = bytes.get(offset..offset + 4)?;
    Some(u32::from_le_bytes(bytes.try_into().ok()?))
}

fn read_u64_le(bytes: &[u8], offset: usize) -> Option<u64> {
    let bytes = bytes.get(offset..offset + 8)?;
    Some(u64::from_le_bytes(bytes.try_into().ok()?))
}

fn format_lamports(lamports: u64) -> String {
    format!("{} SOL", format_decimal_amount(lamports, 9))
}

fn format_decimal_amount(amount: u64, decimals: u8) -> String {
    if decimals == 0 {
        return amount.to_string();
    }

    let decimals = usize::from(decimals);
    let digits = amount.to_string();
    let padded = if digits.len() <= decimals {
        format!("{}{}", "0".repeat(decimals - digits.len() + 1), digits)
    } else {
        digits
    };
    let split = padded.len() - decimals;
    let whole = &padded[..split];
    let fractional = padded[split..].trim_end_matches('0');
    if fractional.is_empty() {
        whole.to_string()
    } else {
        format!("{whole}.{fractional}")
    }
}

fn parse_proposal_inspection_request(
    path: &str,
    query: Option<&str>,
) -> Result<ProposalInspectionRequest, RelayError> {
    let mut parts = path.trim_matches('/').split('/');
    match (
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
    ) {
        (
            Some("cosign"),
            Some("v1"),
            Some("squads"),
            Some(squad),
            Some("transactions"),
            Some(index),
            Some("inspection"),
        ) if parts.next().is_none() => Ok(ProposalInspectionRequest {
            squad: squad
                .parse()
                .map_err(|_| RelayError::BadRequest("invalid squad address".into()))?,
            transaction_index: index
                .parse()
                .map_err(|_| RelayError::BadRequest("invalid transaction index".into()))?,
            query: InspectionQuery::parse(query),
        }),
        _ => Err(RelayError::NotFound),
    }
}

fn parse_transaction_inspection_request(
    path: &str,
    query: Option<&str>,
) -> Result<TransactionInspectionRequest, RelayError> {
    let mut parts = path.trim_matches('/').split('/');
    match (parts.next(), parts.next(), parts.next(), parts.next()) {
        (Some("cosign"), Some("v1"), Some("transactions"), Some(signature))
            if parts.next() == Some("inspection") && parts.next().is_none() =>
        {
            Ok(TransactionInspectionRequest {
                signature: signature
                    .parse()
                    .map_err(|_| RelayError::BadRequest("invalid transaction signature".into()))?,
                query: InspectionQuery::parse(query),
            })
        }
        _ => Err(RelayError::NotFound),
    }
}

fn parse_transaction_status_request(path: &str) -> Result<TransactionStatusRequest, RelayError> {
    let mut parts = path.trim_matches('/').split('/');
    match (parts.next(), parts.next(), parts.next(), parts.next()) {
        (Some("cosign"), Some("v1"), Some("transactions"), Some(signature))
            if parts.next() == Some("status") && parts.next().is_none() =>
        {
            Ok(TransactionStatusRequest {
                signature: signature
                    .parse()
                    .map_err(|_| RelayError::BadRequest("invalid transaction signature".into()))?,
            })
        }
        _ => Err(RelayError::NotFound),
    }
}

struct ProgramIdlRequest {
    program: String,
}

fn parse_program_idl_request(path: &str) -> Result<ProgramIdlRequest, RelayError> {
    let mut parts = path.trim_matches('/').split('/');
    match (
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
    ) {
        (Some("cosign"), Some("v1"), Some("programs"), Some(program), Some("idl"))
            if parts.next().is_none() =>
        {
            Ok(ProgramIdlRequest {
                program: program.to_string(),
            })
        }
        _ => Err(RelayError::NotFound),
    }
}

/// Matches `cosign/v1/mints/<account>` exactly (4 path segments); any other
/// shape returns `None` so it falls through to other route matchers instead
/// of being mistaken for a mint-metadata request.
fn parse_mint_metadata_request(path: &str) -> Option<String> {
    let mut parts = path.trim_matches('/').split('/');
    match (parts.next(), parts.next(), parts.next(), parts.next()) {
        (Some("cosign"), Some("v1"), Some("mints"), Some(account)) if parts.next().is_none() => {
            Some(account.to_string())
        }
        _ => None,
    }
}

fn parse_member_squads_request(path: &str) -> Result<MemberSquadsRequest, RelayError> {
    let mut parts = path.trim_matches('/').split('/');
    match (
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
    ) {
        (Some("cosign"), Some("v1"), Some("members"), Some(member), Some("squads"))
            if parts.next().is_none() =>
        {
            Ok(MemberSquadsRequest {
                member: member
                    .parse()
                    .map_err(|_| RelayError::BadRequest("invalid member address".into()))?,
            })
        }
        _ => Err(RelayError::NotFound),
    }
}

fn parse_squad_proposals_request(
    path: &str,
    query: Option<&str>,
) -> Result<SquadProposalsRequest, RelayError> {
    let mut parts = path.trim_matches('/').split('/');
    match (
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
    ) {
        (Some("cosign"), Some("v1"), Some("squads"), Some(squad), Some("proposals"))
            if parts.next().is_none() =>
        {
            let from_index = required_query_u64(query, "from")?;
            let to_index = required_query_u64(query, "to")?;
            if from_index == 0 || to_index == 0 || from_index > to_index {
                return Err(RelayError::BadRequest("invalid proposal range".into()));
            }
            if to_index - from_index + 1 > MAX_PROPOSAL_RANGE {
                return Err(RelayError::BadRequest("proposal range is too large".into()));
            }
            Ok(SquadProposalsRequest {
                squad: squad
                    .parse()
                    .map_err(|_| RelayError::BadRequest("invalid squad address".into()))?,
                from_index,
                to_index,
            })
        }
        _ => Err(RelayError::NotFound),
    }
}

fn parse_squad_proposal_request(path: &str) -> Result<SquadProposalRequest, RelayError> {
    let mut parts = path.trim_matches('/').split('/');
    match (
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
    ) {
        (
            Some("cosign"),
            Some("v1"),
            Some("squads"),
            Some(squad),
            Some("proposals"),
            Some(index),
        ) if parts.next().is_none() => Ok(SquadProposalRequest {
            squad: squad
                .parse()
                .map_err(|_| RelayError::BadRequest("invalid squad address".into()))?,
            transaction_index: index
                .parse()
                .map_err(|_| RelayError::BadRequest("invalid transaction index".into()))?,
        }),
        _ => Err(RelayError::NotFound),
    }
}

fn parse_squad_detail_request(path: &str) -> Result<SquadDetailRequest, RelayError> {
    let mut parts = path.trim_matches('/').split('/');
    match (parts.next(), parts.next(), parts.next(), parts.next()) {
        (Some("cosign"), Some("v1"), Some("squads"), Some(squad)) if parts.next().is_none() => {
            Ok(SquadDetailRequest {
                squad: squad
                    .parse()
                    .map_err(|_| RelayError::BadRequest("invalid squad address".into()))?,
            })
        }
        _ => Err(RelayError::NotFound),
    }
}

fn parse_account_activity_request(
    path: &str,
    query: Option<&str>,
) -> Result<AccountActivityRequest, RelayError> {
    let mut parts = path.trim_matches('/').split('/');
    match (
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
    ) {
        (Some("cosign"), Some("v1"), Some("accounts"), Some(address), Some("activity"))
            if parts.next().is_none() =>
        {
            let before = optional_query_value(query, "before")
                .map(|value| {
                    value
                        .parse()
                        .map_err(|_| RelayError::BadRequest("invalid before signature".into()))
                })
                .transpose()?;
            let limit = optional_query_u32(query, "limit")?.unwrap_or(DEFAULT_ACTIVITY_LIMIT);
            if limit == 0 {
                return Err(RelayError::BadRequest(
                    "activity limit must be greater than zero".into(),
                ));
            }
            Ok(AccountActivityRequest {
                address: address
                    .parse()
                    .map_err(|_| RelayError::BadRequest("invalid account address".into()))?,
                before,
                limit: limit.min(MAX_ACTIVITY_LIMIT),
            })
        }
        _ => Err(RelayError::NotFound),
    }
}

fn required_query_u64(query: Option<&str>, key: &str) -> Result<u64, RelayError> {
    optional_query_value(query, key)
        .ok_or_else(|| RelayError::BadRequest(format!("missing {key} query parameter")))?
        .parse()
        .map_err(|_| RelayError::BadRequest(format!("invalid {key} query parameter")))
}

fn optional_query_u32(query: Option<&str>, key: &str) -> Result<Option<u32>, RelayError> {
    optional_query_value(query, key)
        .map(|value| {
            value
                .parse()
                .map_err(|_| RelayError::BadRequest(format!("invalid {key} query parameter")))
        })
        .transpose()
}

fn optional_query_value(query: Option<&str>, key: &str) -> Option<String> {
    query.and_then(|query| {
        form_urlencoded::parse(query.as_bytes())
            .find_map(|(name, value)| (name == key).then(|| value.into_owned()))
    })
}

fn parse_inspection_request(
    path: &str,
    query: Option<&str>,
) -> Result<InspectionRequest, RelayError> {
    match parse_proposal_inspection_request(path, query) {
        Ok(request) => Ok(InspectionRequest::Proposal(request)),
        Err(RelayError::NotFound) => {
            parse_transaction_inspection_request(path, query).map(InspectionRequest::Transaction)
        }
        Err(error) => Err(error),
    }
}

fn read_request(
    stream: &mut impl Read,
    max_body_bytes: usize,
) -> Result<Option<HttpRequest>, RelayError> {
    let mut headers = Vec::new();
    let mut byte = [0_u8; 1];

    while !headers.ends_with(b"\r\n\r\n") {
        let read = stream.read(&mut byte)?;
        if read == 0 {
            return Ok(None);
        }
        headers.push(byte[0]);
        if headers.len() > MAX_REQUEST_HEADERS_BYTES {
            return Err(RelayError::BadRequest(
                "HTTP request headers are too large".into(),
            ));
        }
    }

    let header_text = std::str::from_utf8(&headers)
        .map_err(|_| RelayError::BadRequest("HTTP request is not UTF-8".into()))?;
    let request_line = header_text
        .lines()
        .next()
        .ok_or_else(|| RelayError::BadRequest("missing HTTP request line".into()))?;
    let mut request_parts = request_line.split_whitespace();
    let method = request_parts
        .next()
        .ok_or_else(|| RelayError::BadRequest("missing HTTP method".into()))?;
    let target = request_parts
        .next()
        .ok_or_else(|| RelayError::BadRequest("missing HTTP target".into()))?;

    let (path, query) = split_target(target);
    let content_length = content_length(header_text)?;
    if content_length > max_body_bytes {
        return Err(RelayError::BadRequest(
            "HTTP request body is too large".into(),
        ));
    }

    let mut body = vec![0_u8; content_length];
    if content_length > 0 {
        stream.read_exact(&mut body)?;
    }

    let host = header_value(header_text, "host");
    let websocket_key = if is_websocket_upgrade(header_text) {
        header_value(header_text, "sec-websocket-key")
    } else {
        None
    };
    let if_none_match = header_value(header_text, "if-none-match");

    Ok(Some(HttpRequest {
        method: method.to_string(),
        path,
        query,
        body,
        host,
        websocket_key,
        if_none_match,
    }))
}

fn header_value(headers: &str, name: &str) -> Option<String> {
    headers.lines().find_map(|line| {
        let (key, value) = line.split_once(':')?;
        if key.trim().eq_ignore_ascii_case(name) {
            Some(value.trim().to_string())
        } else {
            None
        }
    })
}

fn is_websocket_upgrade(headers: &str) -> bool {
    header_value(headers, "upgrade")
        .map(|value| value.eq_ignore_ascii_case("websocket"))
        .unwrap_or(false)
}

/// The WebSocket form of an http(s) RPC URL (same host, path, query/api-key).
fn derive_ws_url(rpc_url: &str) -> Option<String> {
    if let Some(rest) = rpc_url.strip_prefix("https://") {
        Some(format!("wss://{rest}"))
    } else if let Some(rest) = rpc_url.strip_prefix("http://") {
        Some(format!("ws://{rest}"))
    } else if rpc_url.starts_with("wss://") || rpc_url.starts_with("ws://") {
        Some(rpc_url.to_string())
    } else {
        None
    }
}

/// The relay's own advertised WebSocket endpoint (its `/ws` proxy).
fn relay_ws_url(host: &str) -> String {
    let scheme = if host.starts_with("localhost")
        || host.starts_with("127.0.0.1")
        || host.starts_with("[::1]")
    {
        "ws"
    } else {
        "wss"
    };
    format!("{scheme}://{host}/ws")
}

/// Complete the WebSocket handshake and hand the connection to its own thread,
/// proxying frames to/from the upstream Solana WebSocket. The upstream's
/// credentials stay server-side. Runs off the main accept loop so a long-lived
/// socket never blocks other requests.
fn start_ws_proxy(
    mut stream: TcpStream,
    websocket_key: &str,
    config: &RelayConfig,
    rate: Result<(), RelayError>,
) -> Result<(), RelayError> {
    if let Err(error) = rate {
        return write_response(&mut stream, relay_error_response(error, None));
    }
    let Some(upstream) = config.web_socket_url.clone() else {
        return write_response(
            &mut stream,
            relay_error_response(
                RelayError::BadRequest("relay WebSocket proxy is not configured".into()),
                None,
            ),
        );
    };

    // Bound concurrent proxies: they are long-lived and run on their own detached
    // threads, so without a cap held-open /ws connections would grow without bound.
    if ACTIVE_WS_PROXIES.fetch_add(1, Ordering::Relaxed) >= MAX_WS_PROXIES {
        ACTIVE_WS_PROXIES.fetch_sub(1, Ordering::Relaxed);
        return write_response(
            &mut stream,
            relay_error_response(
                RelayError::RateLimited("relay WebSocket proxy is at capacity".into()),
                None,
            ),
        );
    }
    let proxy_guard = WsProxyGuard;

    let accept = tungstenite::handshake::derive_accept_key(websocket_key.as_bytes());
    let handshake = format!(
        "HTTP/1.1 101 Switching Protocols\r\n\
         Upgrade: websocket\r\nConnection: Upgrade\r\n\
         Sec-WebSocket-Accept: {accept}\r\n\r\n"
    );
    stream.set_read_timeout(None).ok();
    stream.write_all(handshake.as_bytes())?;
    stream.flush()?;

    std::thread::spawn(move || {
        // Held for the proxy's whole lifetime; decrements ACTIVE_WS_PROXIES on exit.
        let _proxy_guard = proxy_guard;
        if let Err(error) = ws_pump(stream, &upstream) {
            eprintln!("relay ws proxy ended: {error}");
        }
    });
    Ok(())
}

/// Solana JSON-RPC PubSub methods the relay forwards client→upstream. The HTTP
/// passthrough allowlist is for HTTP methods (getAccountInfo, …); the WebSocket
/// surface speaks a disjoint set of subscribe/unsubscribe methods, so it has its
/// own allowlist. Anything else (writes, unknown methods, malformed frames) is
/// rejected and the socket is closed.
const ALLOWED_WS_METHODS: &[&str] = &[
    "accountSubscribe",
    "accountUnsubscribe",
    "programSubscribe",
    "programUnsubscribe",
    "signatureSubscribe",
    "signatureUnsubscribe",
    "slotSubscribe",
    "slotUnsubscribe",
    "slotsUpdatesSubscribe",
    "slotsUpdatesUnsubscribe",
    "logsSubscribe",
    "logsUnsubscribe",
    "rootSubscribe",
    "rootUnsubscribe",
    "blockSubscribe",
    "blockUnsubscribe",
];

fn ws_method_allowed(text: &str) -> bool {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(text) else {
        return false;
    };
    let Some(method) = value.get("method").and_then(|method| method.as_str()) else {
        return false;
    };
    ALLOWED_WS_METHODS.contains(&method)
}

/// Per-connection cap on client→upstream frames, so a single socket can't flood
/// the upstream with subscriptions even within the allowlist.
struct WsRate {
    count: u32,
    window_start: Instant,
}

impl WsRate {
    const WINDOW: Duration = Duration::from_secs(10);
    const MAX_PER_WINDOW: u32 = 120;

    fn new() -> Self {
        Self {
            count: 0,
            window_start: Instant::now(),
        }
    }

    fn allow(&mut self) -> bool {
        if self.window_start.elapsed() > Self::WINDOW {
            self.window_start = Instant::now();
            self.count = 0;
        }
        self.count += 1;
        self.count <= Self::MAX_PER_WINDOW
    }
}

fn ws_pump(app_stream: TcpStream, upstream_url: &str) -> Result<(), Box<dyn Error>> {
    let poll = Duration::from_millis(50);
    app_stream.set_read_timeout(Some(poll))?;
    let mut app = tungstenite::WebSocket::from_raw_socket(
        app_stream,
        tungstenite::protocol::Role::Server,
        None,
    );
    let (mut upstream, _response) = tungstenite::connect(upstream_url)?;
    set_ws_read_timeout(&mut upstream, poll);

    let mut rate = WsRate::new();
    loop {
        if !ws_pump_once(&mut app, &mut upstream, true, &mut rate)? {
            break;
        }
        if !ws_pump_once(&mut upstream, &mut app, false, &mut rate)? {
            break;
        }
    }
    Ok(())
}

/// Move one frame from `src` to `dst`. Returns false when the connection should
/// close. Client→upstream frames (`from_client`) are method-filtered, binary is
/// rejected, and a per-connection rate cap applies. Read timeouts (the idle
/// poll) are not errors.
fn ws_pump_once<S, D>(
    src: &mut tungstenite::WebSocket<S>,
    dst: &mut tungstenite::WebSocket<D>,
    from_client: bool,
    rate: &mut WsRate,
) -> Result<bool, Box<dyn Error>>
where
    S: std::io::Read + std::io::Write,
    D: std::io::Read + std::io::Write,
{
    match src.read() {
        Ok(message) => {
            if message.is_close() {
                let _ = dst.send(message);
                return Ok(false);
            }
            if from_client {
                // Solana PubSub is text JSON; drop binary outright.
                if !message.is_text() {
                    return Ok(true);
                }
                if !rate.allow() {
                    return Ok(false);
                }
                let text = message.to_text().unwrap_or_default();
                if !ws_method_allowed(text) {
                    return Ok(false);
                }
                dst.send(message)?;
            } else if message.is_text() || message.is_binary() {
                dst.send(message)?;
            }
        }
        Err(tungstenite::Error::Io(error))
            if matches!(
                error.kind(),
                std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
            ) => {}
        Err(_) => return Ok(false),
    }
    Ok(true)
}

fn set_ws_read_timeout(
    ws: &mut tungstenite::WebSocket<tungstenite::stream::MaybeTlsStream<TcpStream>>,
    timeout: Duration,
) {
    match ws.get_mut() {
        tungstenite::stream::MaybeTlsStream::Plain(stream) => {
            stream.set_read_timeout(Some(timeout)).ok();
        }
        tungstenite::stream::MaybeTlsStream::NativeTls(stream) => {
            stream.get_ref().set_read_timeout(Some(timeout)).ok();
        }
        _ => {}
    }
}

fn content_length(header_text: &str) -> Result<usize, RelayError> {
    header_text
        .lines()
        .skip(1)
        .find_map(|line| {
            let (name, value) = line.split_once(':')?;
            name.eq_ignore_ascii_case("content-length")
                .then_some(value.trim())
        })
        .map(|value| {
            value
                .parse()
                .map_err(|_| RelayError::BadRequest("invalid content-length".into()))
        })
        .transpose()
        .map(|value| value.unwrap_or(0))
}

fn split_target(target: &str) -> (String, Option<String>) {
    match target.split_once('?') {
        Some((path, query)) => (path.to_string(), Some(query.to_string())),
        None => (target.to_string(), None),
    }
}

struct HttpResponse {
    status: u16,
    reason: &'static str,
    content_type: &'static str,
    body: Vec<u8>,
    /// Additional response headers (e.g. Cache-Control, ETag) emitted after
    /// Content-Type. Empty for responses that only need the fixed header block.
    extra_headers: Vec<(&'static str, String)>,
}

fn health_response() -> HttpResponse {
    json_response(
        200,
        json!({
            "ok": true,
            "service": "cosign-relay"
        }),
    )
}

fn capabilities_response(config: &RelayConfig, host: Option<&str>) -> HttpResponse {
    // Advertise the relay's own /ws proxy (not the upstream) when an upstream WS
    // is configured, so the app connects to the relay and the credentials stay
    // server-side.
    let web_socket_url = host
        .filter(|_| config.web_socket_url.is_some())
        .map(relay_ws_url);
    json_response(
        200,
        json!({
            "ok": true,
            "service": "cosign-relay",
            "apiVersion": "cosign/v1",
            "capabilities": config.capabilities(),
            "webSocketURL": web_socket_url,
            "explorerRPCURL": config.explorer_rpc_url
        }),
    )
}

fn prices_response(query: Option<&str>) -> HttpResponse {
    let mints = parse_price_ids(query);
    let (prices, changes) = fetch_jupiter_price_data(&mints);
    json_response(
        200,
        json!({
            "kind": "prices",
            "prices": prices,
            "changes": changes,
        }),
    )
}

fn parse_price_ids(query: Option<&str>) -> Vec<String> {
    let Some(query) = query else {
        return Vec::new();
    };
    query
        .split('&')
        .find_map(|pair| pair.strip_prefix("ids="))
        .map(|ids| {
            ids.split(',')
                .filter(|id| !id.is_empty())
                .map(ToString::to_string)
                .collect()
        })
        .unwrap_or_default()
}

/// Per-mint USD price and 24h change from Jupiter, as two parallel maps. Mints
/// without data (and any fetch failure) are simply absent — the app renders an
/// em-dash, never a fake value. `changes` is a percentage (e.g. -1.55).
fn fetch_jupiter_price_data(
    mints: &[String],
) -> (
    serde_json::Map<String, Value>,
    serde_json::Map<String, Value>,
) {
    let mut prices = serde_json::Map::new();
    let mut changes = serde_json::Map::new();
    if mints.is_empty() {
        return (prices, changes);
    }
    let url = format!("https://lite-api.jup.ag/price/v3?ids={}", mints.join(","));
    let Ok(response) = ureq::get(&url).call() else {
        return (prices, changes);
    };
    let Ok(body) = response.into_json::<Value>() else {
        return (prices, changes);
    };
    for mint in mints {
        if let Some(price) = jupiter_usd_price(&body, mint) {
            prices.insert(mint.clone(), json!(price));
        }
        if let Some(change) = jupiter_price_change_24h(&body, mint) {
            changes.insert(mint.clone(), json!(change));
        }
    }
    (prices, changes)
}

/// Jupiter Price API v3 24h change percentage: `{ "<mint>": { "priceChange24h": <number> } }`.
fn jupiter_price_change_24h(body: &Value, mint: &str) -> Option<f64> {
    body.get(mint)
        .and_then(|entry| entry.get("priceChange24h"))
        .and_then(Value::as_f64)
}

fn jupiter_usd_price(body: &Value, mint: &str) -> Option<f64> {
    // Price API v3: { "<mint>": { "usdPrice": <number> } }
    if let Some(price) = body
        .get(mint)
        .and_then(|entry| entry.get("usdPrice"))
        .and_then(Value::as_f64)
    {
        return Some(price);
    }
    // v2 fallback: { "data": { "<mint>": { "price": "<string|number>" } } }
    let price = body
        .get("data")
        .and_then(|data| data.get(mint))?
        .get("price")?;
    price
        .as_f64()
        .or_else(|| price.as_str().and_then(|value| value.parse().ok()))
}

// TTL-cached latest-release data. Populated on first request and refreshed after
// the TTL expires. Avoids hitting the unauthenticated GitHub API on every page load
// (rate limit: 60 req/hr/IP). The cache is process-global and initialised lazily.
static RELEASE_CACHE: OnceLock<Mutex<Option<(Value, Instant)>>> = OnceLock::new();
const RELEASE_CACHE_TTL: Duration = Duration::from_secs(7 * 60);

fn release_response() -> HttpResponse {
    let cache = RELEASE_CACHE.get_or_init(|| Mutex::new(None));
    {
        let guard = cache.lock().unwrap_or_else(|e| e.into_inner());
        if let Some((ref cached, fetched_at)) = *guard
            && fetched_at.elapsed() < RELEASE_CACHE_TTL
        {
            return json_response(200, cached.clone());
        }
    }
    match fetch_release_data() {
        Ok(release_json) => {
            let mut guard = cache.lock().unwrap_or_else(|e| e.into_inner());
            *guard = Some((release_json.clone(), Instant::now()));
            json_response(200, release_json)
        }
        Err(_) => json_response(502, json!({"kind": "release", "error": "unavailable"})),
    }
}

/// Fetches the latest tagged GitHub release for hackshare/cosign, downloads the
/// BuildClaim.json release asset, and returns a JSON blob with version/tag/commit/
/// fingerprint fields. The fingerprint is sha256(raw BuildClaim.json bytes), which
/// the app computes locally from the same asset to verify the build.
fn fetch_release_data() -> Result<Value, Box<dyn std::error::Error + Send + Sync>> {
    let client = reqwest::blocking::Client::builder()
        .no_proxy()
        .timeout(Duration::from_secs(10))
        .build()?;

    let response = client
        .get("https://api.github.com/repos/hackshare/cosign/releases/latest")
        .header("User-Agent", "cosign-relay")
        .header("Accept", "application/vnd.github+json")
        .send()?;

    if !response.status().is_success() {
        return Err(format!("GitHub API returned {}", response.status().as_u16()).into());
    }

    let release: Value = response.json()?;
    let html_url = release["html_url"]
        .as_str()
        .ok_or("missing html_url")?
        .to_owned();

    let assets = release["assets"].as_array().ok_or("missing assets")?;
    let asset = assets
        .iter()
        .find(|a| a["name"].as_str() == Some("BuildClaim.json"))
        .ok_or("BuildClaim.json asset not found")?;
    let download_url = asset["browser_download_url"]
        .as_str()
        .ok_or("missing browser_download_url")?
        .to_owned();

    let bytes_response = client
        .get(&download_url)
        .header("User-Agent", "cosign-relay")
        .send()?;
    let bytes = bytes_response.bytes()?;

    // Fingerprint over the exact published bytes — the app verifier hashes the
    // same asset so both sides produce identical hex without re-serialising.
    let fingerprint: String = Sha256::digest(&bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();

    let claim: Value = serde_json::from_slice(&bytes)?;
    let version = claim["version"]
        .as_str()
        .ok_or("missing version")?
        .to_owned();
    let tag = claim["tag"].as_str().ok_or("missing tag")?.to_owned();
    let commit = claim["commitSha"]
        .as_str()
        .ok_or("missing commitSha")?
        .to_owned();
    let build = claim["build"].as_str().ok_or("missing build")?.to_owned();
    let commit_short = commit[..8.min(commit.len())].to_owned();

    Ok(json!({
        "kind": "release",
        "version": version,
        "tag": tag,
        "build": build,
        "commit": commit,
        "commitShort": commit_short,
        "fingerprint": fingerprint,
        "releaseUrl": html_url,
    }))
}

fn member_squads_json_response(
    member: &Pubkey,
    squads: &[types::MultisigSummary],
    source: &str,
) -> HttpResponse {
    json_response(
        200,
        json!({
            "kind": "member_squads",
            "member": member.to_string(),
            "cluster": null,
            "source": source,
            "squads": squads.iter().map(squad_summary_json).collect::<Vec<_>>()
        }),
    )
}

fn squad_detail_json_response(squad: &types::MultisigDetail) -> HttpResponse {
    json_response(
        200,
        json!({
            "kind": "squad_detail",
            "cluster": null,
            "squad": squad_detail_json(squad)
        }),
    )
}

/// Builds the `/idl` 200 response body with `idl` embedded byte-for-byte as
/// fetched. This bypasses `Value`/`json!`, which would reserialize the IDL
/// through an unordered map and no longer match `FetchedIdl::hash`.
fn program_idl_response_body(idl: &FetchedIdl) -> Vec<u8> {
    let program = serde_json::to_string(&idl.program).unwrap_or_else(|_| "\"\"".to_string());
    let hash = serde_json::to_string(&idl.hash).unwrap_or_else(|_| "\"\"".to_string());
    let authority = serde_json::to_string(&idl.authority).unwrap_or_else(|_| "\"\"".to_string());
    format!(
        "{{\"ok\":true,\"kind\":\"program_idl\",\"program\":{program},\"idl\":{idl_raw},\"hash\":{hash},\"slot\":{slot},\"authority\":{authority}}}",
        idl_raw = idl.idl_json.get(),
        slot = idl.slot,
    )
    .into_bytes()
}

fn program_idl_json_response(idl: &FetchedIdl) -> HttpResponse {
    HttpResponse {
        status: 200,
        reason: reason_phrase(200),
        content_type: "application/json; charset=utf-8",
        body: program_idl_response_body(idl),
        extra_headers: vec![
            (
                "Cache-Control",
                format!("public, max-age={IDL_CACHE_MAX_AGE_SECS}"),
            ),
            ("ETag", format!("\"{}\"", idl.hash)),
        ],
    }
}

fn decode_registry_response() -> HttpResponse {
    let body = DECODE_REGISTRY_BUNDLE.as_bytes().to_vec();
    let etag = format!("\"{}\"", sha256_hex(&body));
    HttpResponse {
        status: 200,
        reason: reason_phrase(200),
        content_type: "application/json; charset=utf-8",
        body,
        extra_headers: vec![
            (
                "Cache-Control",
                format!("public, max-age={IDL_CACHE_MAX_AGE_SECS}"),
            ),
            ("ETag", etag),
            (
                "X-Cosign-Registry-Signature",
                DECODE_REGISTRY_SIGNATURE.trim().to_string(),
            ),
        ],
    }
}

/// Whether a request's `If-None-Match` header matches the current IDL hash,
/// i.e. the client's cached copy is still fresh and a 304 can be served
/// instead of the full body.
fn if_none_match_hits(if_none_match: Option<&str>, hash: &str) -> bool {
    if_none_match == Some(format!("\"{hash}\"").as_str())
}

fn not_modified_response(hash: &str, max_age_secs: u64) -> HttpResponse {
    HttpResponse {
        status: 304,
        reason: reason_phrase(304),
        content_type: "application/json; charset=utf-8",
        body: Vec::new(),
        extra_headers: vec![
            ("ETag", format!("\"{hash}\"")),
            ("Cache-Control", format!("public, max-age={max_age_secs}")),
        ],
    }
}

/// A `/idl` 404: no on-chain IDL exists for the requested program. Carries a
/// short Cache-Control so an edge cache or client doesn't keep re-requesting
/// (and re-triggering relay RPC calls for) a program that stays empty.
fn program_idl_not_found_response() -> HttpResponse {
    let mut response = error_response(404, ResponseFormat::Json, "not found");
    response.extra_headers.push((
        "Cache-Control",
        format!("public, max-age={}", IDL_NEGATIVE_CACHE_TTL.as_secs()),
    ));
    response
}

/// Builds the `/mints/<account>` 200 body byte-exactly, bypassing `Value`/`json!`
/// (which would re-sort keys) the same way `program_idl_response_body` does.
/// `symbol` serializes to JSON `null` when absent.
fn mint_metadata_response_body(metadata: &MintMetadata) -> Vec<u8> {
    let account = serde_json::to_string(&metadata.account).unwrap_or_else(|_| "\"\"".to_string());
    let mint = serde_json::to_string(&metadata.mint).unwrap_or_else(|_| "\"\"".to_string());
    let symbol = metadata
        .symbol
        .map(|symbol| serde_json::to_string(symbol).unwrap_or_else(|_| "null".to_string()))
        .unwrap_or_else(|| "null".to_string());
    format!(
        "{{\"kind\":\"mint_metadata\",\"account\":{account},\"mint\":{mint},\"decimals\":{decimals},\"symbol\":{symbol}}}",
        decimals = metadata.decimals,
    )
    .into_bytes()
}

/// Mint metadata (decimals + symbol) is effectively immutable on-chain, so the
/// 200 gets the same tier-2 caching as `/idl`: a long `Cache-Control` plus an
/// `ETag` derived from the body so repeated proposal opens skip the account
/// read entirely.
fn mint_metadata_json_response(metadata: &MintMetadata) -> HttpResponse {
    let body = mint_metadata_response_body(metadata);
    let etag = format!("\"{}\"", sha256_hex(&body));
    HttpResponse {
        status: 200,
        reason: reason_phrase(200),
        content_type: "application/json; charset=utf-8",
        body,
        extra_headers: vec![
            (
                "Cache-Control",
                format!("public, max-age={IDL_CACHE_MAX_AGE_SECS}"),
            ),
            ("ETag", etag),
        ],
    }
}

fn mint_metadata_not_found_response() -> HttpResponse {
    error_response(404, ResponseFormat::Json, "not found")
}

fn squad_proposals_json_response(
    request: &SquadProposalsRequest,
    proposals: &[types::ProposalSummary],
) -> HttpResponse {
    json_response(
        200,
        json!({
            "kind": "squad_proposals",
            "squad": request.squad.to_string(),
            "cluster": null,
            "range": {
                "from": request.from_index,
                "to": request.to_index
            },
            "proposals": proposals.iter().map(proposal_summary_json).collect::<Vec<_>>()
        }),
    )
}

fn squad_proposal_json_response(squad: &Pubkey, proposal: &types::ProposalDetail) -> HttpResponse {
    let instructions = decoded_proposal_instructions(proposal);
    json_response(
        200,
        json!({
            "kind": "squad_proposal",
            "squad": squad.to_string(),
            "cluster": null,
            "proposal": proposal_detail_json(proposal, &instructions)
        }),
    )
}

fn proposal_inspection_json_response(result: &ProposalInspection) -> HttpResponse {
    let instructions = decoded_proposal_instructions(&result.detail);
    json_response(
        200,
        json!({
            "kind": "squads_proposal_inspection",
            "squad": result.squad,
            "cluster": result.cluster,
            "action": inspection_action_json(&result.action),
            "simulation": simulation_json(&result.simulation),
            "proposal": proposal_detail_json(&result.detail, &instructions)
        }),
    )
}

fn proposal_inspection_html_response(result: &ProposalInspection) -> HttpResponse {
    let detail = &result.detail;
    let decoded_instructions = decoded_proposal_instructions(detail);
    let transaction_address = detail.transaction_address.as_deref().unwrap_or("Unknown");
    let cluster = result.cluster.as_deref().unwrap_or("Configured RPC");
    let instructions = decoded_instructions
        .iter()
        .map(instruction_html)
        .collect::<String>();
    let action = inspection_action_html(&result.action);
    let simulation = simulation_html(&result.simulation);

    html_response(
        200,
        format!(
            r#"<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Cosign Proposal Inspection</title>
  <style>
    body {{ color: #111; font: 16px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 32px; max-width: 860px; }}
    h1 {{ font-size: 28px; margin-bottom: 8px; }}
    section {{ border: 1px solid #ddd; border-radius: 10px; margin-top: 20px; padding: 16px; }}
    dl {{ display: grid; grid-template-columns: minmax(120px, 220px) 1fr; gap: 10px 16px; }}
    dt {{ color: #666; }}
    dd {{ margin: 0; overflow-wrap: anywhere; }}
    code {{ background: #f5f5f5; border-radius: 6px; padding: 2px 5px; }}
    .status {{ color: #8a6d00; }}
    .succeeded {{ color: #087f23; }}
    .failed {{ color: #b00020; }}
    pre {{ background: #f5f5f5; border-radius: 8px; overflow-x: auto; padding: 12px; }}
  </style>
</head>
<body>
  <h1>Cosign Proposal Inspection</h1>
  {action}
  {simulation}
  <section>
    <h2>Proposal</h2>
    <dl>
      <dt>Squad</dt><dd><code>{squad}</code></dd>
      <dt>Cluster</dt><dd>{cluster}</dd>
      <dt>Transaction index</dt><dd>{transaction_index}</dd>
      <dt>Status</dt><dd>{status}</dd>
      <dt>Kind</dt><dd>{kind}</dd>
      <dt>Threshold</dt><dd>{threshold}</dd>
      <dt>Votes</dt><dd>{votes_yes} approve, {votes_no} reject, {votes_cancelled} cancel</dd>
      <dt>Transaction account</dt><dd><code>{transaction_address}</code></dd>
    </dl>
  </section>
  <section>
    <h2>Instructions</h2>
    {instructions}
  </section>
</body>
</html>
"#,
            simulation = simulation,
            action = action,
            squad = escape_html(&result.squad),
            cluster = escape_html(cluster),
            transaction_index = detail.transaction_index,
            status = escape_html(&detail.status),
            kind = escape_html(&detail.kind),
            threshold = detail.threshold,
            votes_yes = detail.votes_yes,
            votes_no = detail.votes_no,
            votes_cancelled = detail.votes_cancelled,
            transaction_address = escape_html(transaction_address),
            instructions = if instructions.is_empty() {
                "<p>No decoded instructions.</p>".to_string()
            } else {
                instructions
            },
        ),
    )
}

fn account_activity_json_response(
    request: &AccountActivityRequest,
    activity: &[ActivityInspectionItem],
) -> HttpResponse {
    json_response(
        200,
        json!({
            "kind": "account_activity",
            "address": request.address.to_string(),
            "cluster": null,
            "before": request.before.map(|signature| signature.to_string()),
            "limit": request.limit,
            "activity": activity.iter().map(activity_item_json).collect::<Vec<_>>()
        }),
    )
}

fn transaction_status_json_response(
    signature: &Signature,
    status: &transactions::SignatureStatus,
) -> HttpResponse {
    json_response(
        200,
        json!({
            "kind": "transaction_status",
            "signature": signature.to_string(),
            "cluster": null,
            "status": signature_status_json(status)
        }),
    )
}

fn transaction_inspection_json_response(result: &TransactionInspection) -> HttpResponse {
    json_response(
        200,
        json!({
            "kind": "executed_transaction_inspection",
            "signature": result.signature,
            "cluster": result.cluster,
            "status": transaction_status_json(&result.status),
            "action": inspection_action_json(&result.action),
            "logs": result.logs
        }),
    )
}

fn transaction_inspection_html_response(result: &TransactionInspection) -> HttpResponse {
    html_response(
        200,
        format!(
            r#"<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Cosign Transaction Inspection</title>
  <style>
    body {{ color: #111; font: 16px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 32px; max-width: 860px; }}
    h1 {{ font-size: 28px; margin-bottom: 8px; }}
    section {{ border: 1px solid #ddd; border-radius: 10px; margin-top: 20px; padding: 16px; }}
    dl {{ display: grid; grid-template-columns: minmax(120px, 220px) 1fr; gap: 10px 16px; }}
    dt {{ color: #666; }}
    dd {{ margin: 0; overflow-wrap: anywhere; }}
    code {{ background: #f5f5f5; border-radius: 6px; padding: 2px 5px; }}
    pre {{ background: #f5f5f5; border-radius: 8px; overflow-x: auto; padding: 12px; }}
  </style>
</head>
<body>
  <h1>Cosign Transaction Inspection</h1>
  {action}
  <section>
    <h2>Status</h2>
    <dl>
      <dt>Signature</dt><dd><code>{signature}</code></dd>
      <dt>Status</dt><dd>{status}</dd>
      <dt>Slot</dt><dd>{slot}</dd>
      <dt>Block time</dt><dd>{block_time}</dd>
      <dt>Error</dt><dd>{error}</dd>
    </dl>
  </section>
  <section>
    <h2>Logs</h2>
    {logs}
  </section>
</body>
</html>
"#,
            action = inspection_action_html(&result.action),
            signature = escape_html(&result.signature),
            status = escape_html(&result.status.status),
            slot = result
                .status
                .slot
                .map(|slot| slot.to_string())
                .unwrap_or_else(|| "Unknown".into()),
            block_time = result
                .status
                .block_time
                .map(|block_time| block_time.to_string())
                .unwrap_or_else(|| "Unknown".into()),
            error = result
                .status
                .error
                .as_ref()
                .map(|error| format!("<code>{}</code>", escape_html(error)))
                .unwrap_or_else(|| "None".into()),
            logs = if result.logs.is_empty() {
                "<p>No transaction logs.</p>".to_string()
            } else {
                format!("<pre>{}</pre>", escape_html(&result.logs.join("\n")))
            },
        ),
    )
}

fn simulation_json(simulation: &SimulationSummary) -> Value {
    json!({
        "status": simulation.status.as_str(),
        "message": simulation.message,
        "error": simulation.error,
        "logs": simulation.logs,
        "feePayer": simulation.fee_payer,
        "recentBlockhash": simulation.recent_blockhash
    })
}

fn transaction_status_json(status: &TransactionStatusSummary) -> Value {
    json!({
        "status": status.status,
        "slot": status.slot,
        "blockTime": status.block_time,
        "error": status.error
    })
}

fn signature_status_json(status: &transactions::SignatureStatus) -> Value {
    json!({
        "status": status.status,
        "slot": status.slot,
        "error": status.err
    })
}

fn inspection_action_json(action: &InspectionAction) -> Value {
    json!({
        "classification": action.classification,
        "summary": action.summary,
        "confidence": action.confidence,
        "effects": action.effects.iter().map(inspection_effect_json).collect::<Vec<_>>(),
        "warnings": action.warnings.iter().map(inspection_warning_json).collect::<Vec<_>>()
    })
}

fn inspection_effect_json(effect: &InspectionEffect) -> Value {
    json!({
        "kind": effect.kind,
        "summary": effect.summary,
        "program": effect.program,
        "asset": effect.asset,
        "amount": effect.amount,
        "source": effect.source,
        "destination": effect.destination
    })
}

fn inspection_warning_json(warning: &InspectionWarning) -> Value {
    json!({
        "severity": warning.severity,
        "code": warning.code,
        "message": warning.message
    })
}

fn inspection_action_html(action: &InspectionAction) -> String {
    let effects = if action.effects.is_empty() {
        "<p>No known effects.</p>".to_string()
    } else {
        action
            .effects
            .iter()
            .map(|effect| format!("<li>{}</li>", escape_html(&effect.summary)))
            .collect::<Vec<_>>()
            .join("")
    };
    let warnings = if action.warnings.is_empty() {
        "None".to_string()
    } else {
        action
            .warnings
            .iter()
            .map(|warning| escape_html(&warning.message))
            .collect::<Vec<_>>()
            .join("<br>")
    };

    format!(
        r#"<section>
    <h2>Action</h2>
    <dl>
      <dt>Classification</dt><dd>{classification}</dd>
      <dt>Summary</dt><dd>{summary}</dd>
      <dt>Confidence</dt><dd>{confidence}</dd>
      <dt>Warnings</dt><dd>{warnings}</dd>
    </dl>
    <h3>Effects</h3>
    <ul>{effects}</ul>
  </section>"#,
        classification = escape_html(&action.classification),
        summary = escape_html(&action.summary),
        confidence = escape_html(&action.confidence),
        warnings = warnings,
        effects = effects,
    )
}

fn simulation_html(simulation: &SimulationSummary) -> String {
    let status = simulation.status.as_str();
    let error = simulation
        .error
        .as_ref()
        .map(|error| {
            format!(
                r#"<dt>Error</dt><dd><code>{}</code></dd>"#,
                escape_html(error)
            )
        })
        .unwrap_or_default();
    let fee_payer = simulation
        .fee_payer
        .as_ref()
        .map(|fee_payer| {
            format!(
                r#"<dt>Fee payer</dt><dd><code>{}</code></dd>"#,
                escape_html(fee_payer)
            )
        })
        .unwrap_or_default();
    let recent_blockhash = simulation
        .recent_blockhash
        .as_ref()
        .map(|recent_blockhash| {
            format!(
                r#"<dt>Recent blockhash</dt><dd><code>{}</code></dd>"#,
                escape_html(recent_blockhash)
            )
        })
        .unwrap_or_default();
    let logs = if simulation.logs.is_empty() {
        "<p>No simulation logs.</p>".to_string()
    } else {
        format!("<pre>{}</pre>", escape_html(&simulation.logs.join("\n")))
    };

    format!(
        r#"<section>
    <h2>Simulation</h2>
    <dl>
      <dt>Status</dt><dd class="{status_class}">{status}</dd>
      <dt>Message</dt><dd>{message}</dd>
      {error}
      {fee_payer}
      {recent_blockhash}
    </dl>
    <h3>Logs</h3>
    {logs}
  </section>"#,
        status_class = escape_html(status),
        status = escape_html(status),
        message = escape_html(&simulation.message),
        error = error,
        fee_payer = fee_payer,
        recent_blockhash = recent_blockhash,
        logs = logs,
    )
}

fn instruction_html(instruction: &DecodedInstruction) -> String {
    format!(
        r#"<article>
  <h3>{kind}</h3>
  <dl>
    <dt>Program</dt><dd><code>{program}</code></dd>
    <dt>Summary</dt><dd>{summary}</dd>
    <dt>Accounts</dt><dd>{accounts}</dd>
  </dl>
</article>"#,
        kind = escape_html(&instruction.kind),
        program = escape_html(&instruction.program),
        summary = escape_html(&instruction.summary),
        accounts = if instruction.accounts.is_empty() {
            "None".to_string()
        } else {
            instruction
                .accounts
                .iter()
                .map(|account| format!("<code>{}</code>", escape_html(account)))
                .collect::<Vec<_>>()
                .join("<br>")
        },
    )
}

fn proposal_detail_json(detail: &ProposalDetail, instructions: &[DecodedInstruction]) -> Value {
    json!({
        "transactionIndex": detail.transaction_index,
        "status": detail.status,
        "kind": detail.kind,
        "threshold": detail.threshold,
        "votes": {
            "approve": detail.votes_yes,
            "reject": detail.votes_no,
            "cancel": detail.votes_cancelled
        },
        "voters": {
            "approve": detail.voters_yes,
            "reject": detail.voters_no,
            "cancel": detail.voters_cancelled
        },
        "transactionAddress": detail.transaction_address,
        "accountsReferenced": detail.accounts_referenced,
        "proposer": detail.proposer,
        "createdAtUnix": detail.created_at_unix,
        "instructions": instructions.iter().map(instruction_json).collect::<Vec<_>>()
    })
}

fn squad_detail_json(detail: &types::MultisigDetail) -> Value {
    json!({
        "address": detail.address,
        "threshold": detail.threshold,
        "timeLockSeconds": detail.time_lock_seconds,
        "rentCollector": detail.rent_collector,
        "transactionIndex": detail.transaction_index,
        "staleTransactionIndex": detail.stale_transaction_index,
        "isAutonomous": detail.is_autonomous,
        "members": detail.members.iter().map(member_info_json).collect::<Vec<_>>(),
        "vaults": detail.vaults.iter().map(vault_ref_json).collect::<Vec<_>>()
    })
}

fn member_info_json(member: &types::MemberInfo) -> Value {
    json!({
        "pubkey": member.pubkey,
        "canInitiate": member.can_initiate,
        "canVote": member.can_vote,
        "canExecute": member.can_execute
    })
}

fn vault_ref_json(vault: &types::VaultRef) -> Value {
    json!({
        "index": vault.index,
        "address": vault.address
    })
}

fn squad_summary_json(summary: &types::MultisigSummary) -> Value {
    json!({
        "address": summary.address,
        "threshold": summary.threshold,
        "memberCount": summary.member_count,
        "transactionIndex": summary.transaction_index,
        "staleTransactionIndex": summary.stale_transaction_index
    })
}

fn proposal_summary_json(summary: &types::ProposalSummary) -> Value {
    json!({
        "transactionIndex": summary.transaction_index,
        "status": summary.status,
        "votesYes": summary.votes_yes,
        "votesNo": summary.votes_no,
        "votesCancelled": summary.votes_cancelled,
        "threshold": summary.threshold
    })
}

fn activity_item_json(item: &ActivityInspectionItem) -> Value {
    json!({
        "signature": item.item.signature,
        "slot": item.item.slot,
        "timestampUnix": item.item.timestamp_unix,
        "kind": item.item.kind,
        "error": item.item.error,
        "action": item.action.as_ref().map(inspection_action_json)
    })
}

fn instruction_json(instruction: &DecodedInstruction) -> Value {
    json!({
        "program": instruction.program,
        "kind": instruction.kind,
        "summary": instruction.summary,
        "accounts": instruction.accounts,
        "rawDataHex": instruction.raw_data_hex,
        "configAction": instruction.config_action.as_ref().map(config_action_json)
    })
}

fn config_action_json(info: &ConfigActionInfo) -> Value {
    json!({
        "memberKey": info.member_key,
        "canInitiate": info.can_initiate,
        "canVote": info.can_vote,
        "canExecute": info.can_execute,
        "newThreshold": info.new_threshold,
        "newTimeLockSeconds": info.new_time_lock,
        "newRentCollector": info.new_rent_collector,
        "clearsRentCollector": info.clears_rent_collector
    })
}

fn relay_error_response(error: RelayError, query: Option<&str>) -> HttpResponse {
    let format = InspectionQuery::parse(query).format;
    let (status, message) = relay_error_status_message(error);
    error_response(status, format, &message)
}

fn relay_json_error_response(error: RelayError) -> HttpResponse {
    let (status, message) = relay_error_status_message(error);
    error_response(status, ResponseFormat::Json, &message)
}

fn relay_error_status_message(error: RelayError) -> (u16, String) {
    match error {
        RelayError::BadRequest(message) => (400, message),
        RelayError::Forbidden(message) => (403, message),
        RelayError::NotFound => (404, "not found".into()),
        RelayError::RateLimited(message) => (429, message),
        RelayError::Rpc(message) => (502, message),
        RelayError::Io(message) => (500, message.to_string()),
    }
}

fn error_response(status: u16, format: ResponseFormat, message: &str) -> HttpResponse {
    match format {
        ResponseFormat::Html => html_response(
            status,
            format!(
                "<!doctype html><title>Cosign Relay Error</title><h1>Cosign Relay Error</h1><p>{}</p>",
                escape_html(message)
            ),
        ),
        ResponseFormat::Json => json_response(
            status,
            json!({
                "ok": false,
                "error": {
                    "code": error_code(status),
                    "message": message
                }
            }),
        ),
    }
}

fn html_response(status: u16, body: String) -> HttpResponse {
    HttpResponse {
        status,
        reason: reason_phrase(status),
        content_type: "text/html; charset=utf-8",
        body: body.into_bytes(),
        extra_headers: Vec::new(),
    }
}

fn json_response(status: u16, body: Value) -> HttpResponse {
    HttpResponse {
        status,
        reason: reason_phrase(status),
        content_type: "application/json; charset=utf-8",
        body: serde_json::to_vec_pretty(&body).unwrap_or_else(|_| b"{}".to_vec()),
        extra_headers: Vec::new(),
    }
}

fn redirect_response(location: String) -> HttpResponse {
    HttpResponse {
        status: 301,
        reason: reason_phrase(301),
        content_type: "text/plain; charset=utf-8",
        body: location.into_bytes(),
        extra_headers: Vec::new(),
    }
}

fn is_landing_path(path: &str) -> bool {
    matches!(path, "/" | "/privacy" | "/favicon.svg") || path.starts_with("/assets/")
}

fn write_response(stream: &mut impl Write, response: HttpResponse) -> Result<(), RelayError> {
    // A 3xx response carries its Location target in `body` (see redirect_response).
    // No non-redirect response uses a 3xx status, so this branch is unambiguous.
    if matches!(response.status, 301 | 302 | 307 | 308) {
        let location = String::from_utf8_lossy(&response.body);
        write!(
            stream,
            "HTTP/1.1 {} {}\r\nLocation: {}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
            response.status, response.reason, location
        )?;
        stream.flush()?;
        return Ok(());
    }
    write!(
        stream,
        "HTTP/1.1 {} {}\r\nContent-Type: {}\r\nContent-Length: {}\r\nConnection: close\r\n",
        response.status,
        response.reason,
        response.content_type,
        response.body.len()
    )?;
    for (name, value) in &response.extra_headers {
        write!(stream, "{name}: {value}\r\n")?;
    }
    write!(stream, "\r\n")?;
    stream.write_all(&response.body)?;
    stream.flush()?;
    Ok(())
}

fn reason_phrase(status: u16) -> &'static str {
    match status {
        200 => "OK",
        301 => "Moved Permanently",
        304 => "Not Modified",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        _ => "OK",
    }
}

fn error_code(status: u16) -> &'static str {
    match status {
        400 => "bad_request",
        403 => "forbidden",
        404 => "not_found",
        405 => "method_not_allowed",
        429 => "rate_limited",
        502 => "upstream_rpc_error",
        _ => "relay_error",
    }
}

fn escape_html(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

fn load_env_files() {
    if let Ok(path) = env::var("COSIGN_ENV_FILE") {
        let _ = dotenvy::from_path(path);
        return;
    }

    let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("core crate has repository parent")
        .to_path_buf();
    let _ = dotenvy::from_path(repo_root.join(".env"));
    let _ = dotenvy::from_path(repo_root.join(".env.devnet"));
}

#[cfg(test)]
mod tests {
    use super::*;
    use solana_sdk::{
        hash::Hash,
        signature::{Keypair, Signer},
        system_instruction,
    };

    fn build_idl_account_bytes(authority: &Pubkey, json: &str) -> Vec<u8> {
        use flate2::{Compression, write::ZlibEncoder};
        use std::io::Write as _;

        let mut encoder = ZlibEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(json.as_bytes()).unwrap();
        let compressed = encoder.finish().unwrap();

        let mut data = vec![0u8; 8]; // account discriminator (ignored on read)
        data.extend_from_slice(authority.as_ref()); // 32-byte authority
        data.extend_from_slice(&(compressed.len() as u32).to_le_bytes()); // data_len
        data.extend_from_slice(&compressed);
        // Over-allocate trailing zeros the way a real IDL account is padded.
        data.extend_from_slice(&[0u8; 64]);
        data
    }

    #[test]
    fn parses_idl_account_roundtrip() {
        let authority = Pubkey::new_unique();
        let json = r#"{"version":"0.1.0","name":"demo","instructions":[]}"#;
        let bytes = build_idl_account_bytes(&authority, json);

        let parsed = parse_idl_account(&bytes).expect("parse");

        assert_eq!(parsed.authority, authority);
        assert_eq!(parsed.idl_json, json.as_bytes());
    }

    #[test]
    fn rejects_idl_account_too_short() {
        let bytes = vec![0u8; 20];
        assert!(matches!(
            parse_idl_account(&bytes),
            Err(RelayError::NotFound)
        ));
    }

    #[test]
    fn derives_idl_address_deterministically() {
        let program: Pubkey = "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc"
            .parse()
            .unwrap();

        let first = derive_idl_address(&program).expect("address");
        let second = derive_idl_address(&program).expect("address");

        assert_eq!(first, second);
        assert_ne!(first, program);
    }

    #[test]
    fn corrupt_idl_body_maps_to_rpc_error() {
        let authority = Pubkey::new_unique();
        let mut bytes = build_idl_account_bytes(&authority, r#"{"name":"demo","instructions":[]}"#);
        let data_len = u32::from_le_bytes([bytes[40], bytes[41], bytes[42], bytes[43]]) as usize;
        for byte in bytes[44..44 + data_len].iter_mut() {
            *byte = 0xFF;
        }
        assert!(matches!(parse_idl_account(&bytes), Err(RelayError::Rpc(_))));
    }

    #[test]
    fn sha256_hex_is_stable_and_distinguishes_content() {
        assert_eq!(sha256_hex(b"a"), sha256_hex(b"a"));
        assert_ne!(sha256_hex(b"a"), sha256_hex(b"b"));
        assert_eq!(sha256_hex(b"a").len(), 64);
    }

    /// `json!`/`Value` reserialize through an unordered map, which would
    /// silently reorder an IDL's keys and desync the served body from
    /// `FetchedIdl::hash`. This exercises the full parse -> RawValue ->
    /// response-body path with a deliberately unsorted IDL and checks the
    /// served `idl` bytes are identical to what was fetched, and that they
    /// hash to exactly the value reported in `hash`.
    #[test]
    fn program_idl_response_preserves_raw_bytes_and_hash() {
        let authority = Pubkey::new_unique();
        let json = r#"{"name":"demo","zzz":1,"aaa":2,"nested":{"z":1,"a":2}}"#;
        let bytes = build_idl_account_bytes(&authority, json);
        let parsed = parse_idl_account(&bytes).expect("parse");

        let idl_json: Box<RawValue> = serde_json::from_slice(&parsed.idl_json).expect("valid json");
        let hash = sha256_hex(idl_json.get().as_bytes());
        let fetched = FetchedIdl {
            program: Pubkey::new_unique().to_string(),
            idl_json,
            hash: hash.clone(),
            slot: 42,
            authority: authority.to_string(),
        };

        let body = program_idl_response_body(&fetched);

        #[derive(serde::Deserialize)]
        struct ResponseBody {
            idl: Box<RawValue>,
            hash: String,
        }

        let decoded: ResponseBody =
            serde_json::from_slice(&body).expect("response body is valid json");

        assert_eq!(decoded.idl.get().as_bytes(), json.as_bytes());
        assert_eq!(decoded.hash, hash);
        assert_eq!(sha256_hex(decoded.idl.get().as_bytes()), decoded.hash);
    }

    #[test]
    fn if_none_match_matches_only_the_exact_quoted_hash() {
        assert!(if_none_match_hits(Some("\"abc123\""), "abc123"));
        assert!(!if_none_match_hits(Some("\"different\""), "abc123"));
        assert!(!if_none_match_hits(Some("abc123"), "abc123"));
        assert!(!if_none_match_hits(None, "abc123"));
    }

    #[test]
    fn parses_program_idl_route() {
        let program = "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc";
        let parsed = parse_program_idl_request(&format!("/cosign/v1/programs/{program}/idl"))
            .expect("parse");
        assert_eq!(parsed.program, program);
    }

    #[test]
    fn rejects_non_idl_program_route() {
        assert!(matches!(
            parse_program_idl_request("/cosign/v1/programs/abc/proposals"),
            Err(RelayError::NotFound)
        ));
    }

    fn rpc_test_config(methods: BTreeSet<String>) -> RelayConfig {
        RelayConfig {
            bind_addr: DEFAULT_BIND_ADDR.parse().expect("default bind addr"),
            rpc_url: Some("http://127.0.0.1:8899".into()),
            web_socket_url: None,
            explorer_rpc_url: None,
            rpc_allowed_methods: methods,
            rate_limits: RelayRateLimits::default(),
            landing_redirect: None,
            index_db_path: None,
        }
    }

    fn signed_send_transaction_body(payer: &Keypair) -> (Vec<u8>, Transaction) {
        let recipient = Pubkey::new_unique();
        let transaction = Transaction::new_signed_with_payer(
            &[system_instruction::transfer(&payer.pubkey(), &recipient, 1)],
            Some(&payer.pubkey()),
            &[payer],
            Hash::new_unique(),
        );
        let transaction_data = bincode::serialize(&transaction).expect("transaction");
        let encoded_transaction = BASE64_STANDARD.encode(transaction_data);
        let body = json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "sendTransaction",
            "params": [
                encoded_transaction,
                { "encoding": "base64" }
            ]
        });

        (serde_json::to_vec(&body).expect("json"), transaction)
    }

    #[test]
    fn parses_proposal_inspection_route() {
        let squad = Pubkey::new_unique();
        let parsed = parse_proposal_inspection_request(
            &format!("/cosign/v1/squads/{squad}/transactions/42/inspection"),
            Some("format=json"),
        )
        .expect("route should parse");

        assert_eq!(parsed.squad, squad);
        assert_eq!(parsed.transaction_index, 42);
        assert_eq!(parsed.query.format, ResponseFormat::Json);
    }

    #[test]
    fn parses_executed_transaction_inspection_route() {
        let signature = Signature::new_unique();
        let parsed = parse_transaction_inspection_request(
            &format!("/cosign/v1/transactions/{signature}/inspection"),
            Some("format=json"),
        )
        .expect("route should parse");

        assert_eq!(parsed.signature, signature);
        assert_eq!(parsed.query.format, ResponseFormat::Json);
    }

    #[test]
    fn parses_transaction_status_route() {
        let signature = Signature::new_unique();
        let parsed = parse_transaction_status_request(&format!(
            "/cosign/v1/transactions/{signature}/status"
        ))
        .expect("route should parse");

        assert_eq!(parsed.signature, signature);
    }

    #[test]
    fn parses_member_squads_route() {
        let member = Pubkey::new_unique();
        let parsed = parse_member_squads_request(&format!("/cosign/v1/members/{member}/squads"))
            .expect("route should parse");

        assert_eq!(parsed.member, member);
    }

    #[test]
    fn parses_squad_detail_route() {
        let squad = Pubkey::new_unique();
        let parsed = parse_squad_detail_request(&format!("/cosign/v1/squads/{squad}"))
            .expect("route should parse");

        assert_eq!(parsed.squad, squad);
    }

    #[test]
    fn parses_squad_proposals_route() {
        let squad = Pubkey::new_unique();
        let parsed = parse_squad_proposals_request(
            &format!("/cosign/v1/squads/{squad}/proposals"),
            Some("from=2&to=4"),
        )
        .expect("route should parse");

        assert_eq!(parsed.squad, squad);
        assert_eq!(parsed.from_index, 2);
        assert_eq!(parsed.to_index, 4);
    }

    #[test]
    fn rejects_large_squad_proposals_range() {
        let squad = Pubkey::new_unique();
        assert!(matches!(
            parse_squad_proposals_request(
                &format!("/cosign/v1/squads/{squad}/proposals"),
                Some("from=1&to=101"),
            ),
            Err(RelayError::BadRequest(_))
        ));
    }

    #[test]
    fn parses_squad_proposal_route() {
        let squad = Pubkey::new_unique();
        let parsed =
            parse_squad_proposal_request(&format!("/cosign/v1/squads/{squad}/proposals/7"))
                .expect("route should parse");

        assert_eq!(parsed.squad, squad);
        assert_eq!(parsed.transaction_index, 7);
    }

    #[test]
    fn parses_account_activity_route() {
        let address = Pubkey::new_unique();
        let before = Signature::new_unique();
        let parsed = parse_account_activity_request(
            &format!("/cosign/v1/accounts/{address}/activity"),
            Some(&format!("before={before}&limit=25")),
        )
        .expect("route should parse");

        assert_eq!(parsed.address, address);
        assert_eq!(parsed.before, Some(before));
        assert_eq!(parsed.limit, 25);
    }

    #[test]
    fn clamps_account_activity_limit() {
        let address = Pubkey::new_unique();
        let parsed = parse_account_activity_request(
            &format!("/cosign/v1/accounts/{address}/activity"),
            Some("limit=250"),
        )
        .expect("route should parse");

        assert_eq!(parsed.limit, MAX_ACTIVITY_LIMIT);
    }

    #[test]
    fn rejects_invalid_route() {
        assert!(matches!(
            parse_inspection_request("/simulate/accounts/foo", None),
            Err(RelayError::NotFound)
        ));
    }

    #[test]
    fn rejects_legacy_simulation_route() {
        let squad = Pubkey::new_unique();

        assert!(matches!(
            parse_inspection_request(&format!("/simulate/squads/{squad}/transactions/42"), None),
            Err(RelayError::NotFound)
        ));
    }

    #[test]
    fn reads_post_request_body() {
        let raw = b"POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 24\r\n\r\n{\"jsonrpc\":\"2.0\",\"id\":1}";
        let request = read_request(&mut &raw[..], DEFAULT_MAX_REQUEST_BODY_BYTES)
            .expect("request should parse")
            .expect("request");

        assert_eq!(request.method, "POST");
        assert_eq!(request.path, "/");
        assert_eq!(request.body, b"{\"jsonrpc\":\"2.0\",\"id\":1}");
    }

    #[test]
    fn rejects_invalid_content_length() {
        let raw = b"POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: nope\r\n\r\n{}";

        assert!(matches!(
            read_request(&mut &raw[..], DEFAULT_MAX_REQUEST_BODY_BYTES),
            Err(RelayError::BadRequest(_))
        ));
    }

    #[test]
    fn rejects_body_above_configured_limit() {
        let raw = b"POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 3\r\n\r\n{} ";

        assert!(matches!(
            read_request(&mut &raw[..], 2),
            Err(RelayError::BadRequest(_))
        ));
    }

    #[test]
    fn rate_limits_requests_by_client() {
        let mut config = rpc_test_config(default_rpc_allowed_methods());
        config.rate_limits = RelayRateLimits {
            requests_per_window: 1,
            rpc_method_requests_per_window: 100,
            send_transaction_identity_requests_per_window: 100,
            ..RelayRateLimits::default()
        };
        let mut limiter = RateLimiter::new(config.rate_limits);
        let request = HttpRequest {
            method: "GET".into(),
            path: "/_health".into(),
            query: None,
            body: Vec::new(),
            host: None,
            websocket_key: None,
            if_none_match: None,
        };
        let now = Instant::now();
        let client_ip = Some(IpAddr::from([127, 0, 0, 1]));

        limiter
            .check_request_at(client_ip, &request, None, now)
            .expect("first request should pass");
        assert!(matches!(
            limiter.check_request_at(client_ip, &request, None, now),
            Err(RelayError::RateLimited(_))
        ));
        limiter
            .check_request_at(client_ip, &request, None, now + config.rate_limits.window)
            .expect("new window should pass");
    }

    #[test]
    fn rate_limits_rpc_methods_by_client() {
        let mut config = rpc_test_config(default_rpc_allowed_methods());
        config.rate_limits = RelayRateLimits {
            requests_per_window: 100,
            rpc_method_requests_per_window: 1,
            send_transaction_identity_requests_per_window: 100,
            ..RelayRateLimits::default()
        };
        let mut limiter = RateLimiter::new(config.rate_limits);
        let request = HttpRequest {
            method: "POST".into(),
            path: "/".into(),
            query: None,
            body: br#"{"jsonrpc":"2.0","id":1,"method":"getVersion"}"#.to_vec(),
            host: None,
            websocket_key: None,
            if_none_match: None,
        };
        let now = Instant::now();
        let client_ip = Some(IpAddr::from([127, 0, 0, 1]));
        let inspection = inspect_rpc_passthrough_request(&config, &request.body)
            .expect("valid rpc passthrough body");

        limiter
            .check_request_at(client_ip, &request, Some(&inspection), now)
            .expect("first method call should pass");
        assert!(matches!(
            limiter.check_request_at(client_ip, &request, Some(&inspection), now),
            Err(RelayError::RateLimited(_))
        ));
    }

    #[test]
    fn rate_limits_send_transactions_by_identity() {
        let mut config = rpc_test_config(default_rpc_allowed_methods());
        config.rate_limits = RelayRateLimits {
            requests_per_window: 100,
            rpc_method_requests_per_window: 100,
            send_transaction_identity_requests_per_window: 1,
            ..RelayRateLimits::default()
        };
        let mut limiter = RateLimiter::new(config.rate_limits);
        let payer = Keypair::new();
        let (body, _) = signed_send_transaction_body(&payer);
        let request = HttpRequest {
            method: "POST".into(),
            path: "/".into(),
            query: None,
            body,
            host: None,
            websocket_key: None,
            if_none_match: None,
        };
        let now = Instant::now();
        let client_ip = Some(IpAddr::from([127, 0, 0, 1]));
        let inspection = inspect_rpc_passthrough_request(&config, &request.body)
            .expect("valid send transaction body");

        limiter
            .check_request_at(client_ip, &request, Some(&inspection), now)
            .expect("first transaction should pass");
        assert!(matches!(
            limiter.check_request_at(client_ip, &request, Some(&inspection), now),
            Err(RelayError::RateLimited(_))
        ));
    }

    #[test]
    fn rpc_passthrough_allows_default_methods() {
        let config = rpc_test_config(default_rpc_allowed_methods());
        let body = br#"{"jsonrpc":"2.0","id":1,"method":"getVersion"}"#;

        let inspected =
            inspect_rpc_passthrough_request(&config, body).expect("request should inspect");

        assert_eq!(inspected.methods, vec!["getVersion"]);
        assert!(inspected.submitted_transactions.is_empty());
    }

    #[test]
    fn rpc_passthrough_rejects_unknown_methods() {
        let config = rpc_test_config(default_rpc_allowed_methods());
        let body = br#"{"jsonrpc":"2.0","id":1,"method":"requestAirdrop"}"#;

        assert!(matches!(
            inspect_rpc_passthrough_request(&config, body),
            Err(RelayError::Forbidden(_))
        ));
    }

    #[test]
    fn rpc_passthrough_rejections_use_json_errors() {
        let config = rpc_test_config(default_rpc_allowed_methods());
        let request = HttpRequest {
            method: "POST".into(),
            path: "/".into(),
            query: None,
            body: br#"{"jsonrpc":"2.0","id":1,"method":"requestAirdrop"}"#.to_vec(),
            host: None,
            websocket_key: None,
            if_none_match: None,
        };

        let response = handle_request_with_client(&request, &config, None);
        let body: Value = serde_json::from_slice(&response.body).expect("json");

        assert_eq!(response.status, 403);
        assert_eq!(body["ok"], false);
        assert_eq!(body["error"]["code"], "forbidden");
        assert_eq!(
            body["error"]["message"],
            "RPC method requestAirdrop is not allowed by this relay"
        );
    }

    #[test]
    fn rpc_passthrough_can_be_explicitly_opened() {
        let config = rpc_test_config(BTreeSet::from([RPC_ALLOW_ALL_METHODS.to_string()]));
        let body = br#"{"jsonrpc":"2.0","id":1,"method":"requestAirdrop"}"#;

        let inspected =
            inspect_rpc_passthrough_request(&config, body).expect("request should inspect");

        assert_eq!(inspected.methods, vec!["requestAirdrop"]);
    }

    #[test]
    fn rpc_passthrough_identifies_submitted_transactions() {
        let payer = Keypair::new();
        let (body, transaction) = signed_send_transaction_body(&payer);
        let config = rpc_test_config(default_rpc_allowed_methods());

        let inspected =
            inspect_rpc_passthrough_request(&config, &body).expect("request should inspect");

        assert_eq!(inspected.methods, vec!["sendTransaction"]);
        let submitted = inspected
            .submitted_transactions
            .first()
            .expect("submitted transaction");
        let payer_pubkey = payer.pubkey().to_string();
        assert_eq!(submitted.signature, transaction.signatures[0].to_string());
        assert_eq!(submitted.fee_payer.as_deref(), Some(payer_pubkey.as_str()));
        assert_eq!(submitted.signers, vec![payer_pubkey]);
        assert_eq!(submitted.encoding, "base64");
    }

    #[test]
    fn submitted_transaction_log_event_is_structured() {
        let submitted = SubmittedTransactionIdentity {
            signature: "sig111".into(),
            fee_payer: Some("payer111".into()),
            signers: vec!["payer111".into(), "signer222".into()],
            encoding: "base64".into(),
        };

        let event = submitted_transaction_log_event(Some(IpAddr::from([127, 0, 0, 1])), &submitted);

        assert_eq!(event["event"], "rpc_send_transaction");
        assert_eq!(event["clientIp"], "127.0.0.1");
        assert_eq!(event["signature"], "sig111");
        assert_eq!(event["feePayer"], "payer111");
        assert_eq!(event["signers"][1], "signer222");
        assert_eq!(event["encoding"], "base64");
    }

    #[test]
    fn configured_rpc_url_is_required_for_relay_features() {
        let config = RelayConfig {
            bind_addr: DEFAULT_BIND_ADDR.parse().expect("default bind addr"),
            rpc_url: None,
            web_socket_url: None,
            explorer_rpc_url: None,
            rpc_allowed_methods: default_rpc_allowed_methods(),
            rate_limits: RelayRateLimits::default(),
            landing_redirect: None,
            index_db_path: None,
        };

        assert!(matches!(config.rpc_url(), Err(RelayError::BadRequest(_))));
        assert!(config.capabilities().is_empty());
    }

    #[test]
    fn configured_rpc_url_enables_relay_features() {
        let config = RelayConfig {
            bind_addr: DEFAULT_BIND_ADDR.parse().expect("default bind addr"),
            rpc_url: Some("http://127.0.0.1:8899".into()),
            web_socket_url: None,
            explorer_rpc_url: None,
            rpc_allowed_methods: default_rpc_allowed_methods(),
            rate_limits: RelayRateLimits::default(),
            landing_redirect: None,
            index_db_path: None,
        };

        assert_eq!(config.rpc_url().expect("rpc url"), "http://127.0.0.1:8899");
        assert!(config.capabilities().contains(&"rpc_passthrough"));
        assert!(config.capabilities().contains(&"squads_indexing"));
        assert!(config.capabilities().contains(&"squad_detail"));
        assert!(config.capabilities().contains(&"squad_proposals"));
        assert!(config.capabilities().contains(&"proposal_detail"));
        assert!(config.capabilities().contains(&"account_activity"));
        assert!(config.capabilities().contains(&"transaction_status"));
        assert!(config.capabilities().contains(&"proposal_inspection"));
        assert!(
            config
                .capabilities()
                .contains(&"executed_transaction_inspection")
        );
    }

    #[test]
    fn advertises_program_idl_capability() {
        let config = rpc_test_config(default_rpc_allowed_methods());
        assert!(config.capabilities().contains(&"program_idl"));
    }

    #[test]
    fn advertises_decode_registry_capability() {
        let config = rpc_test_config(default_rpc_allowed_methods());
        assert!(config.capabilities().contains(&"decode_registry"));
    }

    #[test]
    fn serves_decode_registry_bundle_with_cache_and_signature_headers() {
        let config = rpc_test_config(default_rpc_allowed_methods());
        let request = HttpRequest {
            method: "GET".into(),
            path: "/cosign/v1/decode-registry".into(),
            query: None,
            body: Vec::new(),
            host: None,
            websocket_key: None,
            if_none_match: None,
        };
        let response = handle_request_with_client(&request, &config, None);
        assert_eq!(response.status, 200);
        assert!(response.body.starts_with(b"{\"schema\":1"));
        let header = |name: &str| {
            response
                .extra_headers
                .iter()
                .find(|(k, _)| k.eq_ignore_ascii_case(name))
                .map(|(_, v)| v.as_str())
        };
        assert_eq!(header("Cache-Control"), Some("public, max-age=3600"));
        assert!(header("ETag").is_some());
        assert!(header("X-Cosign-Registry-Signature").is_some());
    }

    #[test]
    fn program_idl_route_rejects_invalid_program() {
        let config = rpc_test_config(default_rpc_allowed_methods());
        let request = HttpRequest {
            method: "GET".into(),
            path: "/cosign/v1/programs/not-a-pubkey/idl".into(),
            query: None,
            body: Vec::new(),
            host: None,
            websocket_key: None,
            if_none_match: None,
        };
        let response = handle_request_with_client(&request, &config, None);
        assert_eq!(response.status, 400);
    }

    #[test]
    fn insert_idl_cache_entry_evicts_expired_entries_first() {
        let mut cache: HashMap<String, (IdlCacheEntry, Instant)> = HashMap::new();
        let long_expired = Instant::now() - IDL_CACHE_TTL - Duration::from_secs(1);
        cache.insert("stale".to_string(), (IdlCacheEntry::Missing, long_expired));

        insert_idl_cache_entry(&mut cache, "fresh".to_string(), IdlCacheEntry::Missing);

        assert!(!cache.contains_key("stale"));
        assert!(cache.contains_key("fresh"));
    }

    #[test]
    fn insert_idl_cache_entry_evicts_oldest_when_at_capacity() {
        let mut cache: HashMap<String, (IdlCacheEntry, Instant)> = HashMap::new();
        let now = Instant::now();
        // All entries are well within IDL_NEGATIVE_CACHE_TTL, so none are pruned
        // as expired; only the bound-eviction path can make room.
        for i in 0..MAX_IDL_CACHE_ENTRIES {
            let fetched_at = now - Duration::from_millis((MAX_IDL_CACHE_ENTRIES - i) as u64);
            cache.insert(format!("program-{i}"), (IdlCacheEntry::Missing, fetched_at));
        }
        assert_eq!(cache.len(), MAX_IDL_CACHE_ENTRIES);

        insert_idl_cache_entry(&mut cache, "newcomer".to_string(), IdlCacheEntry::Missing);

        assert_eq!(cache.len(), MAX_IDL_CACHE_ENTRIES);
        assert!(
            !cache.contains_key("program-0"),
            "the oldest entry should have been evicted to make room"
        );
        assert!(cache.contains_key("newcomer"));
    }

    #[test]
    fn program_idl_route_serves_404_from_fresh_negative_cache_without_rpc() {
        let config = rpc_test_config(default_rpc_allowed_methods());
        let program = Pubkey::new_unique().to_string();

        let cache = IDL_CACHE.get_or_init(|| Mutex::new(HashMap::new()));
        cache
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(program.clone(), (IdlCacheEntry::Missing, Instant::now()));

        let request = HttpRequest {
            method: "GET".into(),
            path: format!("/cosign/v1/programs/{program}/idl"),
            query: None,
            body: Vec::new(),
            host: None,
            websocket_key: None,
            if_none_match: None,
        };

        // If the negative cache didn't short-circuit, resolve_program_idl would
        // try to reach the bogus RPC URL in rpc_test_config and fail with a 502
        // instead, so this also proves no RPC call was made.
        let response = handle_request_with_client(&request, &config, None);

        assert_eq!(response.status, 404);
        assert!(
            response
                .extra_headers
                .iter()
                .any(|(name, value)| *name == "Cache-Control" && value == "public, max-age=300")
        );
    }

    #[test]
    fn program_idl_route_serves_304_when_if_none_match_matches_cached_hash() {
        let config = rpc_test_config(default_rpc_allowed_methods());
        let program = Pubkey::new_unique().to_string();
        let idl_json: Box<RawValue> = serde_json::from_str(r#"{"name":"demo"}"#).unwrap();
        let hash = sha256_hex(idl_json.get().as_bytes());
        let fetched = FetchedIdl {
            program: program.clone(),
            idl_json,
            hash: hash.clone(),
            slot: 1,
            authority: Pubkey::new_unique().to_string(),
        };

        let cache = IDL_CACHE.get_or_init(|| Mutex::new(HashMap::new()));
        cache.lock().unwrap_or_else(|e| e.into_inner()).insert(
            program.clone(),
            (IdlCacheEntry::Found(fetched), Instant::now()),
        );

        let not_modified_request = HttpRequest {
            method: "GET".into(),
            path: format!("/cosign/v1/programs/{program}/idl"),
            query: None,
            body: Vec::new(),
            host: None,
            websocket_key: None,
            if_none_match: Some(format!("\"{hash}\"")),
        };
        let not_modified = handle_request_with_client(&not_modified_request, &config, None);
        assert_eq!(not_modified.status, 304);
        assert!(not_modified.body.is_empty());
        assert!(
            not_modified
                .extra_headers
                .iter()
                .any(|(name, value)| *name == "ETag" && *value == format!("\"{hash}\""))
        );

        let fresh_request = HttpRequest {
            method: "GET".into(),
            path: format!("/cosign/v1/programs/{program}/idl"),
            query: None,
            body: Vec::new(),
            host: None,
            websocket_key: None,
            if_none_match: None,
        };
        let fresh = handle_request_with_client(&fresh_request, &config, None);
        assert_eq!(fresh.status, 200);
        assert!(
            fresh
                .extra_headers
                .iter()
                .any(|(name, value)| *name == "ETag" && *value == format!("\"{hash}\""))
        );
        assert!(
            fresh
                .extra_headers
                .iter()
                .any(|(name, value)| *name == "Cache-Control" && value == "public, max-age=3600")
        );
    }

    fn mint_account_bytes(decimals: u8) -> Vec<u8> {
        // SPL Mint: COption authority(4+32) | supply u64(8) | decimals(1) | init(1) | COption freeze(4+32)
        let mut data = vec![0u8; 82];
        data[44] = decimals;
        data
    }

    fn token_account_bytes(mint: &Pubkey) -> Vec<u8> {
        // SPL Token Account: mint(32) | owner(32) | amount(8) | ... (165 total)
        let mut data = vec![0u8; 165];
        data[..32].copy_from_slice(mint.as_ref());
        data
    }

    #[test]
    fn advertises_mint_metadata_capability() {
        let config = rpc_test_config(default_rpc_allowed_methods());
        assert!(config.capabilities().contains(&"mint_metadata"));
    }

    #[test]
    fn parses_mint_account_decimals() {
        match parse_spl_account(&mint_account_bytes(6)) {
            Some(SplAccount::Mint { decimals }) => assert_eq!(decimals, 6),
            other => panic!("expected mint, got {other:?}"),
        }
    }

    #[test]
    fn parses_token_account_mint() {
        let mint = Pubkey::new_unique();
        match parse_spl_account(&token_account_bytes(&mint)) {
            Some(SplAccount::TokenAccount { mint: parsed }) => assert_eq!(parsed, mint),
            other => panic!("expected token account, got {other:?}"),
        }
    }

    #[test]
    fn rejects_non_spl_account() {
        assert!(parse_spl_account(&[0u8; 10]).is_none());
    }

    #[test]
    fn well_known_symbol_lookup() {
        assert_eq!(
            well_known_mint_symbol("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),
            Some("USDC")
        );
        assert_eq!(well_known_mint_symbol("not-a-known-mint"), None);
    }

    #[test]
    fn parses_mint_metadata_route() {
        let account = Pubkey::new_unique().to_string();
        assert_eq!(
            parse_mint_metadata_request(&format!("/cosign/v1/mints/{account}")),
            Some(account)
        );
    }

    #[test]
    fn rejects_mint_metadata_route_with_wrong_segment_count() {
        assert_eq!(parse_mint_metadata_request("/cosign/v1/mints"), None);
        assert_eq!(
            parse_mint_metadata_request("/cosign/v1/mints/abc/extra"),
            None
        );
    }

    #[test]
    fn mint_metadata_route_rejects_invalid_account() {
        let config = rpc_test_config(default_rpc_allowed_methods());
        let request = HttpRequest {
            method: "GET".into(),
            path: "/cosign/v1/mints/not-a-pubkey".into(),
            query: None,
            body: Vec::new(),
            host: None,
            websocket_key: None,
            if_none_match: None,
        };
        let response = handle_request_with_client(&request, &config, None);
        assert_eq!(response.status, 400);
    }

    #[test]
    fn mint_metadata_response_body_has_stable_field_order_and_symbol() {
        let metadata = MintMetadata {
            account: "Account11111111111111111111111111111111111".into(),
            mint: "Mint1111111111111111111111111111111111111".into(),
            decimals: 6,
            symbol: Some("USDC"),
        };
        let body = mint_metadata_response_body(&metadata);
        assert_eq!(
            std::str::from_utf8(&body).unwrap(),
            "{\"kind\":\"mint_metadata\",\"account\":\"Account11111111111111111111111111111111111\",\"mint\":\"Mint1111111111111111111111111111111111111\",\"decimals\":6,\"symbol\":\"USDC\"}"
        );
    }

    #[test]
    fn mint_metadata_response_body_null_symbol() {
        let metadata = MintMetadata {
            account: "Account11111111111111111111111111111111111".into(),
            mint: "Mint1111111111111111111111111111111111111".into(),
            decimals: 9,
            symbol: None,
        };
        let body = mint_metadata_response_body(&metadata);
        let parsed: Value = serde_json::from_slice(&body).unwrap();
        assert!(parsed["symbol"].is_null());
    }

    #[test]
    fn mint_metadata_json_response_sets_cache_and_etag_headers() {
        let metadata = MintMetadata {
            account: "Account11111111111111111111111111111111111".into(),
            mint: "Mint1111111111111111111111111111111111111".into(),
            decimals: 6,
            symbol: None,
        };
        let response = mint_metadata_json_response(&metadata);
        assert_eq!(response.status, 200);
        let hash = sha256_hex(&response.body);
        assert!(
            response
                .extra_headers
                .iter()
                .any(|(name, value)| *name == "ETag" && *value == format!("\"{hash}\""))
        );
        assert!(
            response
                .extra_headers
                .iter()
                .any(|(name, value)| *name == "Cache-Control" && value == "public, max-age=3600")
        );
    }

    #[cfg(not(feature = "landing"))]
    #[test]
    fn get_root_does_not_return_health() {
        let config = RelayConfig {
            bind_addr: DEFAULT_BIND_ADDR.parse().expect("default bind addr"),
            rpc_url: Some("http://127.0.0.1:8899".into()),
            web_socket_url: None,
            explorer_rpc_url: None,
            rpc_allowed_methods: default_rpc_allowed_methods(),
            rate_limits: RelayRateLimits::default(),
            landing_redirect: None,
            index_db_path: None,
        };
        let request = HttpRequest {
            method: "GET".into(),
            path: "/".into(),
            query: None,
            body: Vec::new(),
            host: None,
            websocket_key: None,
            if_none_match: None,
        };
        let response = handle_request_with_client(&request, &config, None);

        assert_eq!(response.status, 404);
    }

    #[cfg(feature = "landing")]
    #[test]
    fn get_root_serves_landing_when_enabled() {
        let config = RelayConfig {
            bind_addr: DEFAULT_BIND_ADDR.parse().expect("default bind addr"),
            rpc_url: Some("http://127.0.0.1:8899".into()),
            web_socket_url: None,
            explorer_rpc_url: None,
            rpc_allowed_methods: default_rpc_allowed_methods(),
            rate_limits: RelayRateLimits::default(),
            landing_redirect: None,
            index_db_path: None,
        };
        let request = HttpRequest {
            method: "GET".into(),
            path: "/".into(),
            query: None,
            body: Vec::new(),
            host: None,
            websocket_key: None,
            if_none_match: None,
        };
        let response = handle_request_with_client(&request, &config, None);
        assert_eq!(response.status, 200);
        assert_eq!(response.content_type, "text/html; charset=utf-8");
        assert!(
            std::str::from_utf8(&response.body)
                .expect("utf8")
                .contains("cosign")
        );
    }

    #[test]
    fn landing_redirect_moves_marketing_paths_only() {
        let mut config = rpc_test_config(default_rpc_allowed_methods());
        config.landing_redirect = Some("https://cosign.hackshare.com".into());

        let get = |path: &str| HttpRequest {
            method: "GET".into(),
            path: path.into(),
            query: None,
            body: Vec::new(),
            host: None,
            websocket_key: None,
            if_none_match: None,
        };

        let root = handle_request_with_client(&get("/"), &config, None);
        assert_eq!(root.status, 301);
        assert_eq!(
            std::str::from_utf8(&root.body).expect("utf8"),
            "https://cosign.hackshare.com/"
        );

        let privacy = handle_request_with_client(&get("/privacy"), &config, None);
        assert_eq!(privacy.status, 301);
        assert_eq!(
            std::str::from_utf8(&privacy.body).expect("utf8"),
            "https://cosign.hackshare.com/privacy"
        );

        // The relay's API role is untouched by the redirect.
        assert_eq!(
            handle_request_with_client(&get("/_health"), &config, None).status,
            200
        );
    }

    #[cfg(feature = "landing")]
    #[test]
    fn get_privacy_serves_page_when_enabled() {
        let config = RelayConfig {
            bind_addr: DEFAULT_BIND_ADDR.parse().expect("default bind addr"),
            rpc_url: Some("http://127.0.0.1:8899".into()),
            web_socket_url: None,
            explorer_rpc_url: None,
            rpc_allowed_methods: default_rpc_allowed_methods(),
            rate_limits: RelayRateLimits::default(),
            landing_redirect: None,
            index_db_path: None,
        };
        let request = HttpRequest {
            method: "GET".into(),
            path: "/privacy".into(),
            query: None,
            body: Vec::new(),
            host: None,
            websocket_key: None,
            if_none_match: None,
        };
        let response = handle_request_with_client(&request, &config, None);
        assert_eq!(response.status, 200);
        assert!(
            std::str::from_utf8(&response.body)
                .expect("utf8")
                .contains("Privacy")
        );
    }

    #[cfg(feature = "landing")]
    #[test]
    fn get_landing_asset_serves_png() {
        let config = RelayConfig {
            bind_addr: DEFAULT_BIND_ADDR.parse().expect("default bind addr"),
            rpc_url: Some("http://127.0.0.1:8899".into()),
            web_socket_url: None,
            explorer_rpc_url: None,
            rpc_allowed_methods: default_rpc_allowed_methods(),
            rate_limits: RelayRateLimits::default(),
            landing_redirect: None,
            index_db_path: None,
        };
        let request = HttpRequest {
            method: "GET".into(),
            path: "/assets/08-proposal-detail.png".into(),
            query: None,
            body: Vec::new(),
            host: None,
            websocket_key: None,
            if_none_match: None,
        };
        let response = handle_request_with_client(&request, &config, None);
        assert_eq!(response.status, 200);
        assert_eq!(response.content_type, "image/png");
        assert!(!response.body.is_empty());
    }

    #[test]
    fn get_health_uses_private_route() {
        let config = RelayConfig {
            bind_addr: DEFAULT_BIND_ADDR.parse().expect("default bind addr"),
            rpc_url: Some("http://127.0.0.1:8899".into()),
            web_socket_url: None,
            explorer_rpc_url: None,
            rpc_allowed_methods: default_rpc_allowed_methods(),
            rate_limits: RelayRateLimits::default(),
            landing_redirect: None,
            index_db_path: None,
        };
        let request = HttpRequest {
            method: "GET".into(),
            path: "/_health".into(),
            query: None,
            body: Vec::new(),
            host: None,
            websocket_key: None,
            if_none_match: None,
        };
        let response = handle_request_with_client(&request, &config, None);

        assert_eq!(response.status, 200);
        assert!(
            std::str::from_utf8(&response.body)
                .expect("json")
                .contains("\"service\": \"cosign-relay\"")
        );
    }

    #[test]
    fn serializes_simulation_summary() {
        let summary = SimulationSummary {
            status: SimulationStatus::Succeeded,
            message: "ok".into(),
            error: None,
            logs: vec!["Program log: success".into()],
            fee_payer: Some("payer111".into()),
            recent_blockhash: Some("blockhash111".into()),
        };

        let json = simulation_json(&summary);

        assert_eq!(json["status"], "succeeded");
        assert_eq!(json["message"], "ok");
        assert_eq!(json["logs"][0], "Program log: success");
        assert_eq!(json["feePayer"], "payer111");
    }

    #[test]
    fn blocked_simulation_status_is_structured() {
        let summary = SimulationSummary::blocked("proposal is active");
        let json = simulation_json(&summary);

        assert_eq!(json["status"], "blocked");
        assert_eq!(json["message"], "proposal is active");
    }

    #[test]
    fn serializes_member_squads_response() {
        let member = Pubkey::new_unique();
        let summary = types::MultisigSummary {
            address: "squad111".into(),
            threshold: 1,
            member_count: 2,
            transaction_index: 7,
            stale_transaction_index: 0,
        };
        let response = member_squads_json_response(&member, &[summary], "live");
        let body: Value = serde_json::from_slice(&response.body).expect("json");

        assert_eq!(body["kind"], "member_squads");
        assert_eq!(body["member"], member.to_string());
        assert_eq!(body["squads"][0]["address"], "squad111");
        assert_eq!(body["squads"][0]["memberCount"], 2);
    }

    #[test]
    fn member_squads_response_carries_source() {
        let member = Pubkey::new_unique();
        let response = member_squads_json_response(&member, &[], "live");
        let body: serde_json::Value = serde_json::from_slice(&response.body).unwrap();
        assert_eq!(body["source"], "live");
        assert_eq!(body["kind"], "member_squads");
    }

    #[test]
    fn serializes_optional_websocket_capability_url() {
        let config = RelayConfig {
            bind_addr: DEFAULT_BIND_ADDR.parse().expect("default bind addr"),
            rpc_url: Some("http://127.0.0.1:8899".into()),
            web_socket_url: Some("wss://relay.cosign.example/ws".into()),
            explorer_rpc_url: Some("https://relay.cosign.example".into()),
            rpc_allowed_methods: default_rpc_allowed_methods(),
            rate_limits: RelayRateLimits::default(),
            landing_redirect: None,
            index_db_path: None,
        };
        let response = capabilities_response(&config, Some("relay.cosign.example"));
        let body: Value = serde_json::from_slice(&response.body).expect("json");

        assert_eq!(body["webSocketURL"], "wss://relay.cosign.example/ws");
        assert_eq!(body["explorerRPCURL"], "https://relay.cosign.example");
    }

    #[test]
    fn serializes_squad_detail_response() {
        let detail = types::MultisigDetail {
            address: "squad111".into(),
            threshold: 2,
            time_lock_seconds: 30,
            rent_collector: None,
            transaction_index: 7,
            stale_transaction_index: 1,
            is_autonomous: true,
            members: vec![types::MemberInfo {
                pubkey: "member111".into(),
                can_initiate: true,
                can_vote: true,
                can_execute: false,
            }],
            vaults: vec![types::VaultRef {
                index: 0,
                address: "vault111".into(),
            }],
        };
        let response = squad_detail_json_response(&detail);
        let body: Value = serde_json::from_slice(&response.body).expect("json");

        assert_eq!(body["kind"], "squad_detail");
        assert_eq!(body["squad"]["address"], "squad111");
        assert_eq!(body["squad"]["threshold"], 2);
        assert_eq!(body["squad"]["members"][0]["pubkey"], "member111");
        assert_eq!(body["squad"]["members"][0]["canVote"], true);
        assert_eq!(body["squad"]["vaults"][0]["address"], "vault111");
        assert_eq!(body["squad"]["rentCollector"], serde_json::Value::Null);
    }

    #[test]
    fn serializes_squad_detail_rent_collector_present() {
        let collector = "So11111111111111111111111111111111111111112";
        let detail = types::MultisigDetail {
            address: "squad222".into(),
            threshold: 1,
            time_lock_seconds: 0,
            rent_collector: Some(collector.into()),
            transaction_index: 1,
            stale_transaction_index: 0,
            is_autonomous: true,
            members: vec![],
            vaults: vec![],
        };
        let response = squad_detail_json_response(&detail);
        let body: Value = serde_json::from_slice(&response.body).expect("json");

        assert_eq!(body["squad"]["rentCollector"], collector);
    }

    #[test]
    fn serializes_squad_proposals_response() {
        let squad = Pubkey::new_unique();
        let request = SquadProposalsRequest {
            squad,
            from_index: 1,
            to_index: 2,
        };
        let summary = types::ProposalSummary {
            transaction_index: 1,
            status: "active".into(),
            votes_yes: 1,
            votes_no: 0,
            votes_cancelled: 0,
            threshold: 2,
        };
        let response = squad_proposals_json_response(&request, &[summary]);
        let body: Value = serde_json::from_slice(&response.body).expect("json");

        assert_eq!(body["kind"], "squad_proposals");
        assert_eq!(body["squad"], squad.to_string());
        assert_eq!(body["range"]["from"], 1);
        assert_eq!(body["proposals"][0]["votesYes"], 1);
    }

    #[test]
    fn serializes_squad_proposal_response() {
        let squad = Pubkey::new_unique();
        let detail = types::ProposalDetail {
            transaction_index: 7,
            status: "active".into(),
            votes_yes: 1,
            votes_no: 0,
            votes_cancelled: 0,
            threshold: 2,
            kind: "vault".into(),
            voters_yes: vec!["member111".into()],
            voters_no: Vec::new(),
            voters_cancelled: Vec::new(),
            instructions: vec![DecodedInstruction {
                program: "System Program".into(),
                kind: "transfer".into(),
                summary: "Transfer 1 SOL".into(),
                accounts: Vec::new(),
                raw_data_hex: String::new(),
                config_action: None,
            }],
            accounts_referenced: Vec::new(),
            transaction_address: Some("transaction111".into()),
            proposer: Some("member111".into()),
            created_at_unix: Some(1_700_000_000),
        };
        let response = squad_proposal_json_response(&squad, &detail);
        let body: Value = serde_json::from_slice(&response.body).expect("json");

        assert_eq!(body["kind"], "squad_proposal");
        assert_eq!(body["proposal"]["transactionIndex"], 7);
        assert_eq!(body["proposal"]["votes"]["approve"], 1);
        assert_eq!(
            body["proposal"]["instructions"][0]["summary"],
            "Transfer 1 SOL"
        );
    }

    #[test]
    fn serializes_account_activity_response() {
        let address = Pubkey::new_unique();
        let before = Signature::new_unique();
        let request = AccountActivityRequest {
            address,
            before: Some(before),
            limit: 10,
        };
        let item = types::ActivityItem {
            signature: "signature111".into(),
            slot: 42,
            timestamp_unix: 1_778_107_000,
            kind: "transaction".into(),
            error: None,
        };
        let action = InspectionAction {
            classification: "sol_transfer".into(),
            summary: "Transfer 0.001 SOL".into(),
            confidence: "high".into(),
            effects: Vec::new(),
            warnings: Vec::new(),
        };
        let response = account_activity_json_response(
            &request,
            &[ActivityInspectionItem {
                item,
                action: Some(action),
            }],
        );
        let body: Value = serde_json::from_slice(&response.body).expect("json");

        assert_eq!(body["kind"], "account_activity");
        assert_eq!(body["address"], address.to_string());
        assert_eq!(body["before"], before.to_string());
        assert_eq!(body["activity"][0]["slot"], 42);
        assert_eq!(
            body["activity"][0]["action"]["summary"],
            "Transfer 0.001 SOL"
        );
    }

    #[test]
    fn serializes_transaction_status_response() {
        let signature = Signature::new_unique();
        let status = transactions::SignatureStatus {
            slot: Some(42),
            status: "confirmed".into(),
            err: None,
        };
        let response = transaction_status_json_response(&signature, &status);
        let body: Value = serde_json::from_slice(&response.body).expect("json");

        assert_eq!(body["kind"], "transaction_status");
        assert_eq!(body["signature"], signature.to_string());
        assert_eq!(body["status"]["slot"], 42);
        assert_eq!(body["status"]["status"], "confirmed");
    }

    #[test]
    fn action_effects_decode_system_transfer() {
        let instruction = DecodedInstruction {
            program: SYSTEM_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec!["source111".into(), "destination111".into()],
            raw_data_hex: "020000008813000000000000".into(),
            config_action: None,
        };

        let decoded = decode_known_instruction(&instruction);
        let action = action_from_decoded_instructions(&[decoded]);

        assert_eq!(action.classification, "sol_transfer");
        assert_eq!(action.summary, "Transfer 0.000005 SOL");
        assert_eq!(action.confidence, "high");
        assert_eq!(action.effects[0].destination, Some("destination111".into()));
    }

    #[test]
    fn action_effects_decode_system_owner_and_nonce_authority_changes() {
        let owner = Pubkey::new_unique();
        let assign = DecodedInstruction {
            program: SYSTEM_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec!["account111".into()],
            raw_data_hex: hex_bytes(
                &bincode::serialize(&SystemInstruction::Assign { owner }).expect("system assign"),
            ),
            config_action: None,
        };
        let new_authority = Pubkey::new_unique();
        let nonce = DecodedInstruction {
            program: SYSTEM_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec!["nonce111".into(), "authority111".into()],
            raw_data_hex: hex_bytes(
                &bincode::serialize(&SystemInstruction::AuthorizeNonceAccount(new_authority))
                    .expect("nonce authorize"),
            ),
            config_action: None,
        };

        let assign = decode_known_instruction(&assign);
        let nonce = decode_known_instruction(&nonce);
        let action = action_from_decoded_instructions(&[assign.clone(), nonce.clone()]);

        assert_eq!(assign.kind, "assign");
        assert_eq!(nonce.kind, "authorize_nonce_account");
        assert_eq!(action.classification, "multi_effect");
        assert_eq!(action.effects[0].kind, "system_account_owner_change");
        assert_eq!(action.effects[0].destination, Some(owner.to_string()));
        assert_eq!(action.effects[1].kind, "nonce_authority_change");
        assert_eq!(
            action.effects[1].destination,
            Some(new_authority.to_string())
        );
    }

    #[test]
    fn action_effects_decode_nonce_creation_and_admin_actions() {
        let new_authority = Pubkey::new_unique();
        let create = DecodedInstruction {
            program: SYSTEM_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec!["payer111".into(), "nonce111".into()],
            raw_data_hex: hex_bytes(
                &bincode::serialize(&SystemInstruction::CreateAccount {
                    lamports: 1_000_000,
                    space: NonceState::size() as u64,
                    owner: Pubkey::default(),
                })
                .expect("nonce create"),
            ),
            config_action: None,
        };
        let initialize = DecodedInstruction {
            program: SYSTEM_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec!["nonce111".into(), "recent111".into(), "rent111".into()],
            raw_data_hex: hex_bytes(
                &bincode::serialize(&SystemInstruction::InitializeNonceAccount(new_authority))
                    .expect("nonce initialize"),
            ),
            config_action: None,
        };
        let withdraw = DecodedInstruction {
            program: SYSTEM_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec![
                "nonce111".into(),
                "recipient111".into(),
                "recent111".into(),
                "rent111".into(),
                "authority111".into(),
            ],
            raw_data_hex: hex_bytes(
                &bincode::serialize(&SystemInstruction::WithdrawNonceAccount(2_000_000))
                    .expect("nonce withdraw"),
            ),
            config_action: None,
        };

        let create = decode_known_instruction(&create);
        let initialize = decode_known_instruction(&initialize);
        let create_action = action_from_decoded_instructions(&[create.clone(), initialize]);
        let withdraw_action =
            action_from_decoded_instructions(&[decode_known_instruction(&withdraw)]);

        assert_eq!(create.kind, "create_nonce_account");
        assert_eq!(create_action.classification, "nonce_account_create");
        assert_eq!(
            create_action.summary,
            format!("Create nonce account with authority {new_authority}")
        );
        assert_eq!(create_action.effects[0].kind, "nonce_account_create");
        assert_eq!(withdraw_action.classification, "nonce_withdraw");
        assert_eq!(
            withdraw_action.summary,
            "Withdraw 0.002 SOL from nonce account"
        );
    }

    #[test]
    fn action_effects_decode_token_transfer_with_associated_account_setup() {
        let setup = DecodedInstruction {
            program: ASSOCIATED_TOKEN_ACCOUNT_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec![
                "payer111".into(),
                "recipientAta111".into(),
                "recipient111".into(),
                "mint111".into(),
            ],
            raw_data_hex: "01".into(),
            config_action: None,
        };
        let transfer = DecodedInstruction {
            program: SPL_TOKEN_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec![
                "sourceAta111".into(),
                "mint111".into(),
                "recipientAta111".into(),
                "owner111".into(),
            ],
            raw_data_hex: "0c40420f000000000006".into(),
            config_action: None,
        };

        let decoded = vec![
            decode_known_instruction(&setup),
            decode_known_instruction(&transfer),
        ];
        let action = action_from_decoded_instructions(&decoded);

        assert_eq!(action.classification, "token_transfer");
        assert_eq!(
            action.summary,
            "Transfer 1 tokens and create associated token account if needed"
        );
        assert_eq!(action.confidence, "high");
        assert_eq!(action.effects.len(), 2);
        assert_eq!(action.effects[0].asset, Some("mint111".into()));
    }

    #[test]
    fn action_effects_decode_token_approve() {
        let instruction = DecodedInstruction {
            program: SPL_TOKEN_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec![
                "sourceAta111".into(),
                "delegate111".into(),
                "owner111".into(),
            ],
            raw_data_hex: "0440420f0000000000".into(),
            config_action: None,
        };

        let decoded = decode_known_instruction(&instruction);
        let action = action_from_decoded_instructions(std::slice::from_ref(&decoded));

        assert_eq!(decoded.kind, "approve");
        assert_eq!(decoded.summary, "Approve 1000000 base units");
        assert_eq!(action.classification, "token_approve");
        assert_eq!(action.summary, "Approve 1000000 base units");
        assert_eq!(action.confidence, "high");
        assert_eq!(action.effects[0].destination, Some("delegate111".into()));
    }

    #[test]
    fn action_effects_decode_token_supply_and_account_controls() {
        let mint = DecodedInstruction {
            program: SPL_TOKEN_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec![
                "mint111".into(),
                "destination111".into(),
                "authority111".into(),
            ],
            raw_data_hex: "0e40420f000000000006".into(),
            config_action: None,
        };
        let burn = DecodedInstruction {
            program: TOKEN_2022_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec!["source111".into(), "mint111".into(), "authority111".into()],
            raw_data_hex: "0f40420f000000000006".into(),
            config_action: None,
        };
        let freeze = DecodedInstruction {
            program: SPL_TOKEN_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec!["account111".into(), "mint111".into(), "authority111".into()],
            raw_data_hex: "0a".into(),
            config_action: None,
        };
        let close = DecodedInstruction {
            program: SPL_TOKEN_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec![
                "account111".into(),
                "destination111".into(),
                "owner111".into(),
            ],
            raw_data_hex: "09".into(),
            config_action: None,
        };

        let mint = decode_known_instruction(&mint);
        let burn = decode_known_instruction(&burn);
        let freeze = decode_known_instruction(&freeze);
        let close = decode_known_instruction(&close);

        let mint_action = action_from_decoded_instructions(std::slice::from_ref(&mint));
        let burn_action = action_from_decoded_instructions(std::slice::from_ref(&burn));
        let freeze_action = action_from_decoded_instructions(std::slice::from_ref(&freeze));
        let close_action = action_from_decoded_instructions(std::slice::from_ref(&close));

        assert_eq!(mint.kind, "mint_to_checked");
        assert_eq!(mint_action.classification, "token_mint");
        assert_eq!(mint_action.summary, "Mint 1 tokens");
        assert_eq!(
            mint_action.effects[0].destination,
            Some("destination111".into())
        );
        assert_eq!(burn.kind, "burn_checked");
        assert_eq!(burn_action.classification, "token_burn");
        assert_eq!(burn_action.effects[0].source, Some("authority111".into()));
        assert_eq!(freeze.kind, "freeze_account");
        assert_eq!(freeze_action.classification, "token_account_freeze");
        assert_eq!(close.kind, "close_account");
        assert_eq!(close_action.classification, "token_account_close");
        assert_eq!(
            close_action.effects[0].destination,
            Some("destination111".into())
        );
    }

    #[test]
    fn action_effects_decode_squads_config_change() {
        let instruction = DecodedInstruction {
            program: "Squads".into(),
            kind: "change_threshold".into(),
            summary: "Change threshold to 2".into(),
            accounts: vec!["squad111".into()],
            raw_data_hex: "00".into(),
            config_action: None,
        };

        let action = action_from_decoded_instructions(&[instruction]);

        assert_eq!(action.classification, "squads_change_threshold");
        assert_eq!(action.summary, "Change threshold to 2");
        assert_eq!(action.confidence, "high");
        assert_eq!(action.effects[0].destination, Some("squad111".into()));
    }

    #[test]
    fn action_effects_decode_upgradeable_loader_program_admin_actions() {
        let upgrade = DecodedInstruction {
            program: BPF_UPGRADEABLE_LOADER_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec![
                "programData111".into(),
                "program111".into(),
                "buffer111".into(),
                "spill111".into(),
                "rent111".into(),
                "clock111".into(),
                "authority111".into(),
            ],
            raw_data_hex: hex_bytes(
                &bincode::serialize(&UpgradeableLoaderInstruction::Upgrade)
                    .expect("program upgrade"),
            ),
            config_action: None,
        };
        let set_authority = DecodedInstruction {
            program: BPF_UPGRADEABLE_LOADER_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec![
                "programData111".into(),
                "authority111".into(),
                "newAuthority111".into(),
            ],
            raw_data_hex: hex_bytes(
                &bincode::serialize(&UpgradeableLoaderInstruction::SetAuthority)
                    .expect("set authority"),
            ),
            config_action: None,
        };

        let upgrade = decode_known_instruction(&upgrade);
        let set_authority = decode_known_instruction(&set_authority);
        let upgrade_action = action_from_decoded_instructions(std::slice::from_ref(&upgrade));
        let authority_action =
            action_from_decoded_instructions(std::slice::from_ref(&set_authority));

        assert_eq!(upgrade.program, "BPF Upgradeable Loader");
        assert_eq!(upgrade.kind, "program_upgrade");
        assert_eq!(upgrade_action.classification, "program_upgrade");
        assert_eq!(upgrade_action.summary, "Upgrade program program111");
        assert_eq!(upgrade_action.effects[0].source, Some("buffer111".into()));
        assert_eq!(set_authority.kind, "program_upgrade_authority_change");
        assert_eq!(
            authority_action.classification,
            "program_upgrade_authority_change"
        );
        assert_eq!(
            authority_action.effects[0].destination,
            Some("newAuthority111".into())
        );
    }

    #[test]
    fn action_effects_decode_stake_program_actions() {
        let new_authority = Pubkey::new_unique();
        let authorize = DecodedInstruction {
            program: STAKE_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec!["stake111".into(), "clock111".into(), "authority111".into()],
            raw_data_hex: hex_bytes(
                &bincode::serialize(&StakeInstruction::Authorize(
                    new_authority,
                    StakeAuthorize::Withdrawer,
                ))
                .expect("stake authorize"),
            ),
            config_action: None,
        };
        let delegate = DecodedInstruction {
            program: STAKE_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec![
                "stake111".into(),
                "vote111".into(),
                "clock111".into(),
                "history111".into(),
                "config111".into(),
                "authority111".into(),
            ],
            raw_data_hex: hex_bytes(
                &bincode::serialize(&StakeInstruction::DelegateStake).expect("stake delegate"),
            ),
            config_action: None,
        };
        let withdraw = DecodedInstruction {
            program: STAKE_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec![
                "stake111".into(),
                "recipient111".into(),
                "clock111".into(),
                "history111".into(),
                "authority111".into(),
            ],
            raw_data_hex: hex_bytes(
                &bincode::serialize(&StakeInstruction::Withdraw(1_000_000))
                    .expect("stake withdraw"),
            ),
            config_action: None,
        };

        let authorize = decode_known_instruction(&authorize);
        let delegate = decode_known_instruction(&delegate);
        let withdraw = decode_known_instruction(&withdraw);
        let authorize_action = action_from_decoded_instructions(std::slice::from_ref(&authorize));
        let delegate_action = action_from_decoded_instructions(std::slice::from_ref(&delegate));
        let withdraw_action = action_from_decoded_instructions(std::slice::from_ref(&withdraw));

        assert_eq!(authorize.kind, "stake_authority_change");
        assert_eq!(
            authorize.summary,
            format!("Set stake withdraw authority to {new_authority}")
        );
        assert_eq!(authorize_action.classification, "stake_authority_change");
        assert_eq!(delegate_action.classification, "stake_delegate");
        assert_eq!(delegate_action.summary, "Delegate stake to vote111");
        assert_eq!(withdraw_action.classification, "stake_withdraw");
        assert_eq!(withdraw_action.summary, "Withdraw 0.001 SOL from stake");
    }

    #[test]
    fn action_effects_decode_address_lookup_table_actions() {
        let address = Pubkey::new_unique();
        let extend = DecodedInstruction {
            program: ADDRESS_LOOKUP_TABLE_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec![
                "lookup111".into(),
                "authority111".into(),
                "payer111".into(),
                SYSTEM_PROGRAM_ID.into(),
            ],
            raw_data_hex: hex_bytes(
                &bincode::serialize(&AddressLookupTableInstruction::ExtendLookupTable {
                    new_addresses: vec![address],
                })
                .expect("lookup table extend"),
            ),
            config_action: None,
        };
        let close = DecodedInstruction {
            program: ADDRESS_LOOKUP_TABLE_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec![
                "lookup111".into(),
                "authority111".into(),
                "recipient111".into(),
            ],
            raw_data_hex: hex_bytes(
                &bincode::serialize(&AddressLookupTableInstruction::CloseLookupTable)
                    .expect("lookup table close"),
            ),
            config_action: None,
        };

        let extend = decode_known_instruction(&extend);
        let close = decode_known_instruction(&close);
        let extend_action = action_from_decoded_instructions(std::slice::from_ref(&extend));
        let close_action = action_from_decoded_instructions(std::slice::from_ref(&close));

        assert_eq!(extend.kind, "lookup_table_extend");
        assert_eq!(extend.summary, "Extend address lookup table with 1 address");
        assert_eq!(extend_action.classification, "lookup_table_extend");
        assert_eq!(extend_action.effects[0].amount, Some("1 address".into()));
        assert_eq!(close.kind, "lookup_table_close");
        assert_eq!(close_action.classification, "lookup_table_close");
        assert_eq!(
            close_action.effects[0].destination,
            Some("recipient111".into())
        );
    }

    #[test]
    fn action_effects_decode_parsed_upgradeable_loader_authority_change() {
        let transaction = json!({
            "meta": {
                "innerInstructions": []
            },
            "transaction": {
                "message": {
                    "instructions": [
                        {
                            "program": "bpf-upgradeable-loader",
                            "programId": BPF_UPGRADEABLE_LOADER_PROGRAM_ID,
                            "parsed": {
                                "type": "setAuthority",
                                "info": {
                                    "account": "programData111",
                                    "authority": "authority111",
                                    "newAuthority": "newAuthority111"
                                }
                            }
                        }
                    ]
                }
            }
        });

        let action = action_from_transaction_json(&transaction);

        assert_eq!(action.classification, "program_upgrade_authority_change");
        assert_eq!(action.summary, "Set upgrade authority to newAuthority111");
        assert_eq!(action.confidence, "high");
    }

    #[test]
    fn action_effects_decode_squads_member_and_time_lock_changes() {
        let add_member = DecodedInstruction {
            program: "Squads".into(),
            kind: "add_member".into(),
            summary: "Add member member111 with initiate, vote permissions".into(),
            accounts: vec!["member111".into()],
            raw_data_hex: String::new(),
            config_action: None,
        };
        let time_lock = DecodedInstruction {
            program: "Squads".into(),
            kind: "set_time_lock".into(),
            summary: "Set time lock to 3600 seconds".into(),
            accounts: Vec::new(),
            raw_data_hex: String::new(),
            config_action: None,
        };

        let action = action_from_decoded_instructions(&[add_member, time_lock]);

        assert_eq!(action.classification, "squads_config_change");
        assert_eq!(action.summary, "2 Squads config changes");
        assert_eq!(action.confidence, "high");
        assert_eq!(action.effects[0].kind, "squads_add_member");
        assert_eq!(action.effects[0].destination, Some("member111".into()));
        assert_eq!(action.effects[1].kind, "squads_set_time_lock");
    }

    #[test]
    fn action_effects_decode_squads_votes_from_raw_transaction_json() {
        let cases = [
            (
                ProposalApproveData::DISCRIMINATOR,
                "squads_proposal_approve",
                "Approve proposal",
            ),
            (
                ProposalRejectData::DISCRIMINATOR,
                "squads_proposal_reject",
                "Reject proposal",
            ),
            (
                ProposalCancelData::DISCRIMINATOR,
                "squads_proposal_cancel",
                "Cancel approved proposal",
            ),
        ];

        for (data, kind, summary) in cases {
            let transaction = json!({
                "meta": {
                    "innerInstructions": []
                },
                "transaction": {
                    "message": {
                        "instructions": [
                            raw_squads_instruction_json(
                                &data,
                                &["squad111", "member111", "proposal111"]
                            )
                        ]
                    }
                }
            });

            let action = action_from_transaction_json(&transaction);

            assert_eq!(action.classification, kind);
            assert_eq!(action.summary, summary);
            assert_eq!(action.confidence, "high");
            assert_eq!(action.effects[0].source, Some("member111".into()));
            assert_eq!(action.effects[0].destination, Some("proposal111".into()));
        }
    }

    #[test]
    fn action_effects_decode_squads_execute_without_hiding_inner_transfer() {
        let transaction = json!({
            "meta": {
                "innerInstructions": [
                    {
                        "instructions": [
                            {
                                "program": "system",
                                "programId": SYSTEM_PROGRAM_ID,
                                "parsed": {
                                    "type": "transfer",
                                    "info": {
                                        "source": "vault111",
                                        "destination": "recipient111",
                                        "lamports": 1_000_000
                                    }
                                }
                            }
                        ]
                    }
                ]
            },
            "transaction": {
                "message": {
                    "instructions": [
                        raw_squads_instruction_json(
                            &VaultTransactionExecuteData::DISCRIMINATOR,
                            &["squad111", "proposal111", "transaction111", "member111"]
                        )
                    ]
                }
            }
        });

        let action = action_from_transaction_json(&transaction);

        assert_eq!(action.classification, "sol_transfer");
        assert_eq!(action.summary, "Transfer 0.001 SOL");
        assert_eq!(action.effects[0].kind, "squads_execute_vault_transaction");
        assert_eq!(action.effects[1].kind, "sol_transfer");
    }

    #[test]
    fn action_effects_ignore_memo_and_compute_budget_for_confidence() {
        let compute_budget = DecodedInstruction {
            program: COMPUTE_BUDGET_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: Vec::new(),
            raw_data_hex: "02a0860100".into(),
            config_action: None,
        };
        let memo = DecodedInstruction {
            program: MEMO_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: Vec::new(),
            raw_data_hex: "68656c6c6f".into(),
            config_action: None,
        };
        let transfer = DecodedInstruction {
            program: SYSTEM_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec!["source111".into(), "destination111".into()],
            raw_data_hex: "020000008813000000000000".into(),
            config_action: None,
        };

        let decoded = vec![
            decode_known_instruction(&compute_budget),
            decode_known_instruction(&memo),
            decode_known_instruction(&transfer),
        ];
        let action = action_from_decoded_instructions(&decoded);

        assert_eq!(decoded[0].summary, "Set compute unit limit to 100000");
        assert_eq!(decoded[1].summary, "Memo: hello");
        assert_eq!(action.classification, "sol_transfer");
        assert_eq!(action.confidence, "high");
        assert!(action.warnings.is_empty());
    }

    #[test]
    fn action_effects_decode_parsed_inner_transfer() {
        let transaction = json!({
            "meta": {
                "innerInstructions": [
                    {
                        "index": 0,
                        "instructions": [
                            {
                                "program": "system",
                                "programId": SYSTEM_PROGRAM_ID,
                                "parsed": {
                                    "type": "transfer",
                                    "info": {
                                        "source": "source111",
                                        "destination": "destination111",
                                        "lamports": 1_000_000
                                    }
                                }
                            }
                        ]
                    }
                ]
            },
            "transaction": {
                "message": {
                    "instructions": []
                }
            }
        });

        let action = action_from_transaction_json(&transaction);

        assert_eq!(action.classification, "sol_transfer");
        assert_eq!(action.summary, "Transfer 0.001 SOL");
        assert_eq!(action.effects[0].source, Some("source111".into()));
    }

    #[test]
    fn action_effects_decode_parsed_associated_account_setup() {
        let transaction = json!({
            "meta": {
                "innerInstructions": []
            },
            "transaction": {
                "message": {
                    "instructions": [
                        {
                            "program": "spl-associated-token-account",
                            "programId": ASSOCIATED_TOKEN_ACCOUNT_PROGRAM_ID,
                            "parsed": {
                                "type": "createIdempotent",
                                "info": {
                                    "source": "payer111",
                                    "account": "recipientAta111",
                                    "mint": "mint111"
                                }
                            }
                        },
                        {
                            "program": "spl-token",
                            "programId": SPL_TOKEN_PROGRAM_ID,
                            "parsed": {
                                "type": "transferChecked",
                                "info": {
                                    "source": "sourceAta111",
                                    "destination": "recipientAta111",
                                    "mint": "mint111",
                                    "tokenAmount": {
                                        "uiAmountString": "2.5"
                                    }
                                }
                            }
                        }
                    ]
                }
            }
        });

        let action = action_from_transaction_json(&transaction);

        assert_eq!(action.classification, "token_transfer");
        assert_eq!(
            action.summary,
            "Transfer 2.5 tokens and create associated token account if needed"
        );
        assert_eq!(action.effects.len(), 2);
        assert_eq!(
            action.effects[0].destination,
            Some("recipientAta111".into())
        );
    }

    #[test]
    fn action_effects_decode_parsed_token_authority_change() {
        let transaction = json!({
            "meta": {
                "innerInstructions": []
            },
            "transaction": {
                "message": {
                    "instructions": [
                        {
                            "program": "spl-token",
                            "programId": SPL_TOKEN_PROGRAM_ID,
                            "parsed": {
                                "type": "setAuthority",
                                "info": {
                                    "authority": "oldAuthority111",
                                    "authorityType": "mintTokens",
                                    "mint": "mint111",
                                    "newAuthority": "newAuthority111"
                                }
                            }
                        }
                    ]
                }
            }
        });

        let action = action_from_transaction_json(&transaction);

        assert_eq!(action.classification, "token_authority_change");
        assert_eq!(action.summary, "Set token mintTokens to newAuthority111");
        assert_eq!(action.confidence, "high");
        assert_eq!(action.effects[0].source, Some("oldAuthority111".into()));
        assert_eq!(
            action.effects[0].destination,
            Some("newAuthority111".into())
        );
    }

    /// Pins the gap `resolve_missing_transfer_assets` fixes up after the fact:
    /// a non-checked SPL `transfer` (unlike `transferChecked`) carries no
    /// `mint` in jsonParsed output, so the parsed effect comes out with
    /// `asset: None` even though the leg is a real token transfer.
    #[test]
    fn action_effects_decode_parsed_non_checked_transfer_has_no_asset() {
        let transaction = json!({
            "meta": {
                "innerInstructions": []
            },
            "transaction": {
                "message": {
                    "instructions": [
                        {
                            "program": "spl-token",
                            "programId": SPL_TOKEN_PROGRAM_ID,
                            "parsed": {
                                "type": "transfer",
                                "info": {
                                    "source": "sourceAta111",
                                    "destination": "destinationAta111",
                                    "authority": "owner111",
                                    "amount": "1000"
                                }
                            }
                        }
                    ]
                }
            }
        });

        let action = action_from_transaction_json(&transaction);

        assert_eq!(action.effects.len(), 1);
        assert_eq!(action.effects[0].kind, "token_transfer");
        assert_eq!(action.effects[0].asset, None);
        assert_eq!(action.effects[0].source, Some("sourceAta111".into()));
        assert!(transfer_asset_needs_resolution(&action.effects[0]));
    }

    /// The pending-proposal (decoded) inspection path has the same gap as the
    /// executed (jsonParsed) path: a non-checked SPL `transfer` decodes to an
    /// effect with `asset: None`, but its `source` is account 0 — the source
    /// token account — so the shared post-pass can resolve the mint from it.
    /// A decoded `transferChecked` already carries its mint (account 1) and is
    /// left untouched.
    #[test]
    fn action_effects_decode_decoded_non_checked_transfer_needs_resolution_via_source() {
        let transfer = DecodedInstruction {
            program: SPL_TOKEN_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec![
                "sourceAta111".into(),
                "destinationAta111".into(),
                "owner111".into(),
            ],
            raw_data_hex: "0340420f0000000000".into(),
            config_action: None,
        };
        let decoded = decode_known_instruction(&transfer);
        assert_eq!(decoded.kind, "transfer");
        let action = action_from_decoded_instructions(std::slice::from_ref(&decoded));

        assert_eq!(action.effects.len(), 1);
        assert_eq!(action.effects[0].kind, "token_transfer");
        assert_eq!(action.effects[0].asset, None);
        assert_eq!(action.effects[0].source, Some("sourceAta111".into()));
        assert!(transfer_asset_needs_resolution(&action.effects[0]));

        let checked = DecodedInstruction {
            program: SPL_TOKEN_PROGRAM_ID.into(),
            kind: "raw".into(),
            summary: "raw".into(),
            accounts: vec![
                "sourceAta111".into(),
                "mint111".into(),
                "destinationAta111".into(),
                "owner111".into(),
            ],
            raw_data_hex: "0c40420f000000000006".into(),
            config_action: None,
        };
        let checked_action = action_from_decoded_instructions(std::slice::from_ref(
            &decode_known_instruction(&checked),
        ));
        assert_eq!(checked_action.effects[0].asset, Some("mint111".into()));
        assert!(!transfer_asset_needs_resolution(&checked_action.effects[0]));
    }

    #[test]
    fn transfer_asset_needs_resolution_targets_unresolved_token_transfers_only() {
        let unresolved = InspectionEffect {
            kind: "token_transfer".into(),
            summary: "Transfer 1000 base units".into(),
            program: Some("SPL Token Program".into()),
            asset: None,
            amount: Some("1000 base units".into()),
            source: Some("sourceAta111".into()),
            destination: Some("destinationAta111".into()),
        };
        assert!(transfer_asset_needs_resolution(&unresolved));

        let mut already_resolved = unresolved.clone();
        already_resolved.asset = Some("mint111".into());
        assert!(!transfer_asset_needs_resolution(&already_resolved));

        let mut non_transfer = unresolved;
        non_transfer.kind = "token_approve".into();
        assert!(!transfer_asset_needs_resolution(&non_transfer));
    }

    /// Neither effect here qualifies for resolution (one already has an
    /// asset, the other isn't a transfer), so the pass never attempts an RPC
    /// call — safe to run against a bogus URL and a useful check that
    /// already-resolved / non-transfer effects pass through unchanged.
    #[test]
    fn resolve_missing_transfer_assets_leaves_resolved_and_non_transfer_effects_untouched() {
        let checked_transfer = InspectionEffect {
            kind: "token_transfer".into(),
            summary: "Transfer 2.5 tokens".into(),
            program: Some("SPL Token Program".into()),
            asset: Some("mint111".into()),
            amount: Some("2.5".into()),
            source: Some("sourceAta111".into()),
            destination: Some("destinationAta111".into()),
        };
        let approval = InspectionEffect {
            kind: "token_approve".into(),
            summary: "Approve 5 tokens".into(),
            program: Some("SPL Token Program".into()),
            asset: None,
            amount: Some("5".into()),
            source: Some("sourceAta111".into()),
            destination: Some("delegate111".into()),
        };
        let mut action =
            InspectionAction::from_effects(vec![checked_transfer.clone(), approval.clone()], 0);

        resolve_missing_transfer_assets(&mut action, "not-a-real-rpc-url");

        assert_eq!(action.effects[0].asset, checked_transfer.asset);
        assert_eq!(action.effects[0].amount, checked_transfer.amount);
        assert_eq!(action.effects[0].summary, checked_transfer.summary);
        assert_eq!(action.effects[1].asset, approval.asset);
        assert_eq!(action.effects[1].amount, approval.amount);
    }

    /// Once the mint's decimals are known, a resolved non-checked transfer's raw
    /// `"<n> base units"` amount is rewritten to the same trimmed decimal a
    /// checked transfer shows, and the summary follows. A 6-decimal (USDC-like)
    /// transfer of 1_500_000 base units becomes "1.5"; a whole amount drops its
    /// fractional part entirely.
    #[test]
    fn reformat_transfer_amount_as_decimal_produces_trimmed_decimal() {
        let base = InspectionEffect {
            kind: "token_transfer".into(),
            summary: "Transfer 1500000 base units".into(),
            program: Some("SPL Token Program".into()),
            asset: Some("mint111".into()),
            amount: Some("1500000 base units".into()),
            source: Some("sourceAta111".into()),
            destination: Some("destinationAta111".into()),
        };

        let mut fractional = base.clone();
        reformat_transfer_amount_as_decimal(&mut fractional, 6);
        assert_eq!(fractional.amount, Some("1.5".into()));
        assert_eq!(fractional.summary, "Transfer 1.5 tokens");

        let mut whole = InspectionEffect {
            summary: "Transfer 12000000 base units".into(),
            amount: Some("12000000 base units".into()),
            ..base.clone()
        };
        reformat_transfer_amount_as_decimal(&mut whole, 6);
        assert_eq!(whole.amount, Some("12".into()));
        assert_eq!(whole.summary, "Transfer 12 tokens");

        let mut sub_unit = InspectionEffect {
            amount: Some("1000 base units".into()),
            ..base
        };
        reformat_transfer_amount_as_decimal(&mut sub_unit, 6);
        assert_eq!(sub_unit.amount, Some("0.001".into()));
    }

    /// The decimals lookup is the fail-safe second layer: when it can't be read
    /// the reformat is simply never invoked, so the leg keeps its `"<n> base
    /// units"` amount (asset already set is the win). This pins that the
    /// reformat helper itself is a no-op on anything that isn't the expected
    /// base-units shape, so a partial resolution never corrupts the display.
    #[test]
    fn reformat_transfer_amount_as_decimal_is_noop_on_unexpected_shape() {
        let base = InspectionEffect {
            kind: "token_transfer".into(),
            summary: "Transfer 1000 base units".into(),
            program: Some("SPL Token Program".into()),
            asset: Some("mint111".into()),
            amount: Some("1000 base units".into()),
            source: Some("sourceAta111".into()),
            destination: Some("destinationAta111".into()),
        };

        // Already a decimal (no "base units" suffix) — left exactly as-is.
        let mut decimal = InspectionEffect {
            summary: "Transfer 1.5 tokens".into(),
            amount: Some("1.5".into()),
            ..base.clone()
        };
        reformat_transfer_amount_as_decimal(&mut decimal, 6);
        assert_eq!(decimal.amount, Some("1.5".into()));
        assert_eq!(decimal.summary, "Transfer 1.5 tokens");

        // Non-numeric leading token — unchanged, no panic.
        let mut garbage = InspectionEffect {
            amount: Some("abc base units".into()),
            ..base.clone()
        };
        reformat_transfer_amount_as_decimal(&mut garbage, 6);
        assert_eq!(garbage.amount, Some("abc base units".into()));

        // Missing amount — unchanged, no panic.
        let mut empty = InspectionEffect {
            amount: None,
            ..base
        };
        reformat_transfer_amount_as_decimal(&mut empty, 6);
        assert_eq!(empty.amount, None);
    }

    #[test]
    fn json_errors_use_stable_shape() {
        let response = error_response(404, ResponseFormat::Json, "not found");
        let body: Value = serde_json::from_slice(&response.body).expect("json");

        assert_eq!(body["ok"], false);
        assert_eq!(body["error"]["code"], "not_found");
        assert_eq!(body["error"]["message"], "not found");
    }

    #[test]
    fn ws_allowlist_permits_subscriptions_and_rejects_other_methods() {
        assert!(ws_method_allowed(
            r#"{"jsonrpc":"2.0","id":1,"method":"accountSubscribe","params":[]}"#
        ));
        assert!(ws_method_allowed(r#"{"method":"slotSubscribe"}"#));
        assert!(ws_method_allowed(r#"{"method":"signatureUnsubscribe"}"#));
        assert!(!ws_method_allowed(r#"{"method":"sendTransaction"}"#));
        assert!(!ws_method_allowed(r#"{"method":"getAccountInfo"}"#));
        assert!(!ws_method_allowed(r#"{"no":"method"}"#));
        assert!(!ws_method_allowed("not json"));
    }

    #[test]
    fn simulation_html_escapes_logs() {
        let summary = SimulationSummary {
            status: SimulationStatus::Failed,
            message: "failed <badly>".into(),
            error: Some("InstructionError <0>".into()),
            logs: vec!["Program log: <script>".into()],
            fee_payer: None,
            recent_blockhash: None,
        };

        let html = simulation_html(&summary);

        assert!(html.contains("failed &lt;badly&gt;"));
        assert!(html.contains("InstructionError &lt;0&gt;"));
        assert!(html.contains("Program log: &lt;script&gt;"));
    }

    fn raw_squads_instruction_json(data: &[u8], accounts: &[&str]) -> Value {
        json!({
            "programId": SQUADS_PROGRAM_ID,
            "accounts": accounts,
            "data": bs58::encode(data).into_string()
        })
    }

    fn hex_bytes(bytes: &[u8]) -> String {
        bytes.iter().map(|byte| format!("{byte:02x}")).collect()
    }
}
