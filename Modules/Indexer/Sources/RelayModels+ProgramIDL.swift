import Foundation

public struct ProgramIDLRequest: Equatable, Sendable {
    public let programID: String

    public init(programID: String) {
        self.programID = programID
    }
}

public struct ProgramIDLResponse: Decodable, Equatable, Sendable {
    public let kind: String?
    public let cluster: String?
    public let program: String
    public let idl: AnchorIDLDocument
    public let hash: String
    public let slot: UInt64
    public let authority: String?

    public init(
        kind: String?,
        cluster: String?,
        program: String,
        idl: AnchorIDLDocument,
        hash: String,
        slot: UInt64,
        authority: String?
    ) {
        self.kind = kind
        self.cluster = cluster
        self.program = program
        self.idl = idl
        self.hash = hash
        self.slot = slot
        self.authority = authority
    }
}
