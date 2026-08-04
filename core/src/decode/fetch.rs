//! Relay HTTP client for the decode inputs: fetches on-chain IDLs, the signed
//! decode-registry bundle, mint metadata, and the inspection report, fans them
//! out concurrently, and rebuilds the Cache-Control/ETag/304 client-side HTTP
//! cache that moving off Swift URLSession forfeits. Every failure fails open to
//! an absent input. Transport is the reqwest already in the staticlib via
//! solana-client; the async fan-out runs on a process-wide tokio runtime.

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use solana_client::client_error::reqwest;
use tokio::runtime::Runtime;
use url::Url;

use crate::decode::DecodeProvenance;
use crate::decode::idl::ResolvedProgramIdl;
use crate::decode::manifest::{VerifiedManifest, verify_manifest};
use crate::decode::mints::{MintMetadataResponse, ResolvedMint};
use crate::decode::registry::{DECODE_REGISTRY_ROOT_KEYS, verify_registry};
use crate::decode::spec::DecodeSpec;
use crate::decode::wire::{DecodeRegistryResponse, ProgramIdlResponse};

/// Process-wide multi-thread runtime driving the async `reqwest` fetches. Built
/// once, on first use. `block_on` on it is only ever called from a plain OS
/// thread (Plan 3's Swift bridge background thread), never from inside another
/// runtime — the RPC proposal fetch does its own `block_on` in solana's blocking
/// `RpcClient` and has returned before any decode fetch starts, so the fan-out
/// is flat and no nested `block_on` is attempted.
fn runtime() -> &'static Runtime {
    static RUNTIME: OnceLock<Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("build decode-fetch tokio runtime")
    })
}

/// Process-wide registry of `RelayFetchClient`s keyed by relay coordinates, so
/// repeat decodes against the same relay share one client and thus one HTTP
/// cache. Without this the Plan-2 cache is inert (a fresh client per decode is
/// a cold cache every time).
fn client_registry() -> &'static Mutex<HashMap<String, Arc<RelayFetchClient>>> {
    static REGISTRY: OnceLock<Mutex<HashMap<String, Arc<RelayFetchClient>>>> = OnceLock::new();
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

pub fn shared_client(base_url: &str, capabilities: &[String]) -> Option<Arc<RelayFetchClient>> {
    let mut caps = capabilities.to_vec();
    caps.sort();
    let key = format!("{base_url}\u{1f}{}", caps.join("\u{1f}"));
    let mut registry = client_registry().lock().unwrap_or_else(|e| e.into_inner());
    if let Some(existing) = registry.get(&key) {
        return Some(existing.clone());
    }
    let caps = if capabilities.is_empty() {
        None // empty ⇒ assume all supported, matching the Swift `capabilities: Set? = nil` default
    } else {
        Some(capabilities.to_vec())
    };
    let client = Arc::new(RelayFetchClient::new(base_url, caps)?);
    registry.insert(key, client.clone());
    Some(client)
}

pub const CAP_PROGRAM_IDL: &str = "program_idl";
pub const CAP_DECODE_REGISTRY: &str = "decode_registry";
pub const CAP_MINT_METADATA: &str = "mint_metadata";

const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);
const CACHE_CAPACITY: usize = 256;
/// 8 MiB is far above any legitimate IDL, signed registry bundle, or mint
/// payload, while still bounding memory against an adversarial relay response.
const MAX_RESPONSE_BYTES: usize = 8 * 1024 * 1024;

/// Relay HTTP client: builds the decode-input URLs gated by the relay's
/// advertised capability set, and fetches and caches their responses.
/// `capabilities: None` mirrors Swift's `capabilities: Set<RelayCapability>? = nil`
/// default — assume every capability is supported rather than gate on an
/// empty set.
#[derive(Clone)]
pub struct RelayFetchClient {
    base_url: Url,
    capabilities: Option<HashSet<String>>,
    client: reqwest::Client,
    cache: Arc<HttpCache>,
}

impl RelayFetchClient {
    pub fn new(base_url: &str, capabilities: Option<Vec<String>>) -> Option<Self> {
        let base_url = Url::parse(base_url).ok()?;
        if base_url.cannot_be_a_base() {
            return None;
        }
        let client = reqwest::Client::builder()
            .timeout(REQUEST_TIMEOUT)
            .build()
            .ok()?;
        Some(Self {
            base_url,
            capabilities: capabilities.map(|caps| caps.into_iter().collect()),
            client,
            cache: Arc::new(HttpCache::new(CACHE_CAPACITY)),
        })
    }

    fn supports(&self, capability: &str) -> bool {
        self.capabilities
            .as_ref()
            .is_none_or(|set| set.contains(capability))
    }

    /// Appends path segments to the base URL, tolerating a trailing slash on
    /// the base (so `.../relay/` + `cosign` does not produce a `//`) and
    /// percent-encoding each segment the way `URLComponents.percentEncodedPath`
    /// does on the Swift side.
    fn relay_url(&self, segments: &[&str]) -> Option<Url> {
        let mut url = self.base_url.clone();
        url.path_segments_mut()
            .ok()?
            .pop_if_empty()
            .extend(segments);
        Some(url)
    }

    fn program_idl_url(&self, program_id: &str) -> Option<Url> {
        if !self.supports(CAP_PROGRAM_IDL) {
            return None;
        }
        self.relay_url(&["cosign", "v1", "programs", program_id, "idl"])
    }

    fn mint_url(&self, account: &str) -> Option<Url> {
        if !self.supports(CAP_MINT_METADATA) {
            return None;
        }
        self.relay_url(&["cosign", "v1", "mints", account])
    }

    fn decode_registry_url(&self) -> Option<Url> {
        if !self.supports(CAP_DECODE_REGISTRY) {
            return None;
        }
        self.relay_url(&["cosign", "v1", "decode-registry"])
    }

    /// The trusted-keys manifest endpoint. Gated on the same capability as the
    /// bundle: a relay that serves the decode registry serves its key manifest.
    fn manifest_url(&self) -> Option<Url> {
        if !self.supports(CAP_DECODE_REGISTRY) {
            return None;
        }
        self.relay_url(&["cosign", "v1", "decode-keys"])
    }
}

