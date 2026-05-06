import CosignCore
import Foundation
import Indexer

extension SquadsService {
    func readableSimulationError(_ message: String) -> String {
        if message == "AccountNotFound" {
            return "The selected signer account was not found on this RPC endpoint. Fund it with SOL and try again."
        }
        return message
    }

    func waitForConfirmation(signature: String) async throws {
        var delay: UInt64 = 1_000_000_000
        for _ in 0 ..< 10 {
            let status = try await signatureStatus(signature: signature)
            if let error = status.error {
                throw ProposalActionError.transactionFailed(error)
            }
            if status.status == "confirmed" || status.status == "finalized" {
                return
            }
            try await Task.sleep(nanoseconds: delay)
            delay = min(delay * 2, 8_000_000_000)
        }

        throw ProposalActionError.confirmationTimedOut(signature)
    }

    private func signatureStatus(signature: String) async throws -> RelayTransactionStatus {
        if let response = try? await relay.transactionStatus(for: TransactionStatusRequest(signature: signature)) {
            return response.status
        }

        let status = try CosignCore.getSquadsSignatureStatus(rpcURL: rpcURL, signature: signature)
        return RelayTransactionStatus(
            slot: status.slot,
            status: status.status,
            error: status.err
        )
    }
}
