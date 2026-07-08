import Foundation
import Indexer

public struct ProposalRange: Equatable, Hashable, Sendable {
    public let fromIndex: UInt64
    public let toIndex: UInt64

    public init(fromIndex: UInt64, toIndex: UInt64) {
        self.fromIndex = fromIndex
        self.toIndex = toIndex
    }

    public static func recent(through latestIndex: UInt64, limit: UInt64 = 50) -> ProposalRange? {
        guard latestIndex > 0, limit > 0 else {
            return nil
        }

        let fromIndex = latestIndex > limit ? latestIndex - limit + 1 : 1
        return ProposalRange(fromIndex: fromIndex, toIndex: latestIndex)
    }
}

public struct SquadProposalSummary: Equatable, Sendable, Identifiable {
    public var id: UInt64 {
        transactionIndex
    }

    public let transactionIndex: UInt64
    public let status: String
    public let votesYes: UInt32
    public let votesNo: UInt32
    public let votesCancelled: UInt32
    public let threshold: UInt16
    public let kind: String?
    public let action: RelayInspectionAction?

    public init(
        transactionIndex: UInt64,
        status: String,
        votesYes: UInt32,
        votesNo: UInt32,
        votesCancelled: UInt32,
        threshold: UInt16,
        kind: String? = nil,
        action: RelayInspectionAction? = nil
    ) {
        self.transactionIndex = transactionIndex
        self.status = status
        self.votesYes = votesYes
        self.votesNo = votesNo
        self.votesCancelled = votesCancelled
        self.threshold = threshold
        self.kind = kind
        self.action = action
    }
}

public extension SquadProposalSummary {
    /// A proposal still awaiting quorum or execution (counts toward "pending").
    var isOpen: Bool {
        switch status.lowercased() {
        case "active", "approved":
            true
        default:
            false
        }
    }
}

public struct SquadProposalDetail: Equatable, Sendable, Identifiable {
    public var id: UInt64 {
        transactionIndex
    }

    public let transactionIndex: UInt64
    public let status: String
    public let votesYes: UInt32
    public let votesNo: UInt32
    public let votesCancelled: UInt32
    public let threshold: UInt16
    public let kind: String
    public let votersYes: [String]
    public let votersNo: [String]
    public let votersCancelled: [String]
    public let instructions: [SquadDecodedInstruction]
    public let accountsReferenced: [String]
    public let transactionAddress: String?
    public let proposer: String?
    public let createdAtUnix: Int64?

    public init(
        transactionIndex: UInt64,
        status: String,
        votesYes: UInt32,
        votesNo: UInt32,
        votesCancelled: UInt32,
        threshold: UInt16,
        kind: String,
        votersYes: [String],
        votersNo: [String],
        votersCancelled: [String],
        instructions: [SquadDecodedInstruction],
        accountsReferenced: [String],
        transactionAddress: String?,
        proposer: String? = nil,
        createdAtUnix: Int64? = nil
    ) {
        self.transactionIndex = transactionIndex
        self.status = status
        self.votesYes = votesYes
        self.votesNo = votesNo
        self.votesCancelled = votesCancelled
        self.threshold = threshold
        self.kind = kind
        self.votersYes = votersYes
        self.votersNo = votersNo
        self.votersCancelled = votersCancelled
        self.instructions = instructions
        self.accountsReferenced = accountsReferenced
        self.transactionAddress = transactionAddress
        self.proposer = proposer
        self.createdAtUnix = createdAtUnix
    }
}

public struct SquadConfigAction: Equatable, Sendable {
    public let memberKey: String?
    public let canInitiate: Bool
    public let canVote: Bool
    public let canExecute: Bool
    public let newThreshold: UInt16?
    public let newTimeLockSeconds: UInt32?
    public let newRentCollector: String?
    public let clearsRentCollector: Bool

    public init(
        memberKey: String? = nil,
        canInitiate: Bool = false,
        canVote: Bool = false,
        canExecute: Bool = false,
        newThreshold: UInt16? = nil,
        newTimeLockSeconds: UInt32? = nil,
        newRentCollector: String? = nil,
        clearsRentCollector: Bool = false
    ) {
        self.memberKey = memberKey
        self.canInitiate = canInitiate
        self.canVote = canVote
        self.canExecute = canExecute
        self.newThreshold = newThreshold
        self.newTimeLockSeconds = newTimeLockSeconds
        self.newRentCollector = newRentCollector
        self.clearsRentCollector = clearsRentCollector
    }
}

public struct SquadDecodedInstruction: Equatable, Sendable {
    public let program: String
    public let kind: String
    public let summary: String
    public let accounts: [String]
    public let rawDataHex: String
    public let configAction: SquadConfigAction?

    public init(
        program: String,
        kind: String,
        summary: String,
        accounts: [String] = [],
        rawDataHex: String,
        configAction: SquadConfigAction? = nil
    ) {
        self.program = program
        self.kind = kind
        self.summary = summary
        self.accounts = accounts
        self.rawDataHex = rawDataHex
        self.configAction = configAction
    }
}

public struct SquadActivityItem: Equatable, Sendable, Identifiable {
    public var id: String {
        signature
    }

    public let signature: String
    public let slot: UInt64
    public let timestampUnix: Int64
    public let kind: String
    public let error: String?
    public let action: RelayInspectionAction?

    public init(
        signature: String,
        slot: UInt64,
        timestampUnix: Int64,
        kind: String,
        error: String?,
        action: RelayInspectionAction? = nil
    ) {
        self.signature = signature
        self.slot = slot
        self.timestampUnix = timestampUnix
        self.kind = kind
        self.error = error
        self.action = action
    }
}
