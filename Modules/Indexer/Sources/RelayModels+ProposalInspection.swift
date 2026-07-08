public struct ProposalInspectionVotes: Decodable, Equatable, Sendable {
    public let approve: UInt32
    public let reject: UInt32
    public let cancel: UInt32
}

public struct ProposalInspectionVoters: Decodable, Equatable, Sendable {
    public let approve: [String]
    public let reject: [String]
    public let cancel: [String]
}

public struct ProposalInspectionConfigAction: Decodable, Equatable, Sendable {
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

public struct ProposalInspectionInstruction: Decodable, Equatable, Sendable {
    public let program: String
    public let kind: String
    public let summary: String
    public let accounts: [String]
    public let rawDataHex: String
    public let configAction: ProposalInspectionConfigAction?

    public init(
        program: String,
        kind: String,
        summary: String,
        accounts: [String],
        rawDataHex: String,
        configAction: ProposalInspectionConfigAction? = nil
    ) {
        self.program = program
        self.kind = kind
        self.summary = summary
        self.accounts = accounts
        self.rawDataHex = rawDataHex
        self.configAction = configAction
    }
}
