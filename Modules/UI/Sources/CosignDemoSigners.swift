import Core
import CosignCore
import Foundation

public struct CosignDemoSignerSeed: Equatable, Sendable {
    public let id: UUID
    public let label: String
    public let type: SignerType
    public let pubkey: Pubkey
    public let keychainItemRef: String
    public let createdAt: Date
}

public enum CosignDemoSigners {
    public static let appStore: [CosignDemoSignerSeed] = [
        CosignDemoSignerSeed(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            label: CosignCopy.Demo.operationsSignerLabel,
            type: .hotWallet,
            pubkey: Data((0 ..< 32).map { UInt8($0 + 1) }),
            keychainItemRef: "cosign-demo-operations",
            createdAt: Date(timeIntervalSince1970: 1_779_200_000)
        ),
        CosignDemoSignerSeed(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            label: CosignCopy.Demo.treasurySignerLabel,
            type: .ledger,
            pubkey: Data((0 ..< 32).map { UInt8($0 + 33) }),
            keychainItemRef: "cosign-demo-treasury",
            createdAt: Date(timeIntervalSince1970: 1_779_200_060)
        ),
        CosignDemoSignerSeed(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            label: CosignCopy.Demo.localDevnetSignerLabel,
            type: .yubikey,
            pubkey: Data((0 ..< 32).map { UInt8($0 + 65) }),
            keychainItemRef: "cosign-demo-local-devnet",
            createdAt: Date(timeIntervalSince1970: 1_779_200_120)
        )
    ]

    public static let nullStates: [CosignDemoSignerSeed] = [
        CosignDemoSignerSeed(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            label: CosignCopy.Demo.emptyPortfolioSignerLabel,
            type: .hotWallet,
            pubkey: Data((0 ..< 32).map { UInt8($0 + 97) }),
            keychainItemRef: "cosign-demo-empty-portfolio",
            createdAt: Date(timeIntervalSince1970: 1_779_300_000)
        ),
        CosignDemoSignerSeed(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            label: CosignCopy.Demo.noVaultsSignerLabel,
            type: .ledger,
            pubkey: Data((0 ..< 32).map { UInt8($0 + 129) }),
            keychainItemRef: "cosign-demo-no-vaults",
            createdAt: Date(timeIntervalSince1970: 1_779_300_060)
        ),
        CosignDemoSignerSeed(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            label: CosignCopy.Demo.detachedSignerLabel,
            type: .yubikey,
            pubkey: Data((0 ..< 32).map { UInt8($0 + 161) }),
            keychainItemRef: "cosign-demo-detached",
            createdAt: Date(timeIntervalSince1970: 1_779_300_120)
        )
    ]

    public static let noSigners: [CosignDemoSignerSeed] = []

    public static func seeds(for profile: String) -> [CosignDemoSignerSeed] {
        switch profile.lowercased() {
        case "nosigners":
            noSigners
        case "nullstates":
            nullStates
        default:
            appStore
        }
    }

    public static func memberAddresses(for profile: String) -> [String] {
        seeds(for: profile).map { CosignCore.base58($0.pubkey) }
    }
}