/// Verifies the signed bundle against `keys` and groups its specs by program.
/// Any verification failure (bad signature, unknown/absent key, malformed
/// bundle) yields an empty map — the tier-3 registry stays inert rather than
/// trusting an unverified bundle. Mirrors `DecodeRegistryResolver.resolve`.
fn build_registry_specs(
    response: &DecodeRegistryResponse,
    keys: &[(&str, &str)],
) -> HashMap<String, Vec<DecodeSpec>> {
    let Ok(bundle) = verify_registry(response, keys) else {
        return HashMap::new();
    };
    let mut grouped: HashMap<String, Vec<DecodeSpec>> = HashMap::new();
    for spec in bundle.specs {
        grouped.entry(spec.program.clone()).or_default().push(spec);
    }
    grouped
}

impl RelayFetchClient {
    async fn program_idl_async(&self, program_id: &str) -> Option<ResolvedProgramIdl> {
        let url = self.program_idl_url(program_id)?;
        let body = self.get_cacheable(&url).await?.body;
        let parsed: ProgramIdlResponse = serde_json::from_slice(&body).ok()?;
        Some(ResolvedProgramIdl {
            provenance: DecodeProvenance::OnChainIdl {
                idl_name: parsed.idl.name.clone(),
                hash: parsed.hash,
                slot: parsed.slot,
            },
            document: parsed.idl,
        })
    }

    async fn mint_async(&self, account: &str) -> Option<ResolvedMint> {
        let url = self.mint_url(account)?;
        let body = self.get_cacheable(&url).await?.body;
        let parsed: MintMetadataResponse = serde_json::from_slice(&body).ok()?;
        Some(ResolvedMint {
            mint: parsed.mint,
            decimals: parsed.decimals,
            symbol: parsed.symbol,
        })
    }

    /// Verifies the relay's trusted-keys manifest against the pinned root keys,
    /// then resolves the signed bundle against the manifest's publisher keys —
    /// two-level delegation. Returns the grouped specs plus the accepted manifest
    /// `issuedAt`. Any manifest failure (absent, malformed, expired, rolled back,
    /// unknown root, bad signature) fails safe to empty specs and no accepted
    /// `issuedAt`, keeping tier-3 inert. `now_rfc3339`/`last_accepted_issued_at`
    /// are supplied by the caller so freshness is deterministic in tests.
    async fn decode_registry_async(
        &self,
        now_rfc3339: &str,
        last_accepted_issued_at: Option<&str>,
    ) -> (HashMap<String, Vec<DecodeSpec>>, Option<String>) {
        self.decode_registry_with_roots(
            DECODE_REGISTRY_ROOT_KEYS,
            now_rfc3339,
            last_accepted_issued_at,
        )
        .await
    }

    async fn decode_registry_with_roots(
        &self,
        root_keys: &[(&str, &str)],
        now_rfc3339: &str,
        last_accepted_issued_at: Option<&str>,
    ) -> (HashMap<String, Vec<DecodeSpec>>, Option<String>) {
        let Some(manifest_url) = self.manifest_url() else {
            return (HashMap::new(), None);
        };
        let Some(manifest_cached) = self.get_cacheable(&manifest_url).await else {
            return (HashMap::new(), None);
        };
        let Ok(VerifiedManifest {
            issued_at,
            publisher_keys,
        }) = verify_manifest(
            &manifest_cached.body,
            manifest_cached.signature.as_deref().unwrap_or_default(),
            root_keys,
            now_rfc3339,
            last_accepted_issued_at,
        )
        else {
            return (HashMap::new(), None);
        };

        // The manifest is accepted: record its issued_at even if the bundle then
        // fails to resolve, so a later older manifest can't roll it back.
        let accepted = Some(issued_at);

        let Some(url) = self.decode_registry_url() else {
            return (HashMap::new(), accepted);
        };
        let Some(cached) = self.get_cacheable(&url).await else {
            return (HashMap::new(), accepted);
        };
        let response = DecodeRegistryResponse {
            bundle_data: cached.body,
            signature_base64: cached.signature.unwrap_or_default(),
        };
        let key_refs: Vec<(&str, &str)> = publisher_keys
            .iter()
            .map(|(id, pk)| (id.as_str(), pk.as_str()))
            .collect();
        (build_registry_specs(&response, &key_refs), accepted)
    }
}

/// A cacheable GET's payload: the body plus the registry signature header (the
/// only response header a decode caller needs beyond the body).
struct CachedResponse {
    body: Vec<u8>,
    signature: Option<String>,
}

impl RelayFetchClient {
    /// GET for a cacheable endpoint: consults the client-side cache first (a
    /// fresh entry is served with no network request), sends `If-None-Match`
    /// when a stale entry has an `ETag`, treats a `304` as a cache hit that
    /// reuses the cached body, and otherwise stores the fresh response before
    /// returning it. Fails open on any transport/status error rather than
    /// serving a stale entry.
    async fn get_cacheable(&self, url: &Url) -> Option<CachedResponse> {
        let key = url.as_str().to_string();

        if let Some(fresh) = self.cache.fresh(&key) {
            return Some(fresh);
        }

        let mut request = self.client.get(url.as_str());
        if let Some(etag) = self.cache.etag(&key) {
            request = request.header(reqwest::header::IF_NONE_MATCH, etag);
        }
        let response = request.send().await.ok()?;
        let status = response.status();

        if status == reqwest::StatusCode::NOT_MODIFIED {
            let max_age = cache_max_age(response.headers());
            return self.cache.revalidate(&key, max_age);
        }
        if !status.is_success() {
            return None; // fail-open; a stale entry is not served on error
        }

        let etag = header_string(response.headers(), "etag");
        // The bundle rides `x-cosign-registry-signature`; the trusted-keys
        // manifest rides `x-cosign-registry-keys-signature`. Only one is present
        // per response, so a single cached field carries whichever the endpoint
        // sent.
        let signature = header_string(response.headers(), "x-cosign-registry-signature")
            .or_else(|| header_string(response.headers(), "x-cosign-registry-keys-signature"));
        let max_age = cache_max_age(response.headers());
        let body = read_body_capped(response, MAX_RESPONSE_BYTES).await?;
        self.cache.store(
            &key,
            CachedEntry {
                body: body.clone(),
                etag,
                signature: signature.clone(),
                stored_at: Instant::now(),
                max_age,
            },
        );
        Some(CachedResponse { body, signature })
    }
}

/// Reads `response`'s body into memory, bounded by `cap` bytes. Rejects up
/// front when a `Content-Length` header already exceeds `cap`, and otherwise
/// streams the body chunk by chunk, failing open the moment the running total
/// would exceed `cap` — so a relay that omits or lies about `Content-Length`
/// and streams an unbounded chunked body still can't grow the buffer past the
/// cap.
async fn read_body_capped(mut response: reqwest::Response, cap: usize) -> Option<Vec<u8>> {
    if response.content_length().is_some_and(|n| n > cap as u64) {
        return None;
    }
    let mut buf = Vec::new();
    while let Some(chunk) = response.chunk().await.ok()? {
        if buf.len() + chunk.len() > cap {
            return None;
        }
        buf.extend_from_slice(&chunk);
    }
    Some(buf)
}

