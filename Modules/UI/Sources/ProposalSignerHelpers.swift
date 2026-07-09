import Core
import CosignCore
import Foundation
import Persistence
import Signers

func makeProposalActionSigner(from signer: RegisteredSigner) -> ProposalActionSigner? {
    guard let account = signer.keychainItemRef else {
        return nil
    }

    return ProposalActionSigner(
        id: signer.id,
        label: signer.label,
        type: signer.type,
        pubkey: signer.pubkey,
        address: CosignCore.base58(signer.pubkey),
        storage: .hotWallet(keychainAccount: account),
        backedUp: signer.backedUp
    )
}

@MainActor
func withResolvedProposalSigner<T>(
    _ signer: ProposalActionSigner,
    deviceStatus: @escaping @MainActor (String?) -> Void,
    operation: (any Signer) async throws -> T
) async throws -> T {
    deviceStatus(nil)

    guard case let .hotWallet(keychainAccount) = signer.storage else {
        throw ProposalSignerResolutionError.notBackedUp
    }
    guard signer.backedUp else {
        throw ProposalSignerResolutionError.notBackedUp
    }
    return try await operation(HotWalletSigner(
        label: signer.label,
        pubkey: signer.pubkey,
        keychainAccount: keychainAccount
    ))
}

enum ProposalSignerResolutionError: LocalizedError {
    case notBackedUp

    var errorDescription: String? {
        switch self {
        case .notBackedUp:
            CosignCopy.ProposalSigning.notBackedUpError
        }
    }
}
