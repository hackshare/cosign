import Core
import CosignCore
import Foundation

public enum ConfigChangeError: Error, Sendable {
    case notAutonomous
    case invalidMemberAddress(String)
    case contradictoryEdit(String)
    case memberMissingPermission(String)
    case noChanges
    case thresholdOutOfRange(String)
    case timeLockOutOfRange
}

extension ConfigChangeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAutonomous:
            "Config changes require an autonomous Squad."
        case let .invalidMemberAddress(address):
            "'\(address)' is not a valid Solana address."
        case let .contradictoryEdit(reason):
            "Contradictory change: \(reason)."
        case .memberMissingPermission:
            "Every member needs at least one permission."
        case .noChanges:
            "No changes were specified."
        case let .thresholdOutOfRange(reason):
            "Invalid threshold: \(reason)."
        case .timeLockOutOfRange:
            "Time lock must be 90 days or less."
        }
    }
}

public extension SquadsService {
    static let maxTimeLockSeconds: UInt32 = 7_776_000

    static func validateConfigChange(
        detail: SquadDetail,
        desiredMembers: [SquadMember],
        newThreshold: UInt16,
        newTimeLockSeconds: UInt32,
        newRentCollector: String?
    ) throws {
        guard detail.isAutonomous else { throw ConfigChangeError.notAutonomous }
        guard newTimeLockSeconds <= maxTimeLockSeconds else { throw ConfigChangeError.timeLockOutOfRange }

        try validateMemberAddresses(desiredMembers, rentCollector: newRentCollector)
        if Set(desiredMembers.map(\.pubkey)).count != desiredMembers.count {
            throw ConfigChangeError.contradictoryEdit("a member appears more than once")
        }
        for member in desiredMembers where !(member.canInitiate || member.canVote || member.canExecute) {
            throw ConfigChangeError.memberMissingPermission(member.pubkey)
        }

        let voters = desiredMembers.count(where: \.canVote)
        let proposers = desiredMembers.count(where: \.canInitiate)
        let executors = desiredMembers.count(where: \.canExecute)
        guard newThreshold >= 1 else {
            throw ConfigChangeError.thresholdOutOfRange("threshold must be at least 1")
        }
        guard Int(newThreshold) <= voters else {
            throw ConfigChangeError.thresholdOutOfRange(
                "threshold \(newThreshold) exceeds voter count \(voters)"
            )
        }
        guard proposers >= 1 else {
            throw ConfigChangeError.thresholdOutOfRange("no member has propose permission")
        }
        guard executors >= 1 else {
            throw ConfigChangeError.thresholdOutOfRange("no member has execute permission")
        }

        let sameMembers = Set(desiredMembers.map(memberKey)) == Set(detail.members.map(memberKey))
        let isNoOp = sameMembers
            && newThreshold == detail.threshold
            && newTimeLockSeconds == detail.timeLockSeconds
            && newRentCollector == detail.rentCollector
        if isNoOp { throw ConfigChangeError.noChanges }
    }

    // swiftlint:disable:next function_parameter_count
    func submitConfigChangeProposal(
        desiredMembers: [SquadMember],
        newThreshold: UInt16,
        newTimeLockSeconds: UInt32,
        newRentCollector: String?,
        expectedMembers: [SquadMember],
        expectedThreshold: UInt16,
        expectedTimeLockSeconds: UInt32,
        expectedRentCollector: String?,
        in squadAddress: String,
        signer: any Signer
    ) async throws -> ProposalCreationSubmission {
        let memberPubkey = CosignCore.base58(signer.pubkey)
        let detail = try await detail(of: squadAddress)
        try Self.validateConfigChange(
            detail: detail,
            desiredMembers: desiredMembers,
            newThreshold: newThreshold,
            newTimeLockSeconds: newTimeLockSeconds,
            newRentCollector: newRentCollector
        )

        let toConfigMemberInput = { (mem: SquadMember) in
            ConfigMemberInput(
                pubkey: mem.pubkey, canInitiate: mem.canInitiate,
                canVote: mem.canVote, canExecute: mem.canExecute
            )
        }
        var request = ConfigChangeProposalRequest()
        request.rpcURL = rpcURL
        request.multisigAddress = squadAddress
        request.memberPubkey = memberPubkey
        request.desiredMembers = desiredMembers.map(toConfigMemberInput)
        request.newThreshold = newThreshold
        request.newTimeLockSeconds = newTimeLockSeconds
        request.newRentCollector = newRentCollector
        request.expectedMembers = expectedMembers.map(toConfigMemberInput)
        request.expectedThreshold = expectedThreshold
        request.expectedTimeLockSeconds = expectedTimeLockSeconds
        request.expectedRentCollector = expectedRentCollector
        let prepared = try CosignCore.buildSquadsConfigChangeProposal(request)

        let signatureBytes = try await signer.sign(message: prepared.messageBytes)
        try simulateProposalCreation(prepared, signatureBytes: signatureBytes)
        return try await submitPreparedProposalCreation(
            prepared,
            signatureBytes: signatureBytes,
            squadAddress: squadAddress
        )
    }

    private static func validateMemberAddresses(
        _ desiredMembers: [SquadMember],
        rentCollector: String?
    ) throws {
        for member in desiredMembers where !CosignCore.isValidSolanaPubkey(member.pubkey) {
            throw ConfigChangeError.invalidMemberAddress(member.pubkey)
        }
        if let collector = rentCollector, !CosignCore.isValidSolanaPubkey(collector) {
            throw ConfigChangeError.invalidMemberAddress(collector)
        }
    }

    private static func memberKey(_ member: SquadMember) -> String {
        "\(member.pubkey):\(member.canInitiate ? 1 : 0)\(member.canVote ? 1 : 0)\(member.canExecute ? 1 : 0)"
    }
}
