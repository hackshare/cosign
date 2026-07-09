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
