import Core
import CosignCore
import Foundation

public enum ConfigChangeError: Error, Sendable {
    case notAutonomous
    case signerNotMember(String)
    case missingInitiatePermission
    case invalidMemberAddress(String)
    case contradictoryEdit(String)
    case noChanges
    case thresholdOutOfRange(String)
}

extension ConfigChangeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAutonomous:
            "Config changes require an autonomous Squad."
        case let .signerNotMember(address):
            "The selected signer (\(address)) is not a member of this Squad."
        case .missingInitiatePermission:
            "The selected signer does not have permission to create proposals for this Squad."
        case let .invalidMemberAddress(address):
            "'\(address)' is not a valid Solana address."
        case let .contradictoryEdit(reason):
            "Contradictory change: \(reason)."
        case .noChanges:
            "No changes were specified."
        case let .thresholdOutOfRange(reason):
            "Invalid threshold: \(reason)."
        }
    }
}

public extension SquadsService {
    /// Validates a config-change request against the current squad state.
    /// Mirrors the Rust projected-invariant logic: checks autonomous flag,
    /// signer membership + initiate permission, address validity, no
    /// contradictions, and threshold bounds against the projected member set.
    static func validateConfigChange(
        detail: SquadDetail,
        memberPubkey: String,
        addedMembers: [String],
        removedMembers: [String],
        newThreshold: UInt16
    ) throws {
        guard detail.isAutonomous else {
            throw ConfigChangeError.notAutonomous
        }
        guard let signer = detail.members.first(where: { $0.pubkey == memberPubkey }) else {
            throw ConfigChangeError.signerNotMember(memberPubkey)
        }
        guard signer.canInitiate else {
            throw ConfigChangeError.missingInitiatePermission
        }
        let currentPubkeys = Set(detail.members.map(\.pubkey))
        try validateConfigEdits(
            addedMembers: addedMembers,
            removedMembers: removedMembers,
            currentPubkeys: currentPubkeys,
            newThreshold: newThreshold,
            currentThreshold: detail.threshold
        )
        // Projected member set: (existing − removed) + added.
        // Added members are treated as full-permission (canVote, canInitiate, canExecute).
        let addedSet = Set(addedMembers)
        let removedSet = Set(removedMembers)
        let projectedExisting = detail.members.filter { !removedSet.contains($0.pubkey) }
        try validateProjectedInvariant(
            newThreshold: newThreshold,
            projectedVoterCount: projectedExisting.filter(\.canVote).count + addedSet.count,
            projectedProposerCount: projectedExisting.filter(\.canInitiate).count + addedSet.count,
            projectedExecutorCount: projectedExisting.filter(\.canExecute).count + addedSet.count
        )
    }

    private static func validateConfigEdits(
        addedMembers: [String],
        removedMembers: [String],
        currentPubkeys: Set<String>,
        newThreshold: UInt16,
        currentThreshold: UInt16
    ) throws {
        for address in addedMembers where !CosignCore.isValidSolanaPubkey(address) {
            throw ConfigChangeError.invalidMemberAddress(address)
        }
        for address in removedMembers where !CosignCore.isValidSolanaPubkey(address) {
            throw ConfigChangeError.invalidMemberAddress(address)
        }
        // Check intersection before individual add/remove checks so that
        // "add+remove same key" is reported as a contradiction rather than
        // collapsing into the remove-non-member branch.
        let addedSet = Set(addedMembers)
        let removedSet = Set(removedMembers)
        if let conflict = addedSet.intersection(removedSet).first {
            throw ConfigChangeError.contradictoryEdit("\(conflict) appears in both added and removed")
        }
        for address in addedMembers where currentPubkeys.contains(address) {
            throw ConfigChangeError.contradictoryEdit("\(address) is already a member")
        }
        for address in removedMembers where !currentPubkeys.contains(address) {
            throw ConfigChangeError.contradictoryEdit("\(address) is not a member")
        }
        guard !(addedMembers.isEmpty && removedMembers.isEmpty && newThreshold == currentThreshold) else {
            throw ConfigChangeError.noChanges
        }
    }

    private static func validateProjectedInvariant(
        newThreshold: UInt16,
        projectedVoterCount: Int,
        projectedProposerCount: Int,
        projectedExecutorCount: Int
    ) throws {
        guard newThreshold >= 1 else {
            throw ConfigChangeError.thresholdOutOfRange("threshold must be at least 1")
        }
        guard newThreshold <= projectedVoterCount else {
            throw ConfigChangeError.thresholdOutOfRange(
                "threshold \(newThreshold) exceeds projected voter count \(projectedVoterCount)"
            )
        }
        guard projectedProposerCount >= 1 else {
            throw ConfigChangeError.thresholdOutOfRange("no projected member has initiate permission")
        }
        guard projectedExecutorCount >= 1 else {
            throw ConfigChangeError.thresholdOutOfRange("no projected member has execute permission")
        }
    }

    func submitConfigChangeProposal(
        addedMembers: [String],
        removedMembers: [String],
        newThreshold: UInt16,
        in squadAddress: String,
        signer: any Signer
    ) async throws -> ProposalCreationSubmission {
        let memberPubkey = CosignCore.base58(signer.pubkey)
        let detail = try await detail(of: squadAddress)
        try Self.validateConfigChange(
            detail: detail,
            memberPubkey: memberPubkey,
            addedMembers: addedMembers,
            removedMembers: removedMembers,
            newThreshold: newThreshold
        )

        var request = ConfigChangeProposalRequest()
        request.rpcURL = rpcURL
        request.multisigAddress = squadAddress
        request.memberPubkey = memberPubkey
        request.addedMembers = addedMembers
        request.removedMembers = removedMembers
        request.newThreshold = newThreshold
        let prepared = try CosignCore.buildSquadsConfigChangeProposal(request)

        let signatureBytes = try await signer.sign(message: prepared.messageBytes)
        try simulateProposalCreation(prepared, signatureBytes: signatureBytes)
        return try await submitPreparedProposalCreation(
            prepared,
            signatureBytes: signatureBytes,
            squadAddress: squadAddress
        )
    }
}
