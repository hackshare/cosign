import Foundation
import Indexer

public extension SquadsService {
    /// The owning program of `address`, or nil if the account does not exist.
    func accountOwner(address: String) async throws -> String? {
        if let demoFixture {
            return demoFixture.accountOwner(address: address)
        }
        return try await indexer.getAccountOwner(pubkey: address)
    }

    /// Classify a transfer recipient by its owning program. A fresh/non-existent
    /// address and System-Program-owned accounts are wallets; Squads-owned
    /// accounts (vaults, configs) are recoverable; anything else is a risky
    /// program/token account where a SOL transfer can be unrecoverable.
    func classifyRecipient(address: String) async throws -> RecipientClassification {
        guard let owner = try await accountOwner(address: address) else {
            return .wallet
        }
        if owner == SolanaConstants.systemProgram {
            return .wallet
        }
        if SolanaConstants.squadsPrograms.contains(owner) {
            return .squadsControlled
        }
        return .programOwned
    }

    /// On-chain confirmation facts (slot, block time, status) for a broadcast
    /// signature — used by the receipt to report what actually settled. Returns
    /// nil if the transaction can't be inspected yet.
    func executedTransactionStatus(signature: String) async -> ExecutedTransactionInspectionStatus? {
        if demoFixture != nil {
            return ExecutedTransactionInspectionStatus(
                status: "finalized",
                slot: 282_140_917,
                blockTime: 1_779_230_400,
                error: nil
            )
        }
        let request = ExecutedTransactionInspectionRequest(signature: signature)
        return try? await relay.executedTransactionInspectionReport(for: request).status
    }

    /// Network fee (lamports) paid by a broadcast signature, or nil if not yet
    /// readable. Complements `executedTransactionStatus` (the inspection has no
    /// fee field, so this is a separate `getTransaction` lookup).
    func executedTransactionFee(signature: String) async -> UInt64? {
        if demoFixture != nil {
            return 5000
        }
        return try? await indexer.getTransactionFee(signature: signature)
    }

    /// Per-mint USD prices from the relay (demo relay serves illustrative prices;
    /// real relay fetches live prices from Jupiter). Missing mints are absent —
    /// callers render an em-dash, never a fabricated value.
    func prices(for mints: [String]) async -> [String: Double] {
        guard !mints.isEmpty else {
            return [:]
        }
        let response = try? await relay.prices(for: mints)
        return response?.prices ?? [:]
    }
}
