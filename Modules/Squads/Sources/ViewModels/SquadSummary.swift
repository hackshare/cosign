import Foundation

public struct SquadSummary: Equatable, Sendable, Identifiable {
    public var id: String {
        address
    }

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
