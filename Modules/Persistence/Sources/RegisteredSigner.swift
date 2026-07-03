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

    /// A hot wallet imported from a raw secret key holds no recovery phrase on
    /// this device — the secret key is its only backup. This distinguishes such
    /// keyless imports from phrase-backed hot wallets for the detail screen.
    public var importedWithoutPhrase: Bool = false

    public init(
        id: UUID = UUID(),
        label: String,
        type: SignerType,
        pubkey: Pubkey,
        keychainItemRef: String? = nil,
        createdAt: Date = .now,
        backedUp: Bool = true,
        backedUpAt: Date? = nil,
        importedWithoutPhrase: Bool = false
    ) {
        self.id = id
        self.label = label
        typeRaw = type.rawValue
        pubkeyData = pubkey
        self.keychainItemRef = keychainItemRef
        self.createdAt = createdAt
        self.backedUp = backedUp
        self.backedUpAt = backedUpAt
        self.importedWithoutPhrase = importedWithoutPhrase
    }

    public var type: SignerType {
        SignerType(rawValue: typeRaw) ?? .hotWallet
    }

    public var pubkey: Pubkey {
        pubkeyData
    }
}
