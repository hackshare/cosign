//! Background worker that builds and refreshes the membership index: one full
//! scan to build, a filtered `programSubscribe` for live deltas, and a periodic
//! reconcile scan as the correctness backstop. Runs on its own thread.

use std::io::ErrorKind;
use std::ops::ControlFlow;
use std::thread::{self, JoinHandle};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use base64::{Engine, engine::general_purpose::STANDARD as BASE64_STANDARD};
use serde_json::{Value, json};
use solana_sdk::pubkey::Pubkey;
use squads_multisig::anchor_lang::{AccountDeserialize, Discriminator};
use squads_multisig::state::Multisig;
use tungstenite::Message;

use crate::membership_index::{IndexError, MembershipIndex};
use crate::rpc::RpcClient;
use crate::squads::SquadsClient;

const RECONCILE_INTERVAL: Duration = Duration::from_secs(60 * 60);
/// After a reconcile scan fails, wait this long before retrying instead of hammering
/// the upstream on every loop tick. Health does not depend on reconcile success, so a
/// failed backstop scan only delays the next gap-close; it does not stop serving.
const RECONCILE_RETRY_BACKOFF: Duration = Duration::from_secs(5 * 60);
const WS_READ_TIMEOUT: Duration = Duration::from_secs(30);
const RECONNECT_BACKOFF: Duration = Duration::from_secs(5);
/// The membership scan is a large getProgramAccounts (every Multisig account), which
/// can take far longer than a normal RPC call; give it generous headroom so the
/// reconcile backstop does not time out on big programs.
const INDEXER_RPC_TIMEOUT: Duration = Duration::from_secs(120);

fn now_unix() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Decode one account's raw bytes as a Multisig and upsert it. Returns false if the
/// bytes are not a Multisig (wrong discriminator / undeserializable), which the
/// caller treats as "ignore".
pub fn apply_account_bytes(
    index: &MembershipIndex,
    address: &Pubkey,
    data: &[u8],
    slot: u64,
) -> bool {
    let mut slice = data;
    match Multisig::try_deserialize(&mut slice) {
        Ok(ms) => index.upsert_multisig(address, &ms, slot).is_ok(),
        Err(_) => false,
    }
}

/// Refresh the index from upstream. The first run (no persisted scan slot) is a full
/// paginated scan; every run after passes `changedSinceSlot = last_scan_slot`, so it
/// streams only the accounts changed since last time. Upserting a Multisig replaces
/// that squad's membership rows, so member changes are absorbed here too. There is no
/// pruning: Squads v4 has no instruction to close a Multisig account, so none ever
/// vanish. On a scan or upsert failure it returns `Err` without advancing the slot or
/// the reconcile stamp, so the next run retries from the same point. An empty full
/// build (nothing returned on the very first scan) is likewise treated as not-yet-built
/// and retried, so a lagging upstream cannot make an empty index authoritative.
pub fn reconcile(
    index: &MembershipIndex,
    client: &SquadsClient,
    now_unix: i64,
) -> Result<usize, IndexError> {
    let since = match index.last_scan_slot() {
        0 => None,
        slot => Some(slot),
    };

    let mut count = 0usize;
    let mut upsert_error: Option<IndexError> = None;
    let slot = client
        .scan_multisigs(since, |address, ms| {
            match index.upsert_multisig(address, ms, 0) {
                Ok(()) => {
                    count += 1;
                    ControlFlow::Continue(())
                }
                Err(error) => {
                    // Stop the scan immediately; no point fetching more pages we
                    // cannot store.
                    upsert_error = Some(error);
                    ControlFlow::Break(())
                }
            }
        })
        .map_err(|error| IndexError::Scan(error.to_string()))?;

    if let Some(error) = upsert_error {
        return Err(error);
    }

    if !reconcile_should_advance(since, count) {
        return Ok(0);
    }

    index.set_last_scan_slot(slot)?;
    index.touch_reconcile(now_unix)?;
    if !index.build_complete() {
        index.mark_build_complete()?;
    }
    Ok(count)
}

/// Whether a completed reconcile should advance the persisted scan slot and build
/// stamp. An empty FULL build (no prior slot AND nothing returned) must NOT advance:
/// marking an empty index build-complete, combined with incremental follow-ups, would
/// permanently hide the existing squads. An empty incremental scan (nothing changed)
/// advances normally.
fn reconcile_should_advance(since: Option<u64>, count: usize) -> bool {
    since.is_some() || count > 0
}

pub fn spawn(
    index: &'static MembershipIndex,
    rpc_url: String,
    ws_url: Option<String>,
) -> JoinHandle<()> {
    thread::spawn(move || run(index, rpc_url, ws_url))
}