fn header_string(headers: &reqwest::header::HeaderMap, name: &str) -> Option<String> {
    headers.get(name)?.to_str().ok().map(str::to_string)
}

/// The current wall-clock time as a UTC RFC3339 string (`YYYY-MM-DDTHH:MM:SSZ`),
/// the shape `verify_manifest` compares lexically against the manifest's
/// `expiresAt`/`issuedAt`. Uses Howard Hinnant's `civil_from_days` so the
/// staticlib carries no date crate. A clock before the Unix epoch clamps to
/// epoch (harmless: an early clock only ever makes a manifest look fresher, and
/// with empty pinned roots nothing verifies regardless).
fn now_rfc3339() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let (days, secs_of_day) = ((secs / 86_400) as i64, secs % 86_400);
    let (hh, mm, ss) = (
        secs_of_day / 3_600,
        (secs_of_day % 3_600) / 60,
        secs_of_day % 60,
    );
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if month <= 2 { year + 1 } else { year };
    format!("{year:04}-{month:02}-{day:02}T{hh:02}:{mm:02}:{ss:02}Z")
}

/// Parses `max-age=<secs>` out of a `Cache-Control` header; absent/unparseable
/// → `Duration::ZERO` (the entry is immediately stale and revalidates via ETag
/// on the next fetch rather than being reused blindly).
fn cache_max_age(headers: &reqwest::header::HeaderMap) -> Duration {
    let Some(value) = headers
        .get(reqwest::header::CACHE_CONTROL)
        .and_then(|v| v.to_str().ok())
    else {
        return Duration::ZERO;
    };
    for directive in value.split(',') {
        if let Some(secs) = directive.trim().strip_prefix("max-age=")
            && let Ok(secs) = secs.trim().parse::<u64>()
        {
            return Duration::from_secs(secs);
        }
    }
    Duration::ZERO
}

fn unique(items: &[String]) -> Vec<String> {
    let mut seen = HashSet::new();
    items
        .iter()
        .filter(|item| seen.insert((*item).clone()))
        .cloned()
        .collect()
}

impl RelayFetchClient {
    async fn resolve_idls(&self, program_ids: Vec<String>) -> HashMap<String, ResolvedProgramIdl> {
        let mut set = tokio::task::JoinSet::new();
        for program_id in program_ids {
            let client = self.clone();
            set.spawn(async move {
                let resolved = client.program_idl_async(&program_id).await;
                (program_id, resolved)
            });
        }
        let mut out = HashMap::new();
        while let Some(joined) = set.join_next().await {
            if let Ok((program_id, Some(resolved))) = joined {
                out.insert(program_id, resolved);
            }
        }
        out
    }

    async fn resolve_mints(&self, accounts: Vec<String>) -> HashMap<String, ResolvedMint> {
        let mut set = tokio::task::JoinSet::new();
        for account in accounts {
            let client = self.clone();
            set.spawn(async move {
                let resolved = client.mint_async(&account).await;
                (account, resolved)
            });
        }
        let mut out = HashMap::new();
        while let Some(joined) = set.join_next().await {
            if let Ok((account, Some(resolved))) = joined {
                out.insert(account, resolved);
            }
        }
        out
    }
}

/// The IDL/spec/mint augmentation for a decode, fetched concurrently. The
/// inspection report is NOT fetched here — the app passes it in — so demo mode
/// (which supplies the proposal + inspection as fixtures and has no live relay)
/// is unaffected: these three fetches simply fail open to empty.
pub struct DecodeAugmentation {
    pub idls: HashMap<String, ResolvedProgramIdl>,
    pub specs: HashMap<String, Vec<DecodeSpec>>,
    pub resolved_mints: HashMap<String, ResolvedMint>,
    /// The accepted decode-registry manifest `issuedAt`, or `None` if no
    /// manifest verified this fetch (inert path — `specs` is then empty).
    pub accepted_manifest_issued_at: Option<String>,
}

impl RelayFetchClient {
    /// Fetches IDLs, the signed spec registry, and mint metadata concurrently
    /// under one `block_on` (the `*_async` forms only — no nested `block_on`).
    /// `last_accepted_manifest_issued_at` is the app-persisted floor (from a
    /// prior decode) below which a manifest is rejected as a rollback; `None`
    /// accepts any valid, non-expired manifest.
    pub fn fetch_decode_augmentation(
        &self,
        program_ids: &[String],
        mint_accounts: &[String],
        last_accepted_manifest_issued_at: Option<&str>,
    ) -> DecodeAugmentation {
        let programs = unique(program_ids);
        let accounts = unique(mint_accounts);
        let now = now_rfc3339();
        runtime().block_on(async {
            let (idls, resolved_mints, (specs, accepted_manifest_issued_at)) = tokio::join!(
                self.resolve_idls(programs),
                self.resolve_mints(accounts),
                self.decode_registry_async(&now, last_accepted_manifest_issued_at),
            );
            DecodeAugmentation {
                idls,
                specs,
                resolved_mints,
                accepted_manifest_issued_at,
            }
        })
    }
}

struct CachedEntry {
    body: Vec<u8>,
    /// Stored verbatim, including the surrounding quotes, so `If-None-Match`
    /// echoes exactly what the relay's `if_none_match_hits` compares against.
    etag: Option<String>,
    /// Retained for the registry entry so a `304`/fresh hit can rebuild the
    /// signed `DecodeRegistryResponse` (the signature rides an HTTP header, not
    /// the body, and a `304` carries no body or header).
    signature: Option<String>,
    stored_at: Instant,
    max_age: Duration,
}

/// Client-side HTTP cache keyed on request URL, reconstructing the
/// Cache-Control/ETag/304 behavior Swift got for free from `URLSession`.
struct HttpCache {
    entries: Mutex<HashMap<String, CachedEntry>>,
    capacity: usize,
}

impl HttpCache {
    fn new(capacity: usize) -> Self {
        Self {
            entries: Mutex::new(HashMap::new()),
            capacity,
        }
    }

    fn fresh(&self, url: &str) -> Option<CachedResponse> {
        let map = self.entries.lock().unwrap_or_else(|e| e.into_inner());
        let entry = map.get(url)?;
        (entry.stored_at.elapsed() < entry.max_age).then(|| CachedResponse {
            body: entry.body.clone(),
            signature: entry.signature.clone(),
        })
    }

