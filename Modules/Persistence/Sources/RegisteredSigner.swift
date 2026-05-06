import Core
import Foundation
import SwiftData

@Model
public final class RegisteredSigner {
    public var id: UUID
    public var label: String
    public var typeRaw: String
    public var pubkeyData: Data
    public var keychainItemRef: String?
    public var createdAt: Date
    public var backedUp: Bool = true
    public var backedUpAt: Date?

    public init(
        id: UUID = UUID(),
        label: String,
        type: SignerType,
        pubkey: Pubkey,
        keychainItemRef: String? = nil,
        createdAt: Date = .now,
        backedUp: Bool = true,
        backedUpAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        typeRaw = type.rawValue
        pubkeyData = pubkey
        self.keychainItemRef = keychainItemRef
        self.createdAt = createdAt
        self.backedUp = backedUp
        self.backedUpAt = backedUpAt
    }

    public var type: SignerType {
        SignerType(rawValue: typeRaw) ?? .hotWallet
    }

    public var pubkey: Pubkey {
        pubkeyData
    }
}