fn run(index: &'static MembershipIndex, rpc_url: String, ws_url: Option<String>) {
    index.set_healthy(false);
    let client = SquadsClient::new(RpcClient::new_with_timeout(rpc_url, INDEXER_RPC_TIMEOUT));

    // Populate the index before we even connect, so a warm restart serves from disk
    // once the subscription is live. reconcile marks build_complete on success.
    match reconcile(index, &client, now_unix()) {
        Ok(count) => println!("membership index built: {count} squads"),
        Err(error) => eprintln!("membership index initial build failed: {error}"),
    }

    let Some(ws_url) = ws_url else {
        // No subscription available: reconcile-only degraded mode. Health tracks the
        // last scan; staleness is bounded by RECONCILE_INTERVAL.
        loop {
            thread::sleep(RECONCILE_INTERVAL);
            index.set_healthy(reconcile(index, &client, now_unix()).is_ok());
        }
    };

    loop {
        if let Err(error) = subscribe_loop(index, &client, &ws_url) {
            eprintln!("membership index subscription ended: {error}");
        }
        index.set_healthy(false);
        eprintln!("membership index health: false (reconnecting)");
        // No full gap-scan on reconnect: upstream providers routinely cycle idle WS
        // connections, so reconnects are frequent, and a 15k-account scan each time is
        // both costly and drops reads to the live path for its duration. A brief
        // disconnect misses few deltas; the periodic reconcile (driven by the
        // persisted last-reconcile time) closes any gap. subscribe_loop re-asserts
        // health as soon as the socket reconnects.
        thread::sleep(RECONNECT_BACKOFF);
    }
}

/// Connect, subscribe to Multisig account changes, and pump notifications into the
/// index until the socket errors. Health is asserted as soon as the subscription is
/// live: the index is already current from the initial build and deltas now stream in
/// real time. An idle connection is kept alive with periodic pings, and the periodic
/// reconcile (a background correctness backstop, timed off the persisted last-reconcile
/// stamp) closes any gap; neither's failure drops health. Returns Err on socket failure
/// so `run` reconnects.
fn subscribe_loop(
    index: &MembershipIndex,
    client: &SquadsClient,
    ws_url: &str,
) -> Result<(), String> {
    let (mut socket, _response) = tungstenite::connect(ws_url).map_err(|e| e.to_string())?;
    set_read_timeout(&socket, WS_READ_TIMEOUT);

    let program_id = SquadsClient::default_program_id().to_string();
    let discriminator = bs58::encode(Multisig::DISCRIMINATOR).into_string();
    let subscribe = json!({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "programSubscribe",
        "params": [
            program_id,
            {
                "encoding": "base64",
                "commitment": "confirmed",
                "filters": [ { "memcmp": { "offset": 0, "bytes": discriminator } } ]
            }
        ]
    });
    socket
        .send(Message::Text(subscribe.to_string().into()))
        .map_err(|e| e.to_string())?;

    // Subscription is live and the index is current, so reads can serve from it now.
    // Health reflects subscription connectivity, NOT reconcile success.
    index.set_healthy(true);
    println!("membership index health: true (subscription live)");

    // Reconcile cadence is driven by the PERSISTED last-reconcile time, so frequent
    // reconnects (upstream idle-cycling) don't keep resetting it and starving the
    // backstop. `next_attempt_at` only rate-limits retries after a failure.
    let mut next_attempt_at = 0_i64;

    loop {
        match socket.read() {
            Ok(Message::Text(text)) => handle_notification(index, &text),
            Ok(Message::Ping(payload)) => {
                socket
                    .send(Message::Pong(payload))
                    .map_err(|e| e.to_string())?;
            }
            Ok(Message::Close(_)) => return Err("upstream closed".into()),
            Ok(_) => {}
            Err(tungstenite::Error::Io(e))
                if e.kind() == ErrorKind::WouldBlock || e.kind() == ErrorKind::TimedOut =>
            {
                // Idle: no message within the read timeout. Send a keepalive ping so
                // the upstream doesn't drop the subscription as idle (a quiet program
                // can go minutes without a notification), then run the reconcile check.
                if let Err(error) = socket.send(Message::Ping(Vec::<u8>::new().into())) {
                    return Err(format!("keepalive ping failed: {error}"));
                }
            }
            Err(error) => return Err(error.to_string()),
        }

        let now = now_unix();
        let reconcile_due =
            now.saturating_sub(index.last_reconcile_at()) >= RECONCILE_INTERVAL.as_secs() as i64;
        if reconcile_due && now >= next_attempt_at {
            // Background correctness backstop for deltas missed during a disconnect.
            // Failure keeps health (the live subscription still keeps the index
            // current) and backs off the retry; success updates the persisted stamp.
            match reconcile(index, client, now) {
                Ok(count) => println!("membership index reconcile ok: {count} multisigs upserted"),
                Err(error) => {
                    next_attempt_at = now + RECONCILE_RETRY_BACKOFF.as_secs() as i64;
                    eprintln!("membership index reconcile failed (retrying soon): {error}");
                }
            }
        }
    }
}