    fn etag(&self, url: &str) -> Option<String> {
        self.entries
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(url)
            .and_then(|e| e.etag.clone())
    }

    fn revalidate(&self, url: &str, max_age: Duration) -> Option<CachedResponse> {
        let mut map = self.entries.lock().unwrap_or_else(|e| e.into_inner());
        let entry = map.get_mut(url)?;
        entry.stored_at = Instant::now();
        entry.max_age = max_age;
        Some(CachedResponse {
            body: entry.body.clone(),
            signature: entry.signature.clone(),
        })
    }

    fn store(&self, url: &str, entry: CachedEntry) {
        let mut map = self.entries.lock().unwrap_or_else(|e| e.into_inner());
        if !map.contains_key(url)
            && map.len() >= self.capacity
            && let Some(oldest) = map
                .iter()
                .min_by_key(|(_, e)| e.stored_at)
                .map(|(k, _)| k.clone())
        {
            map.remove(&oldest);
        }
        map.insert(url.to_string(), entry);
    }
}

#[cfg(test)]
mod fetch_tests {
    use super::*;
    use crate::decode::registry::DECODE_REGISTRY_ROOT_KEYS;

    pub(crate) const IDL_BODY: &str = r#"{"ok":true,"kind":"program_idl","program":"whirL",
      "idl":{"metadata":{"name":"whirlpool"},"instructions":[
        {"name":"swap","discriminator":[1,2,3,4,5,6,7,8],
         "args":[{"name":"amount","type":"u64"}]}]},
      "hash":"abc123","slot":4242,"authority":null}"#;

    pub(crate) const MINT_BODY: &str = r#"{"kind":"mint_metadata","account":"ACCT","mint":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v","decimals":6,"symbol":"USDC"}"#;

    fn client_for(server: &mockito::Server) -> RelayFetchClient {
        RelayFetchClient::new(&server.url(), None).unwrap()
    }

    #[test]
    fn fetch_program_idl_parses_into_resolved_idl() {
        let mut server = mockito::Server::new();
        let _m = server
            .mock("GET", "/cosign/v1/programs/whirL/idl")
            .with_status(200)
            .with_header("content-type", "application/json")
            .with_body(IDL_BODY)
            .create();
        let c = client_for(&server);
        let resolved = runtime().block_on(c.program_idl_async("whirL")).unwrap();
        assert_eq!(resolved.document.name, "whirlpool");
        assert_eq!(
            resolved.provenance,
            crate::decode::DecodeProvenance::OnChainIdl {
                idl_name: "whirlpool".into(),
                hash: "abc123".into(),
                slot: 4242
            }
        );
    }

    #[test]
    fn fetch_mint_parses_into_resolved_mint() {
        let mut server = mockito::Server::new();
        let _m = server
            .mock("GET", "/cosign/v1/mints/ACCT")
            .with_status(200)
            .with_body(MINT_BODY)
            .create();
        let c = client_for(&server);
        let mint = runtime().block_on(c.mint_async("ACCT")).unwrap();
        assert_eq!(mint.mint, "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v");
        assert_eq!(mint.decimals, 6);
        assert_eq!(mint.symbol.as_deref(), Some("USDC"));
    }

    #[test]
    fn fetch_decode_registry_fails_safe_to_empty_with_the_shipped_empty_keys() {
        // A well-formed signed bundle + signature header, but the SHIPPED public
        // key map is empty, so verification fails → zero specs. This is today's
        // production behavior and the fail-safe default.
        let mut server = mockito::Server::new();
        let _m = server
            .mock("GET", "/cosign/v1/decode-registry")
            .with_status(200)
            .with_header("X-Cosign-Registry-Signature", "AAAA")
            .with_body(r#"{"schema":1,"keyId":"k1","specs":[]}"#)
            .create();
        assert!(DECODE_REGISTRY_ROOT_KEYS.is_empty());
        let (specs, accepted) = runtime()
            .block_on(client_for(&server).decode_registry_async("2026-08-10T00:00:00Z", None));
        assert!(specs.is_empty());
        assert!(accepted.is_none());
    }

    #[test]
    fn build_registry_specs_groups_verified_specs_by_program() {
        // The success path, exercised through the internal helper with a test key
        // (the shipped keys are empty). Uses the same signing helper as registry.rs.
        use crate::keypair;
        use base64::{Engine, engine::general_purpose::STANDARD};
        const MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let kp = keypair::from_mnemonic(MNEMONIC, "").unwrap();
        let bundle = r#"{"schema":1,"keyId":"k1","specs":[
          {"program":"P1","discriminator":[1],"mode":"standalone","layout":[],"action":"A","accounts":{},"template":"t","effects":[]},
          {"program":"P1","discriminator":[2],"mode":"standalone","layout":[],"action":"B","accounts":{},"template":"t","effects":[]},
          {"program":"P2","discriminator":[3],"mode":"standalone","layout":[],"action":"C","accounts":{},"template":"t","effects":[]}]}"#;
        let sig = keypair::sign(&kp.private_key, bundle.as_bytes());
        let response = crate::decode::wire::DecodeRegistryResponse {
            bundle_data: bundle.as_bytes().to_vec(),
            signature_base64: STANDARD.encode(sig),
        };
        let pk = STANDARD.encode(kp.public_key.to_bytes());
        let specs = build_registry_specs(&response, &[("k1", pk.as_str())]);
        assert_eq!(specs.get("P1").map(Vec::len), Some(2));
        assert_eq!(specs.get("P2").map(Vec::len), Some(1));
    }

    #[test]
    fn every_endpoint_fails_open_on_500() {
        let mut server = mockito::Server::new();
        let _idl = server
            .mock("GET", "/cosign/v1/programs/P/idl")
            .with_status(500)
            .create();
        let _mint = server
            .mock("GET", "/cosign/v1/mints/A")
            .with_status(500)
            .create();
        let _reg = server
            .mock("GET", "/cosign/v1/decode-registry")
            .with_status(500)
            .create();
        let c = client_for(&server);
        assert!(runtime().block_on(c.program_idl_async("P")).is_none());
        assert!(runtime().block_on(c.mint_async("A")).is_none());
        assert!(
            runtime()
                .block_on(c.decode_registry_async("2026-08-10T00:00:00Z", None))
                .0
                .is_empty()
        );
    }

    #[test]
    fn fails_open_on_malformed_json() {
        let mut server = mockito::Server::new();
        let _m = server
            .mock("GET", "/cosign/v1/programs/P/idl")
            .with_status(200)
            .with_body("{ this is not json")
            .create();
        assert!(
            runtime()
                .block_on(client_for(&server).program_idl_async("P"))
                .is_none()
        );
    }

    #[test]
    fn registry_fails_open_when_signature_header_absent() {
        let mut server = mockito::Server::new();
        let _m = server
            .mock("GET", "/cosign/v1/decode-registry")
            .with_status(200)
            .with_body(r#"{"schema":1,"keyId":"k1","specs":[]}"#)
            .create();
        // No X-Cosign-Registry-Signature header → empty signature → verify fails → empty.
        assert!(
            runtime()
                .block_on(client_for(&server).decode_registry_async("2026-08-10T00:00:00Z", None))
                .0
                .is_empty()
        );
    }

    #[test]
    fn fails_open_on_network_error() {
        // Port 1 refuses connections: a transport error must fail open, not panic.
        let c = RelayFetchClient::new("http://127.0.0.1:1", None).unwrap();
        assert!(runtime().block_on(c.program_idl_async("P")).is_none());
        assert!(runtime().block_on(c.mint_async("A")).is_none());
        assert!(
            runtime()
                .block_on(c.decode_registry_async("2026-08-10T00:00:00Z", None))
                .0
                .is_empty()
        );
    }

    #[test]
    fn gated_off_capability_skips_the_fetch() {
        let mut server = mockito::Server::new();
        // Serve a valid body, but the client advertises only mint_metadata.
        let _m = server
            .mock("GET", "/cosign/v1/programs/P/idl")
            .with_status(200)
            .with_body(IDL_BODY)
            .expect(0) // must never be requested
            .create();
        let c = RelayFetchClient::new(&server.url(), Some(vec![CAP_MINT_METADATA.into()])).unwrap();
        assert!(runtime().block_on(c.program_idl_async("P")).is_none());
        _m.assert(); // asserts 0 calls
    }
}

