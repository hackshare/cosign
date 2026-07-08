public struct ProposalInspectionRequest: Equatable, Sendable {
    public let squadAddress: String
    public let transactionIndex: UInt64

    public init(squadAddress: String, transactionIndex: UInt64) {
        self.squadAddress = squadAddress
        self.transactionIndex = transactionIndex
    }
}

public struct ExecutedTransactionInspectionRequest: Equatable, Sendable {
    public let signature: String

    public init(signature: String) {
        self.signature = signature
    }
}

public struct TransactionStatusRequest: Equatable, Sendable {
    public let signature: String

    public init(signature: String) {
        self.signature = signature
    }
}

public struct MemberSquadsRequest: Equatable, Sendable {
    public let memberAddress: String

    public init(memberAddress: String) {
        self.memberAddress = memberAddress
    }
}

public struct MemberSquadsResponse: Decodable, Equatable, Sendable {
    public let kind: String?
    public let member: String
    public let cluster: String?
    public let squads: [RelaySquadSummary]
}

public struct SquadDetailRequest: Equatable, Sendable {
    public let squadAddress: String

    public init(squadAddress: String) {
        self.squadAddress = squadAddress
    }
}

public struct SquadDetailResponse: Decodable, Equatable, Sendable {
    public let kind: String?
    public let cluster: String?
    public let squad: RelaySquadDetail
}

public struct SquadProposalsRequest: Equatable, Sendable {
    public let squadAddress: String
    public let fromIndex: UInt64
    public let toIndex: UInt64

    public init(squadAddress: String, fromIndex: UInt64, toIndex: UInt64) {
        self.squadAddress = squadAddress
        self.fromIndex = fromIndex
        self.toIndex = toIndex
    }
}

public struct SquadProposalsResponse: Decodable, Equatable, Sendable {
    public let kind: String?
    public let squad: String
    public let cluster: String?
    public let range: RelayProposalRange
    public let proposals: [RelayProposalSummary]
}

public struct SquadProposalRequest: Equatable, Sendable {
    public let squadAddress: String
    public let transactionIndex: UInt64

    public init(squadAddress: String, transactionIndex: UInt64) {
        self.squadAddress = squadAddress
        self.transactionIndex = transactionIndex
    }
}

public struct SquadProposalResponse: Decodable, Equatable, Sendable {
    public let kind: String?
    public let squad: String
    public let cluster: String?
    public let proposal: ProposalInspectionProposal
}

public struct RelayPrices: Decodable, Equatable, Sendable {
    public let prices: [String: Double]

    public init(prices: [String: Double]) {
        self.prices = prices
    }
}

public struct AccountActivityRequest: Equatable, Sendable {
    public let address: String
    public let beforeSignature: String?
    public let limit: UInt32

    public init(address: String, beforeSignature: String? = nil, limit: UInt32 = 50) {
        self.address = address
        self.beforeSignature = beforeSignature
        self.limit = limit
    }
}

public struct AccountActivityResponse: Decodable, Equatable, Sendable {
    public let kind: String?
    public let address: String
    public let cluster: String?
    public let before: String?
    public let limit: UInt32
    public let activity: [RelayActivityItem]
}

public struct TransactionStatusResponse: Decodable, Equatable, Sendable {
    public let kind: String?
    public let signature: String
    public let cluster: String?
    public let status: RelayTransactionStatus
}

public struct RelaySquadSummary: Decodable, Equatable, Sendable {
    public let address: String
    public let displayName: String?
    public let threshold: UInt16
    public let memberCount: UInt32
    public let transactionIndex: UInt64
    public let staleTransactionIndex: UInt64

    public init(
        address: String,
        displayName: String? = nil,
        threshold: UInt16,
        memberCount: UInt32,
        transactionIndex: UInt64,
        staleTransactionIndex: UInt64
    ) {
        self.address = address
        self.displayName = displayName
        self.threshold = threshold
        self.memberCount = memberCount
        self.transactionIndex = transactionIndex
        self.staleTransactionIndex = staleTransactionIndex
    }
}

public struct RelaySquadDetail: Decodable, Equatable, Sendable {
    public let address: String
    public let displayName: String?
    public let threshold: UInt16
    public let timeLockSeconds: UInt32
    public let rentCollector: String?
    public let transactionIndex: UInt64
    public let staleTransactionIndex: UInt64
    public let isAutonomous: Bool
    public let members: [RelaySquadMember]
    public let vaults: [RelaySquadVaultRef]

