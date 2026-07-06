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

public struct ProposalInspectionInstruction: Decodable, Equatable, Sendable {
    public let program: String
    public let kind: String
    public let summary: String
    public let accounts: [String]
    public let rawDataHex: String
}