#[cfg(test)]
mod body_cap_tests {
    use super::*;

    #[test]
    fn rejects_over_cap_and_accepts_at_cap() {
        let mut server = mockito::Server::new();
        let body = "x".repeat(100);
        let _m = server
            .mock("GET", "/body")
            .with_status(200)
            .with_body(&body)
            .expect(2)
            .create();
        let url = format!("{}/body", server.url());
        let client = reqwest::Client::new();

        let over_cap = runtime().block_on(async {
            let resp = client.get(&url).send().await.unwrap();
            read_body_capped(resp, body.len() - 1).await
        });
        assert!(over_cap.is_none());

        let at_cap = runtime().block_on(async {
            let resp = client.get(&url).send().await.unwrap();
            read_body_capped(resp, body.len()).await
        });
        assert_eq!(at_cap.map(|b| b.len()), Some(body.len()));
    }
}

#[cfg(test)]
impl RelayFetchClient {
    fn decode_registry_via_test_keys(
        &self,
        keys: &[(&str, &str)],
    ) -> HashMap<String, Vec<DecodeSpec>> {
        runtime().block_on(async {
            let Some(url) = self.decode_registry_url() else {
                return HashMap::new();
            };
            let Some(cached) = self.get_cacheable(&url).await else {
                return HashMap::new();
            };
            let response = DecodeRegistryResponse {
                bundle_data: cached.body,
                signature_base64: cached.signature.unwrap_or_default(),
            };
            build_registry_specs(&response, keys)
        })
    }

    /// Test seam mirroring `decode_registry_via_test_keys` but exercising the
    /// full manifest→bundle chain with an injected root set (the shipped
    /// `DECODE_REGISTRY_ROOT_KEYS` is empty, so the production path is always
    /// inert and can't reach the success branch on its own).
    fn decode_registry_via_test_roots(
        &self,
        root_keys: &[(&str, &str)],
        now_rfc3339: &str,
        last_accepted_issued_at: Option<&str>,
    ) -> (HashMap<String, Vec<DecodeSpec>>, Option<String>) {
        runtime().block_on(self.decode_registry_with_roots(
            root_keys,
            now_rfc3339,
            last_accepted_issued_at,
        ))
    }
}

#[cfg(test)]
mod cache_tests {
    use super::fetch_tests::IDL_BODY;
    use super::*;

    fn cacheable_idl_mock(server: &mut mockito::Server, calls: usize) -> mockito::Mock {
        server
            .mock("GET", "/cosign/v1/programs/P/idl")
            .with_status(200)
            .with_header("ETag", "\"hash-1\"")
            .with_header("Cache-Control", "public, max-age=3600")
            .with_body(IDL_BODY)
            .expect(calls)
            .create()
    }

    #[test]
    fn a_fresh_entry_is_served_without_a_second_request() {
        let mut server = mockito::Server::new();
        let mock = cacheable_idl_mock(&mut server, 1); // exactly one network request
        let c = RelayFetchClient::new(&server.url(), None).unwrap();

        let first = runtime().block_on(c.program_idl_async("P")).unwrap();
        let second = runtime().block_on(c.program_idl_async("P")).unwrap();
        assert_eq!(first.document.name, second.document.name);
        mock.assert(); // the second call was a fresh cache hit — server hit once
    }

    #[test]
    fn a_304_revalidation_is_a_cache_hit() {
        let mut server = mockito::Server::new();
        // First request: 200 with a max-age=0 body so the entry is immediately stale
        // but carries an ETag; second request must send If-None-Match and get 304.
        let first = server
            .mock("GET", "/cosign/v1/programs/P/idl")
            .with_status(200)
            .with_header("ETag", "\"hash-1\"")
            .with_header("Cache-Control", "public, max-age=0")
            .with_body(IDL_BODY)
            .expect(1)
            .create();
        let revalidate = server
            .mock("GET", "/cosign/v1/programs/P/idl")
            .match_header("if-none-match", "\"hash-1\"")
            .with_status(304)
            .with_header("Cache-Control", "public, max-age=3600")
            .expect(1)
            .create();

        let c = RelayFetchClient::new(&server.url(), None).unwrap();
        let a = runtime().block_on(c.program_idl_async("P")).unwrap();
        let b = runtime().block_on(c.program_idl_async("P")).unwrap(); // 304 → cached body reused
        assert_eq!(a.document.name, b.document.name);
        first.assert();
        revalidate.assert();
    }

