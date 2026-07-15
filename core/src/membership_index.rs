//! Relay-side membership index: a `member -> squads` reverse lookup backed by
//! embedded SQLite, so `/members/<member>/squads` reads do not rescan the whole
//! Squads program on every request. The index is a fast path only; callers fall
//! back to a live scan whenever it is not fresh.

use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};

use rusqlite::Connection;
use solana_sdk::pubkey::Pubkey;
use squads_multisig::state::Multisig;

use crate::types::{self, MultisigSummary};

/// The index is judged stale if the last successful reconcile is older than this,
/// even while the subscription reports healthy. Bounds how long a missed delta can
/// go uncorrected before reads fall back to a live scan.
pub const MAX_RECONCILE_AGE_SECS: i64 = 3 * 60 * 60;

const META_BUILD_COMPLETE: &str = "build_complete";
const META_LAST_RECONCILE_AT: &str = "last_reconcile_at";
const META_LAST_SCAN_SLOT: &str = "last_scan_slot";

#[derive(Debug, thiserror::Error)]
pub enum IndexError {
    #[error("sqlite error: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("upstream scan failed: {0}")]
    Scan(String),
}

pub struct MembershipIndex {
    conn: Mutex<Connection>,
    healthy: AtomicBool,
}

impl MembershipIndex {
    pub fn open(path: &str) -> Result<MembershipIndex, IndexError> {
        let conn = Connection::open(path)?;
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "synchronous", "NORMAL")?;
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS multisig (
                 address                 TEXT PRIMARY KEY,
                 threshold               INTEGER NOT NULL,
                 member_count            INTEGER NOT NULL,
                 transaction_index       INTEGER NOT NULL,
                 stale_transaction_index INTEGER NOT NULL,
                 updated_slot            INTEGER NOT NULL
             );
             CREATE TABLE IF NOT EXISTS membership (
                 member           TEXT NOT NULL,
                 multisig_address TEXT NOT NULL,
                 PRIMARY KEY (member, multisig_address)
             );
             CREATE INDEX IF NOT EXISTS membership_by_member ON membership (member);
             CREATE INDEX IF NOT EXISTS membership_by_multisig ON membership (multisig_address);
             CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);",
        )?;
        Ok(MembershipIndex {
            conn: Mutex::new(conn),
            healthy: AtomicBool::new(false),
        })
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Connection> {
        self.conn.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub fn upsert_multisig(
        &self,
        address: &Pubkey,
        ms: &Multisig,
        slot: u64,
    ) -> Result<(), IndexError> {
        let summary = types::multisig_summary(address, ms);
        let address = address.to_string();
        let members: Vec<String> = ms.members.iter().map(|m| m.key.to_string()).collect();

        let mut guard = self.lock();
        let tx = guard.transaction()?;
        tx.execute(
            "INSERT INTO multisig
               (address, threshold, member_count, transaction_index, stale_transaction_index, updated_slot)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)
             ON CONFLICT(address) DO UPDATE SET
               threshold = excluded.threshold,
               member_count = excluded.member_count,
               transaction_index = excluded.transaction_index,
               stale_transaction_index = excluded.stale_transaction_index,
               updated_slot = excluded.updated_slot",
            rusqlite::params![
                address,
                summary.threshold,
                summary.member_count,
                summary.transaction_index,
                summary.stale_transaction_index,
                slot,
            ],
        )?;
        tx.execute(
            "DELETE FROM membership WHERE multisig_address = ?1",
            [&address],
        )?;
        {
            let mut stmt = tx.prepare(
                "INSERT OR IGNORE INTO membership (member, multisig_address) VALUES (?1, ?2)",
            )?;
            for member in &members {
                stmt.execute(rusqlite::params![member, address])?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    pub fn squads_for_member(&self, member: &Pubkey) -> Result<Vec<MultisigSummary>, IndexError> {
        let guard = self.lock();
        let mut stmt = guard.prepare(
            "SELECT m.address, m.threshold, m.member_count, m.transaction_index, m.stale_transaction_index
               FROM multisig m
               JOIN membership mem ON mem.multisig_address = m.address
              WHERE mem.member = ?1",
        )?;
        let rows = stmt.query_map([member.to_string()], |row| {
            Ok(MultisigSummary {
                address: row.get(0)?,
                threshold: row.get(1)?,
                member_count: row.get(2)?,
                transaction_index: row.get::<_, i64>(3)? as u64,
                stale_transaction_index: row.get::<_, i64>(4)? as u64,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    fn get_meta(&self, key: &str) -> Option<String> {
        let guard = self.lock();
        guard
            .query_row("SELECT value FROM meta WHERE key = ?1", [key], |row| {
                row.get::<_, String>(0)
            })
            .ok()
    }

    fn set_meta(&self, key: &str, value: &str) -> Result<(), IndexError> {
        let guard = self.lock();
        guard.execute(
            "INSERT INTO meta (key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            rusqlite::params![key, value],
        )?;
        Ok(())
    }

    pub fn build_complete(&self) -> bool {
        self.get_meta(META_BUILD_COMPLETE).as_deref() == Some("1")
    }

    pub fn mark_build_complete(&self) -> Result<(), IndexError> {
        self.set_meta(META_BUILD_COMPLETE, "1")
    }

    pub fn touch_reconcile(&self, now_unix: i64) -> Result<(), IndexError> {
        self.set_meta(META_LAST_RECONCILE_AT, &now_unix.to_string())
    }

    pub fn last_reconcile_at(&self) -> i64 {
        self.get_meta(META_LAST_RECONCILE_AT)
            .and_then(|v| v.parse().ok())
            .unwrap_or(0)
    }

    pub fn last_scan_slot(&self) -> u64 {
        self.get_meta(META_LAST_SCAN_SLOT)
            .and_then(|v| v.parse().ok())
            .unwrap_or(0)
    }

    pub fn set_last_scan_slot(&self, slot: u64) -> Result<(), IndexError> {
        self.set_meta(META_LAST_SCAN_SLOT, &slot.to_string())
    }

    pub fn set_healthy(&self, healthy: bool) {
        self.healthy.store(healthy, Ordering::SeqCst);
    }

    pub fn is_fresh(&self, now_unix: i64) -> bool {
        self.healthy.load(Ordering::SeqCst)
            && self.build_complete()
            && now_unix.saturating_sub(self.last_reconcile_at()) < MAX_RECONCILE_AGE_SECS
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use solana_sdk::pubkey::Pubkey;
    use squads_multisig::state::{Member, Multisig, Permission, Permissions};

    fn member(key: Pubkey) -> Member {
        Member {
            key,
            permissions: Permissions::from_vec(&[Permission::Vote]),
        }
    }

    fn multisig_with(members: Vec<Member>, threshold: u16, tx_index: u64) -> Multisig {
        Multisig {
            create_key: Pubkey::new_unique(),
            config_authority: Pubkey::default(),
            threshold,
            time_lock: 0,
            transaction_index: tx_index,
            stale_transaction_index: 0,
            rent_collector: None,
            bump: 255,
            members,
        }
    }

    #[test]
    fn upsert_then_query_returns_summary_for_each_member() {
        let index = MembershipIndex::open(":memory:").unwrap();
        let alice = Pubkey::new_unique();
        let bob = Pubkey::new_unique();
        let ms_addr = Pubkey::new_unique();
        let ms = multisig_with(vec![member(alice), member(bob)], 2, 7);

        index.upsert_multisig(&ms_addr, &ms, 100).unwrap();

        let for_alice = index.squads_for_member(&alice).unwrap();
        assert_eq!(for_alice.len(), 1);
        assert_eq!(for_alice[0].address, ms_addr.to_string());
        assert_eq!(for_alice[0].threshold, 2);
        assert_eq!(for_alice[0].member_count, 2);
        assert_eq!(for_alice[0].transaction_index, 7);

        assert_eq!(index.squads_for_member(&bob).unwrap().len(), 1);
        assert!(
            index
                .squads_for_member(&Pubkey::new_unique())
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn upsert_replaces_membership_when_a_member_is_removed() {
        let index = MembershipIndex::open(":memory:").unwrap();
        let alice = Pubkey::new_unique();
        let bob = Pubkey::new_unique();
        let ms_addr = Pubkey::new_unique();

        index
            .upsert_multisig(
                &ms_addr,
                &multisig_with(vec![member(alice), member(bob)], 2, 1),
                1,
            )
            .unwrap();
        index
            .upsert_multisig(&ms_addr, &multisig_with(vec![member(alice)], 1, 2), 2)
            .unwrap();

        assert_eq!(
            index.squads_for_member(&alice).unwrap()[0].transaction_index,
            2
        );
        assert!(index.squads_for_member(&bob).unwrap().is_empty());
    }

    #[test]
    fn freshness_requires_build_complete_healthy_and_recent_reconcile() {
        let index = MembershipIndex::open(":memory:").unwrap();
        let now = 1_000_000_i64;

        assert!(!index.is_fresh(now), "not built, not healthy");
        index.mark_build_complete().unwrap();
        index.touch_reconcile(now).unwrap();
        assert!(!index.is_fresh(now), "still not healthy");
        index.set_healthy(true);
        assert!(index.is_fresh(now), "built + healthy + just reconciled");

        let stale = now + MAX_RECONCILE_AGE_SECS + 1;
        assert!(!index.is_fresh(stale), "reconcile too old");
    }

    #[test]
    fn last_scan_slot_round_trips() {
        let index = MembershipIndex::open(":memory:").unwrap();
        assert_eq!(index.last_scan_slot(), 0);
        index.set_last_scan_slot(987_654).unwrap();
        assert_eq!(index.last_scan_slot(), 987_654);
    }

    // The per-multisig membership DELETE in upsert_multisig runs on every upsert
    // (build, reconcile, and each subscription notification). Without an index on
    // multisig_address it full-scans the membership table, which is O(n^2) over a
    // large build. Assert the query plan uses the index instead of scanning.
    #[test]
    fn delete_by_multisig_uses_an_index() {
        let index = MembershipIndex::open(":memory:").unwrap();
        let guard = index.lock();
        let mut stmt = guard
            .prepare("EXPLAIN QUERY PLAN DELETE FROM membership WHERE multisig_address = ?1")
            .unwrap();
        let plan = stmt
            .query_map(["x"], |row| row.get::<_, String>(3))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap()
            .join(" ");
        assert!(
            plan.contains("membership_by_multisig"),
            "DELETE by multisig_address must use the index, got plan: {plan}"
        );
        assert!(
            !plan.to_uppercase().contains("SCAN MEMBERSHIP"),
            "DELETE should not full-scan membership, got plan: {plan}"
        );
    }
}