/// Parse a `programNotification` and upsert the changed account.
fn handle_notification(index: &MembershipIndex, text: &str) {
    let Ok(value) = serde_json::from_str::<Value>(text) else {
        return;
    };
    if value.get("method").and_then(Value::as_str) != Some("programNotification") {
        return;
    }
    let result = &value["params"]["result"];
    let slot = result["context"]["slot"].as_u64().unwrap_or(0);
    let Some(pubkey_str) = result["value"]["pubkey"].as_str() else {
        return;
    };
    let Ok(address) = pubkey_str.parse::<Pubkey>() else {
        return;
    };
    let Some(data_b64) = result["value"]["account"]["data"][0].as_str() else {
        return;
    };
    let Ok(bytes) = BASE64_STANDARD.decode(data_b64) else {
        return;
    };
    apply_account_bytes(index, &address, &bytes, slot);
}

/// Best-effort read timeout on the underlying TCP stream so the read loop wakes
/// periodically to run the reconcile timer even when no notifications arrive.
fn set_read_timeout(
    socket: &tungstenite::WebSocket<tungstenite::stream::MaybeTlsStream<std::net::TcpStream>>,
    timeout: Duration,
) {
    match socket.get_ref() {
        tungstenite::stream::MaybeTlsStream::Plain(stream) => {
            let _ = stream.set_read_timeout(Some(timeout));
        }
        tungstenite::stream::MaybeTlsStream::NativeTls(stream) => {
            let _ = stream.get_ref().set_read_timeout(Some(timeout));
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::membership_index::MembershipIndex;
    use solana_sdk::pubkey::Pubkey;
    use squads_multisig::anchor_lang::{AnchorSerialize, Discriminator};
    use squads_multisig::state::{Member, Multisig, Permission, Permissions};

    fn serialized_multisig(members: Vec<Member>, threshold: u16) -> Vec<u8> {
        let ms = Multisig {
            create_key: Pubkey::new_unique(),
            config_authority: Pubkey::default(),
            threshold,
            time_lock: 0,
            transaction_index: 3,
            stale_transaction_index: 0,
            rent_collector: None,
            bump: 255,
            members,
        };
        let mut bytes = Multisig::DISCRIMINATOR.to_vec();
        ms.serialize(&mut bytes).unwrap();
        bytes
    }

    #[test]
    fn apply_account_bytes_upserts_a_multisig() {
        let index = MembershipIndex::open(":memory:").unwrap();
        let alice = Pubkey::new_unique();
        let addr = Pubkey::new_unique();
        let bytes = serialized_multisig(
            vec![Member {
                key: alice,
                permissions: Permissions::from_vec(&[Permission::Vote]),
            }],
            1,
        );

        assert!(apply_account_bytes(&index, &addr, &bytes, 42));
        let hits = index.squads_for_member(&alice).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].address, addr.to_string());
    }

    #[test]
    fn apply_account_bytes_ignores_non_multisig_data() {
        let index = MembershipIndex::open(":memory:").unwrap();
        let addr = Pubkey::new_unique();
        assert!(!apply_account_bytes(&index, &addr, b"not a multisig", 1));
    }

    #[test]
    fn handle_notification_upserts_from_program_notification() {
        let index = MembershipIndex::open(":memory:").unwrap();
        let alice = Pubkey::new_unique();
        let addr = Pubkey::new_unique();
        let bytes = serialized_multisig(
            vec![Member {
                key: alice,
                permissions: Permissions::from_vec(&[Permission::Vote]),
            }],
            1,
        );
        let data_b64 = BASE64_STANDARD.encode(&bytes);
        let notification = serde_json::json!({
            "jsonrpc": "2.0",
            "method": "programNotification",
            "params": {
                "result": {
                    "context": { "slot": 123 },
                    "value": {
                        "pubkey": addr.to_string(),
                        "account": {
                            "data": [data_b64, "base64"],
                            "owner": "SQDS4ep65T869zMMBKyuUq6aD6EgTu8psMjkvj52pCf",
                            "lamports": 0u64,
                            "executable": false,
                            "rentEpoch": 0u64
                        }
                    }
                },
                "subscription": 1
            }
        })
        .to_string();

        handle_notification(&index, &notification);

        let hits = index.squads_for_member(&alice).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].address, addr.to_string());
    }

    #[test]
    fn handle_notification_ignores_subscribe_confirmation() {
        let index = MembershipIndex::open(":memory:").unwrap();
        // A subscribe-confirmation reply has no "method" field; it must be ignored.
        handle_notification(&index, r#"{"jsonrpc":"2.0","result":42,"id":1}"#);
        assert!(
            index
                .squads_for_member(&Pubkey::new_unique())
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn reconcile_should_advance_except_on_empty_full_build() {
        // Empty first (full) build: do NOT advance, so a lagging upstream can't make an
        // empty index authoritative — retry a full scan next cycle.
        assert!(!reconcile_should_advance(None, 0));
        // Populated first build: advance.
        assert!(reconcile_should_advance(None, 5));
        // Empty incremental scan (nothing changed since last slot): advance.
        assert!(reconcile_should_advance(Some(100), 0));
        // Populated incremental scan: advance.
        assert!(reconcile_should_advance(Some(100), 3));
    }
}