    #[test]
    fn the_registry_signature_survives_a_fresh_cache_hit() {
        use crate::keypair;
        use base64::{Engine, engine::general_purpose::STANDARD};
        const MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let kp = keypair::from_mnemonic(MNEMONIC, "").unwrap();
        let bundle = r#"{"schema":1,"keyId":"reg","specs":[
          {"program":"P1","discriminator":[1],"mode":"standalone","layout":[],"action":"A","accounts":{},"template":"t","effects":[]}]}"#;
        let sig = STANDARD.encode(keypair::sign(&kp.private_key, bundle.as_bytes()));
        let pk = STANDARD.encode(kp.public_key.to_bytes());

        let mut server = mockito::Server::new();
        let mock = server
            .mock("GET", "/cosign/v1/decode-registry")
            .with_status(200)
            .with_header("ETag", "\"reg-1\"")
            .with_header("Cache-Control", "public, max-age=3600")
            .with_header("X-Cosign-Registry-Signature", &sig)
            .with_body(bundle)
            .expect(1)
            .create();

        let c = RelayFetchClient::new(&server.url(), None).unwrap();
        // First call caches body + signature; verify the cached signature still
        // reconstructs a verifiable response on the second (cache-hit) call.
        let inputs1 = c.decode_registry_via_test_keys(&[("reg", pk.as_str())]);
        let inputs2 = c.decode_registry_via_test_keys(&[("reg", pk.as_str())]);
        assert_eq!(inputs1.get("P1").map(Vec::len), Some(1));
        assert_eq!(inputs2.get("P1").map(Vec::len), Some(1)); // signature survived the cache hit
        mock.assert(); // one network request
    }

    #[test]
    fn eviction_bounds_the_cache_at_capacity() {
        // Fill past capacity; the oldest entry is evicted. A CACHE_CAPACITY of 256
        // is impractical to fill in a test, so assert the HttpCache primitive directly.
        let cache = HttpCache::new(2);
        cache.store("a", entry(b"A"));
        std::thread::sleep(std::time::Duration::from_millis(2));
        cache.store("b", entry(b"B"));
        std::thread::sleep(std::time::Duration::from_millis(2));
        cache.store("c", entry(b"C")); // evicts "a" (oldest)
        assert!(cache.fresh("a").is_none());
        assert!(cache.fresh("b").is_some());
        assert!(cache.fresh("c").is_some());
    }

    fn entry(body: &[u8]) -> CachedEntry {
        CachedEntry {
            body: body.to_vec(),
            etag: None,
            signature: None,
            stored_at: std::time::Instant::now(),
            max_age: std::time::Duration::from_secs(3600),
        }
    }
}

#[cfg(test)]
mod fanout_tests {
    use super::*;

    // Reuse the fetch_tests fixtures via full paths to keep them in one place.
    use super::fetch_tests::{IDL_BODY, MINT_BODY};

    fn full_client(server: &mockito::Server) -> RelayFetchClient {
        RelayFetchClient::new(&server.url(), None).unwrap()
    }

    #[test]
    fn fetch_decode_augmentation_resolves_idls_specs_and_mints_and_skips_inspection() {
        let mut server = mockito::Server::new();
        let _idl = server
            .mock("GET", "/cosign/v1/programs/whirL/idl")
            .with_status(200)
            .with_body(IDL_BODY)
            .create();
        let _mint = server
            .mock("GET", "/cosign/v1/mints/ACCT")
            .with_status(200)
            .with_body(MINT_BODY)
            .create();
        let _reg = server
            .mock("GET", "/cosign/v1/decode-registry")
            .with_status(200)
            .with_body(r#"{"schema":1,"keyId":"k1","specs":[]}"#)
            .create();
        // No inspection endpoint is mocked at all: `fetch_decode_augmentation`
        // takes no inspection target and must never request one.

        let augmentation = full_client(&server).fetch_decode_augmentation(
            &["whirL".into()],
            &["ACCT".into()],
            None,
        );

        assert_eq!(
            augmentation
                .idls
                .get("whirL")
                .map(|i| i.document.name.clone()),
            Some("whirlpool".into())
        );
        assert_eq!(
            augmentation.resolved_mints.get("ACCT").map(|m| m.decimals),
            Some(6)
        );
        assert!(augmentation.specs.is_empty()); // empty shipped keys → fail-safe empty
    }

    #[test]
    fn fetch_decode_augmentation_fans_out_idl_and_mint_fetches_concurrently() {
        use std::sync::Arc;
        use std::sync::atomic::{AtomicUsize, Ordering};

        // Prove the fan-out by observing overlap rather than timing it. Each
        // handler marks itself active on entry, holds briefly so the window stays
        // open, then marks itself done; the peak count of simultaneously-active
        // handlers reaches two only if the IDL and mint fetches actually run
        // concurrently — a serial fetch never sees more than one at a time. Unlike
        // an elapsed-time threshold, this can't false-fail when a loaded CI runner
        // adds latency to a genuinely-concurrent run.
        let active = Arc::new(AtomicUsize::new(0));
        let peak = Arc::new(AtomicUsize::new(0));
        let hold = Duration::from_millis(150);

        let mut server = mockito::Server::new();
        let (a_idl, p_idl) = (active.clone(), peak.clone());
        let _idl = server
            .mock("GET", "/cosign/v1/programs/whirL/idl")
            .with_status(200)
            .with_chunked_body(move |w| {
                p_idl.fetch_max(a_idl.fetch_add(1, Ordering::SeqCst) + 1, Ordering::SeqCst);
                std::thread::sleep(hold);
                a_idl.fetch_sub(1, Ordering::SeqCst);
                w.write_all(IDL_BODY.as_bytes())
            })
            .create();
        let (a_mint, p_mint) = (active.clone(), peak.clone());
        let _mint = server
            .mock("GET", "/cosign/v1/mints/ACCT")
            .with_status(200)
            .with_chunked_body(move |w| {
                p_mint.fetch_max(a_mint.fetch_add(1, Ordering::SeqCst) + 1, Ordering::SeqCst);
                std::thread::sleep(hold);
                a_mint.fetch_sub(1, Ordering::SeqCst);
                w.write_all(MINT_BODY.as_bytes())
            })
            .create();
        let _reg = server
            .mock("GET", "/cosign/v1/decode-registry")
            .with_status(500)
            .create();

        let augmentation = full_client(&server).fetch_decode_augmentation(
            &["whirL".into()],
            &["ACCT".into()],
            None,
        );

        assert!(augmentation.idls.contains_key("whirL"));
        assert!(augmentation.resolved_mints.contains_key("ACCT"));
        assert_eq!(
            peak.load(Ordering::SeqCst),
            2,
            "IDL and mint fetches did not overlap (peak concurrent handlers = 1); the fan-out regressed to serial"
        );
    }
}

#[cfg(test)]
mod client_registry_tests {
    use super::fetch_tests;
    use super::*;

