import Foundation

public struct PendingRPCURLDraft: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let rpcURL: URL

    public var redactedRPCURLString: String {
        NetworkSettingsStore.redactedRPCURLString(for: rpcURL)
    }

    public var rpcURLInfo: RPCURLInfo {
        NetworkSettingsStore.rpcURLInfo(for: rpcURL)
    }
}

public struct RPCURLInfo: Equatable, Sendable {
    public let provider: RPCURLProvider
    public let cluster: RPCCluster
    public let host: String
    public let hasCredentials: Bool
    public let redactedURLString: String
}

public enum RPCURLProvider: String, Sendable {
    case helius
    case solanaPublic
    case local
    case custom
}

public enum RPCCluster: String, Sendable {
    case devnet
    case testnet
    case mainnetBeta
    case local
    case unknown
}

public enum NetworkSettingsError: LocalizedError, Equatable {
    case invalidRPCURL
    case keychainFailure(OSStatus)
    case missingRPCURL
    case unsupportedDeepLink

    public var errorDescription: String? {
        switch self {
        case .invalidRPCURL:
            "Enter a full HTTP or HTTPS Solana RPC or Cosign relay URL."
        case let .keychainFailure(status):
            "Keychain operation failed with status \(status)."
        case .missingRPCURL:
            "The link did not include a network endpoint URL."
        case .unsupportedDeepLink:
            "The link is not a supported Cosign network settings link."
        }
    }
}
