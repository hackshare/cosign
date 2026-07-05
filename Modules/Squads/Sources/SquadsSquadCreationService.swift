import Core
import CosignCore
import Foundation

public struct SquadCreationResult: Sendable {
    public let multisigAddress: String
    public let signature: String
}

public enum SquadCreationError: Error, Sendable {
    case invalidMemberAddress(String)
    case thresholdOutOfRange
    case transactionFailed(String)
    case confirmationTimedOut(String)
}

public extension SquadsService {
    /// Validates and normalizes member input. Returns the deduped extra-members
    /// list (creator excluded; the core always includes the creator automatically).
    static func validateSquadCreation(
        memberAddresses: [String],
        threshold: UInt16,
        creator: String
    ) throws -> [String] {
        for address in memberAddresses where !CosignCore.isValidSolanaPubkey(address) {
            throw SquadCreationError.invalidMemberAddress(address)
        }
        var extras: [String] = []
        for address in memberAddresses where address != creator && !extras.contains(address) {
            extras.append(address)
        }
        let memberCount = extras.count + 1 // creator always counts as a member
        guard threshold >= 1, Int(threshold) <= memberCount else {
            throw SquadCreationError.thresholdOutOfRange
        }
        return extras
    }

    func estimateSquadCost(
        memberAddresses: [String],
        threshold: UInt16,
        creatorPubkey: String
    ) async throws -> CreateMultisigCost {
        let extras = try Self.validateSquadCreation(
            memberAddresses: memberAddresses, threshold: threshold, creator: creatorPubkey
        )
        var request = CreateMultisigTransactionRequest()
        request.rpcURL = rpcURL
        request.creatorPubkey = creatorPubkey
        request.memberPubkeys = extras
        request.threshold = threshold
        return try CosignCore.estimateSquadsCreateMultisigCost(request)
    }

    func solBalance(of address: String) async throws -> UInt64 {
        try CosignCore.solBalance(rpcURL: rpcURL, address: address)
    }

    func requestAirdrop(address: String, airdropRPCURL: String) async throws -> String {
        try CosignCore.airdropDevnet(rpcURL: airdropRPCURL, address: address, lamports: 1_000_000_000)
    }

    func createSquad(
        memberAddresses: [String],
        threshold: UInt16,
        signer: any Signer
    ) async throws -> SquadCreationResult {
        let creatorPubkey = CosignCore.base58(signer.pubkey)
        let extras = try Self.validateSquadCreation(
            memberAddresses: memberAddresses, threshold: threshold, creator: creatorPubkey
        )

        var request = CreateMultisigTransactionRequest()
        request.rpcURL = rpcURL
        request.creatorPubkey = creatorPubkey
        request.memberPubkeys = extras
        request.threshold = threshold
        let prepared = try CosignCore.buildSquadsCreateMultisig(request)

        let creatorSignature = try await signer.sign(message: prepared.messageBytes)
        let submission = try CosignCore.sendSquadsMultisigCreate(
            rpcURL: rpcURL,
            messageBytes: prepared.messageBytes,
            creatorSignature: creatorSignature,
            createKey: prepared.createKey,
            createKeySignature: prepared.createKeySignature
        )

        do {
            try await waitForConfirmation(signature: submission.signature)
        } catch let ProposalActionError.confirmationTimedOut(signature) {
            throw SquadCreationError.confirmationTimedOut(signature)
        } catch let ProposalActionError.transactionFailed(message) {
            throw SquadCreationError.transactionFailed(message)
        }
        await clearReadCaches()
        _ = try? await refreshSquads(forMember: creatorPubkey)

        return SquadCreationResult(
            multisigAddress: prepared.multisigAddress,
            signature: submission.signature
        )
    }
}