    #[test]
    fn shared_client_reuses_the_cache_across_calls() {
        let mut server = mockito::Server::new();
        let _idl = server
            .mock("GET", "/cosign/v1/programs/P/idl")
            .with_status(200)
            .with_header("ETag", "\"h1\"")
            .with_header("Cache-Control", "public, max-age=3600")
            .with_body(fetch_tests::IDL_BODY)
            .expect(1) // one network hit despite two fetches on the shared client
            .create();
        let caps: Vec<String> = vec![CAP_PROGRAM_IDL.to_string()];
        let a = shared_client(&server.url(), &caps).unwrap();
        let b = shared_client(&server.url(), &caps).unwrap();
        let _ = runtime().block_on(a.program_idl_async("P"));
        let _ = runtime().block_on(b.program_idl_async("P")); // fresh cache hit on the same shared client
        _idl.assert();
    }

    #[test]
    fn shared_client_with_empty_caps_assumes_all_capabilities() {
        let mut server = mockito::Server::new();
        let _idl = server
            .mock("GET", "/cosign/v1/programs/P/idl")
            .with_status(200)
            .with_body(fetch_tests::IDL_BODY)
            .expect(1) // empty caps ⇒ assume-all ⇒ the IDL fetch fires (before this fix it would be 0)
            .create();
        let client = shared_client(&server.url(), &[]).unwrap(); // EMPTY caps
        assert!(runtime().block_on(client.program_idl_async("P")).is_some());
        _idl.assert();
    }
}

#[cfg(test)]
mod spike_tests {
    use super::*;

    #[test]
    fn block_on_drives_async_reqwest_against_a_mock() {
        let mut server = mockito::Server::new();
        let mock = server
            .mock("GET", "/ping")
            .with_status(200)
            .with_body("pong")
            .create();
        let url = format!("{}/ping", server.url());

        let body = runtime().block_on(async {
            let client = reqwest::Client::new();
            let resp = client.get(&url).send().await.unwrap();
            resp.text().await.unwrap()
        });

        assert_eq!(body, "pong");
        mock.assert();
    }

    #[test]
    fn sequential_block_on_calls_do_not_panic() {
        // Guards the nested-block_on hazard by construction: two sequential
        // block_on calls on the shared runtime from a plain test thread must
        // each complete without "cannot start a runtime from within a runtime".
        let a = runtime().block_on(async { 1 + 1 });
        let b = runtime().block_on(async { 2 + 2 });
        assert_eq!((a, b), (2, 4));
    }

    #[test]
    fn block_on_of_a_join_fans_out_without_nesting() {
        // Models the real decode fan-out shape: a single block_on wrapping a
        // tokio::join! of several concurrent requests, all on the shared
        // runtime. Solana's blocking RpcClient does its own block_on and
        // returns before this one starts, so this join is never nested inside
        // another runtime.
        let mut server = mockito::Server::new();
        let mock_a = server
            .mock("GET", "/a")
            .with_status(200)
            .with_body("a")
            .create();
        let mock_b = server
            .mock("GET", "/b")
            .with_status(200)
            .with_body("b")
            .create();
        let url_a = format!("{}/a", server.url());
        let url_b = format!("{}/b", server.url());

        let (body_a, body_b) = runtime().block_on(async {
            let client = reqwest::Client::new();
            let fetch_a = async {
                client
                    .get(&url_a)
                    .send()
                    .await
                    .unwrap()
                    .text()
                    .await
                    .unwrap()
            };
            let fetch_b = async {
                client
                    .get(&url_b)
                    .send()
                    .await
                    .unwrap()
                    .text()
                    .await
                    .unwrap()
            };
            tokio::join!(fetch_a, fetch_b)
        });

        assert_eq!((body_a.as_str(), body_b.as_str()), ("a", "b"));
        mock_a.assert();
        mock_b.assert();
    }
}

#[cfg(test)]
mod url_tests {
    use super::*;

    fn client(base: &str, caps: Option<Vec<String>>) -> RelayFetchClient {
        RelayFetchClient::new(base, caps).unwrap()
    }
    fn all_caps() -> Vec<String> {
        vec![
            CAP_PROGRAM_IDL.into(),
            CAP_DECODE_REGISTRY.into(),
            CAP_MINT_METADATA.into(),
        ]
    }

    #[test]
    fn builds_all_decode_urls() {
        let c = client("https://relay.example.com", Some(all_caps()));
        assert_eq!(
            c.program_idl_url("PROG").unwrap().as_str(),
            "https://relay.example.com/cosign/v1/programs/PROG/idl"
        );
        assert_eq!(
            c.mint_url("ACCT").unwrap().as_str(),
            "https://relay.example.com/cosign/v1/mints/ACCT"
        );
        assert_eq!(
            c.decode_registry_url().unwrap().as_str(),
            "https://relay.example.com/cosign/v1/decode-registry"
        );
    }

    #[test]
    fn tolerates_a_base_url_with_a_trailing_slash_and_path_prefix() {
        let c = client("https://host.example.com/relay/", Some(all_caps()));
        assert_eq!(
            c.program_idl_url("PROG").unwrap().as_str(),
            "https://host.example.com/relay/cosign/v1/programs/PROG/idl"
        );
    }

    #[test]
    fn none_capabilities_assumes_all_supported() {
        let c = client("https://relay.example.com", None);
        assert!(c.program_idl_url("PROG").is_some());
        assert!(c.decode_registry_url().is_some());
        assert!(c.mint_url("A").is_some());
    }

    #[test]
    fn a_known_set_gates_unsupported_endpoints_to_none() {
        // Only mint_metadata advertised: every other decode URL is skipped.
        let c = client(
            "https://relay.example.com",
            Some(vec![CAP_MINT_METADATA.into()]),
        );
        assert!(c.mint_url("A").is_some());
        assert!(c.program_idl_url("PROG").is_none());
        assert!(c.decode_registry_url().is_none());
    }

    #[test]
    fn rejects_an_unparseable_base_url() {
        assert!(RelayFetchClient::new("not a url", None).is_none());
    }
}

#[cfg(test)]
mod manifest_chain_tests {
    use super::*;
    use crate::keypair;
    use base64::{Engine, engine::general_purpose::STANDARD};

    const MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

    fn client_for(server: &mockito::Server) -> RelayFetchClient {
        RelayFetchClient::new(&server.url(), None).unwrap()
    }

