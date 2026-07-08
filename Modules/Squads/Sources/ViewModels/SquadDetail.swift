import Foundation
import Indexer

public struct SquadDetail: Equatable, Sendable, Identifiable {
    public var id: String {
        address
    }

    public let address: String
    public let displayName: String?
    public let threshold: UInt16
    public let timeLockSeconds: UInt32
    public let rentCollector: String?
    public let transactionIndex: UInt64
    public let staleTransactionIndex: UInt64
    public let isAutonomous: Bool
    public let members: [SquadMember]
    public let vaults: [VaultDetail]

    public init(
        address: String,
        displayName: String? = nil,
        threshold: UInt16,
        timeLockSeconds: UInt32,
        rentCollector: String? = nil,
        transactionIndex: UInt64,
        staleTransactionIndex: UInt64,
        isAutonomous: Bool = true,
        members: [SquadMember],
        vaults: [VaultDetail]
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
}

public struct SquadMember: Equatable, Sendable, Identifiable {
    public var id: String {
        pubkey
    }

    public let pubkey: String
    public let canInitiate: Bool
    public let canVote: Bool
    public let canExecute: Bool

    public init(pubkey: String, canInitiate: Bool, canVote: Bool, canExecute: Bool) {
        self.pubkey = pubkey
        self.canInitiate = canInitiate
        self.canVote = canVote
        self.canExecute = canExecute
    }
}

public struct SquadVaultRef: Equatable, Sendable, Identifiable {
    public var id: UInt8 {
        index
    }

    public let index: UInt8
    public let address: String

    public init(index: UInt8, address: String) {
        self.index = index
        self.address = address
    }
}

public struct VaultDetail: Equatable, Sendable, Identifiable {
    public var id: UInt8 {
        ref.index
    }

    public let ref: SquadVaultRef
    public let nativeBalanceLamports: UInt64?
    public let assets: [DASAsset]

    public init(ref: SquadVaultRef, nativeBalanceLamports: UInt64?, assets: [DASAsset]) {
        self.ref = ref
        self.nativeBalanceLamports = nativeBalanceLamports
        self.assets = assets
    }
}