    public init(
        address: String,
        displayName: String? = nil,
        threshold: UInt16,
        timeLockSeconds: UInt32,
        rentCollector: String? = nil,
        transactionIndex: UInt64,
        staleTransactionIndex: UInt64,
        isAutonomous: Bool = true,
        members: [RelaySquadMember],
        vaults: [RelaySquadVaultRef]
    ) {
        self.address = address
        self.displayName = displayName
        self.threshold = threshold
        self.timeLockSeconds = timeLockSeconds
        self.rentCollector = rentCollector
        self.transactionIndex = transactionIndex
        self.staleTransactionIndex = staleTransactionIndex
        self.isAutonomous = isAutonomous
        self.members = members
        self.vaults = vaults
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decode(String.self, forKey: .address)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        threshold = try container.decode(UInt16.self, forKey: .threshold)
        timeLockSeconds = try container.decode(UInt32.self, forKey: .timeLockSeconds)
        rentCollector = try container.decodeIfPresent(String.self, forKey: .rentCollector)
        transactionIndex = try container.decode(UInt64.self, forKey: .transactionIndex)
        staleTransactionIndex = try container.decode(UInt64.self, forKey: .staleTransactionIndex)
        isAutonomous = try container.decodeIfPresent(Bool.self, forKey: .isAutonomous) ?? true
        members = try container.decode([RelaySquadMember].self, forKey: .members)
        vaults = try container.decode([RelaySquadVaultRef].self, forKey: .vaults)
    }

    private enum CodingKeys: String, CodingKey {
        case address, displayName, threshold, timeLockSeconds, rentCollector,
             transactionIndex, staleTransactionIndex, isAutonomous, members, vaults
    }
}

public struct RelaySquadMember: Decodable, Equatable, Sendable {
    public let pubkey: String
    public let canInitiate: Bool
    public let canVote: Bool
    public let canExecute: Bool
}

public struct RelaySquadVaultRef: Decodable, Equatable, Sendable {
    public let index: UInt8
    public let address: String
}

public struct RelayProposalRange: Decodable, Equatable, Sendable {
    public let fromIndex: UInt64
    public let toIndex: UInt64

    enum CodingKeys: String, CodingKey {
        case fromIndex = "from"
        case toIndex = "to"
    }
}

public struct RelayProposalSummary: Decodable, Equatable, Sendable {
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

public struct RelayActivityItem: Decodable, Equatable, Sendable {
    public let signature: String
    public let slot: UInt64
    public let timestampUnix: Int64
    public let kind: String
    public let error: String?
    public let action: RelayInspectionAction?
}

public struct RelayTransactionStatus: Decodable, Equatable, Sendable {
    public let slot: UInt64?
    public let status: String
    public let error: String?

    public init(slot: UInt64?, status: String, error: String?) {
        self.slot = slot
        self.status = status
        self.error = error
    }
}

public struct ProposalInspectionReport: Decodable, Equatable, Sendable {
    public let kind: String?
    public let squad: String
    public let cluster: String?
    public let action: RelayInspectionAction?
    public let simulation: ProposalInspectionSimulation
    public let proposal: ProposalInspectionProposal
}

public struct ExecutedTransactionInspectionReport: Decodable, Equatable, Sendable {
    public let kind: String?
    public let signature: String
    public let cluster: String?
    public let status: ExecutedTransactionInspectionStatus
    public let action: RelayInspectionAction
    public let logs: [String]
}

public struct ExecutedTransactionInspectionStatus: Decodable, Equatable, Sendable {
    public let status: String
    public let slot: UInt64?
    public let blockTime: Int64?
    public let error: String?

    public init(status: String, slot: UInt64?, blockTime: Int64?, error: String?) {
        self.status = status
        self.slot = slot
        self.blockTime = blockTime
        self.error = error
    }
}

public struct RelayInspectionAction: Decodable, Equatable, Sendable {
    public let classification: String
    public let summary: String
    public let confidence: String
    public let effects: [RelayInspectionEffect]
    public let warnings: [RelayInspectionWarning]

    public init(
        classification: String,
        summary: String,
        confidence: String,
        effects: [RelayInspectionEffect],
        warnings: [RelayInspectionWarning]
    ) {
        self.classification = classification
        self.summary = summary
        self.confidence = confidence
        self.effects = effects
        self.warnings = warnings
    }
}

public struct RelayInspectionEffect: Decodable, Equatable, Sendable {
    public let kind: String
    public let summary: String
    public let program: String?
    public let asset: String?
    public let amount: String?
    public let source: String?
    public let destination: String?

    public init(
        kind: String,
        summary: String,
        program: String?,
        asset: String?,
        amount: String?,
        source: String?,
        destination: String?
    ) {
        self.kind = kind
        self.summary = summary
        self.program = program
        self.asset = asset
        self.amount = amount
        self.source = source
        self.destination = destination
    }
}

public struct RelayInspectionWarning: Decodable, Equatable, Sendable {
    public let severity: String
    public let code: String
    public let message: String

    public init(severity: String, code: String, message: String) {
        self.severity = severity
        self.code = code
        self.message = message
    }
}

public struct ProposalInspectionSimulation: Decodable, Equatable, Sendable {
    public let status: String
    public let message: String
    public let error: String?
    public let logs: [String]
    public let feePayer: String?
    public let recentBlockhash: String?
}

public struct ProposalInspectionProposal: Decodable, Equatable, Sendable {
    public let transactionIndex: UInt64
    public let status: String
    public let kind: String
    public let threshold: UInt16
    public let votes: ProposalInspectionVotes
    public let voters: ProposalInspectionVoters
    public let transactionAddress: String?
    public let accountsReferenced: [String]
    public let instructions: [ProposalInspectionInstruction]
    public var proposer: String?
    public var createdAtUnix: Int64?
}