    /// A bundle whose `keyId` is `pub-key`, signed by `publisher`.
    fn bundle_signed_by(publisher: &keypair::KeyPair) -> (String, String) {
        let bundle = r#"{"schema":1,"keyId":"pub-key","specs":[
          {"program":"P1","discriminator":[1],"mode":"standalone","layout":[],"action":"A","accounts":{},"template":"t","effects":[]}]}"#;
        let sig = STANDARD.encode(keypair::sign(&publisher.private_key, bundle.as_bytes()));
        (bundle.to_string(), sig)
    }

    /// A manifest listing `pub-key → publisher_pk_b64`, signed by `root`.
    fn manifest_signed_by(
        root: &keypair::KeyPair,
        publisher_pk_b64: &str,
        issued: &str,
        expires: &str,
    ) -> (String, String) {
        let manifest = format!(
            r#"{{"schema":1,"issuedAt":"{issued}","expiresAt":"{expires}","rootKeyId":"root","publishers":[{{"keyId":"pub-key","publicKey":"{publisher_pk_b64}","status":"active"}}]}}"#
        );
        let sig = STANDARD.encode(keypair::sign(&root.private_key, manifest.as_bytes()));
        (manifest, sig)
    }

    fn root_and_publisher() -> (keypair::KeyPair, keypair::KeyPair, String, String) {
        // Distinct keys from one known-good mnemonic via the passphrase.
        let root = keypair::from_mnemonic(MNEMONIC, "").unwrap();
        let publisher = keypair::from_mnemonic(MNEMONIC, "publisher").unwrap();
        let root_pk = STANDARD.encode(root.public_key.to_bytes());
        let publisher_pk = STANDARD.encode(publisher.public_key.to_bytes());
        (root, publisher, root_pk, publisher_pk)
    }

    #[test]
    fn valid_manifest_chains_publisher_key_to_the_bundle() {
        let (root, publisher, root_pk, publisher_pk) = root_and_publisher();
        let (bundle, bundle_sig) = bundle_signed_by(&publisher);
        let (manifest, manifest_sig) = manifest_signed_by(
            &root,
            &publisher_pk,
            "2026-08-01T00:00:00Z",
            "2026-08-15T00:00:00Z",
        );

        let mut server = mockito::Server::new();
        let _m = server
            .mock("GET", "/cosign/v1/decode-keys")
            .with_status(200)
            .with_header("X-Cosign-Registry-Keys-Signature", &manifest_sig)
            .with_body(&manifest)
            .create();
        let _b = server
            .mock("GET", "/cosign/v1/decode-registry")
            .with_status(200)
            .with_header("X-Cosign-Registry-Signature", &bundle_sig)
            .with_body(&bundle)
            .create();

        let roots = [("root", root_pk.as_str())];
        let (specs, accepted) = client_for(&server).decode_registry_via_test_roots(
            &roots,
            "2026-08-10T00:00:00Z",
            None,
        );
        assert_eq!(specs.get("P1").map(Vec::len), Some(1));
        assert_eq!(accepted.as_deref(), Some("2026-08-01T00:00:00Z"));
    }

    #[test]
    fn no_manifest_yields_empty_specs_even_with_a_valid_bundle() {
        let (_root, publisher, root_pk, _publisher_pk) = root_and_publisher();
        let (bundle, bundle_sig) = bundle_signed_by(&publisher);

        let mut server = mockito::Server::new();
        let _k = server
            .mock("GET", "/cosign/v1/decode-keys")
            .with_status(404)
            .create();
        let _b = server
            .mock("GET", "/cosign/v1/decode-registry")
            .with_status(200)
            .with_header("X-Cosign-Registry-Signature", &bundle_sig)
            .with_body(&bundle)
            .create();

        let roots = [("root", root_pk.as_str())];
        let (specs, accepted) = client_for(&server).decode_registry_via_test_roots(
            &roots,
            "2026-08-10T00:00:00Z",
            None,
        );
        assert!(specs.is_empty());
        assert!(accepted.is_none());
    }

    #[test]
    fn expired_manifest_yields_empty_specs_even_with_a_valid_bundle() {
        let (root, publisher, root_pk, publisher_pk) = root_and_publisher();
        let (bundle, bundle_sig) = bundle_signed_by(&publisher);
        let (manifest, manifest_sig) = manifest_signed_by(
            &root,
            &publisher_pk,
            "2026-08-01T00:00:00Z",
            "2026-08-15T00:00:00Z",
        );

        let mut server = mockito::Server::new();
        let _m = server
            .mock("GET", "/cosign/v1/decode-keys")
            .with_status(200)
            .with_header("X-Cosign-Registry-Keys-Signature", &manifest_sig)
            .with_body(&manifest)
            .create();
        let _b = server
            .mock("GET", "/cosign/v1/decode-registry")
            .with_status(200)
            .with_header("X-Cosign-Registry-Signature", &bundle_sig)
            .with_body(&bundle)
            .create();

        let roots = [("root", root_pk.as_str())];
        // now is AFTER expiresAt → manifest expired → empty specs, no accepted issued_at.
        let (specs, accepted) = client_for(&server).decode_registry_via_test_roots(
            &roots,
            "2026-08-20T00:00:00Z",
            None,
        );
        assert!(specs.is_empty());
        assert!(accepted.is_none());
    }

    #[test]
    fn empty_roots_keep_the_registry_inert_even_with_a_valid_chain() {
        let (root, publisher, _root_pk, publisher_pk) = root_and_publisher();
        let (bundle, bundle_sig) = bundle_signed_by(&publisher);
        let (manifest, manifest_sig) = manifest_signed_by(
            &root,
            &publisher_pk,
            "2026-08-01T00:00:00Z",
            "2026-08-15T00:00:00Z",
        );

        let mut server = mockito::Server::new();
        let _m = server
            .mock("GET", "/cosign/v1/decode-keys")
            .with_status(200)
            .with_header("X-Cosign-Registry-Keys-Signature", &manifest_sig)
            .with_body(&manifest)
            .create();
        let _b = server
            .mock("GET", "/cosign/v1/decode-registry")
            .with_status(200)
            .with_header("X-Cosign-Registry-Signature", &bundle_sig)
            .with_body(&bundle)
            .create();

        // The shipped state: no pinned roots → nothing verifies → inert.
        assert!(DECODE_REGISTRY_ROOT_KEYS.is_empty());
        let (specs, accepted) = runtime()
            .block_on(client_for(&server).decode_registry_async("2026-08-10T00:00:00Z", None));
        assert!(specs.is_empty());
        assert!(accepted.is_none());
    }
}
