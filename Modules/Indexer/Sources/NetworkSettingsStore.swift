import Core
import Foundation
import Observation

@Observable
public final class NetworkSettingsStore {
    public static let developerRPCURLScheme = "cosign-dev"
    public static let developerDemoRPCURLScheme = "cosign-demo-dev"

    /// The relay endpoint — the app's single source for Solana RPC, WebSocket,
    /// and the cosign/v1 add-ons. Editable (so self-hosters can point at their
    /// own relay); defaults to the build's relay.
    public private(set) var rpcURL: URL
    public private(set) var loadErrorMessage: String?
    public private(set) var pendingRPCURLDraft: PendingRPCURLDraft?

    public let networkHealth = NetworkHealth()

    /// The active Solana network. Switch with `switch(to:)`.
    public private(set) var selectedNetwork: Network

    /// True when a custom relay URL is saved to the Keychain, causing
    /// `environment` to route through that URL rather than the network default.
    public private(set) var hasCustomRelayOverride: Bool

    private let rpcURLKeychain: SecureNetworkURLKeychain
    private let defaultRPCURL: URL
    private let networkDefaults: UserDefaults
    private static let selectedNetworkKey = "cosign.selectedNetwork"

    public static var defaultRPCURL: URL {
        CosignBuildEnvironment.current().relayURL ?? IndexerEnvironment.devnetRPCURL
    }

    public convenience init() {
        self.init(rpcURLKeychain: .rpcURL)
    }

    init(rpcURLKeychain: SecureNetworkURLKeychain, networkDefaults: UserDefaults = .standard) {
        let fallback = NetworkSettingsStore.defaultRPCURL
        defaultRPCURL = fallback
        self.rpcURLKeychain = rpcURLKeychain
        self.networkDefaults = networkDefaults

        var hadKeychainURL = false
        do {
            if let storedRPCURL = try rpcURLKeychain.load() {
                rpcURL = try NetworkSettingsStore.validatedRPCURL(from: storedRPCURL)
                hadKeychainURL = true
            } else {
                rpcURL = fallback
            }
        } catch {
            rpcURL = fallback
            loadErrorMessage = "Failed to load the saved relay endpoint from the Keychain."
        }
        hasCustomRelayOverride = hadKeychainURL

        // Use the persisted network if one exists; otherwise default to .mainnet
        // until resolveInitialNetwork(_:) is called with signer context.
        let stored = networkDefaults.string(forKey: NetworkSettingsStore.selectedNetworkKey)
            .flatMap(Network.init(rawValue:))
        selectedNetwork = stored ?? .mainnet
        if !hadKeychainURL {
            rpcURL = NetworkConfig.config(for: selectedNetwork, build: .current()).relayURL
        }
    }

    /// Call once after the SwiftData container is available. If no network
    /// preference has been persisted yet, computes the migration default
    /// (mainnet for fresh installs, devnet for installs with existing signers)
    /// and persists it.
    public func resolveInitialNetwork(hasExistingSigners: Bool) {
        guard networkDefaults.string(forKey: Self.selectedNetworkKey) == nil else { return }
        let resolved = Self.defaultNetwork(hasExistingSigners: hasExistingSigners, stored: nil)
        selectedNetwork = resolved
        networkDefaults.set(resolved.rawValue, forKey: Self.selectedNetworkKey)
        if !hasCustomRelayOverride {
            rpcURL = NetworkConfig.config(for: resolved, build: .current()).relayURL
        }
    }

    /// Migration default: stored preference wins; otherwise mainnet for fresh
    /// installs and devnet for installs that already have signers.
    public static func defaultNetwork(hasExistingSigners: Bool, stored: Network?) -> Network {
        if let stored { return stored }
        return hasExistingSigners ? .devnet : .mainnet
    }

    /// Always a relay client. When a custom relay URL is active, routes through
    /// that URL; otherwise derives everything from `selectedNetwork`.
    /// In both branches, `explorerRPCURL` and airdrop follow `selectedNetwork`.
    public var environment: IndexerEnvironment {
        let cfg = NetworkConfig.config(for: selectedNetwork, build: .current())
        if hasCustomRelayOverride {
            return IndexerEnvironment(
                rpcURL: rpcURL,
                relay: HTTPRelayClient(
                    baseURL: rpcURL,
                    capabilities: RelayCapability.enhancedFeatures,
                    healthReporter: networkHealth.reporter()
                ),
                webSocketURL: SolanaWebSocketEndpoint.relayWebSocketURL(for: rpcURL),
                explorerRPCURL: cfg.explorerRPCURL,
                supportsAirdrop: cfg.supportsAirdrop
            )
        }
        return IndexerEnvironment.forNetwork(selectedNetwork, healthReporter: networkHealth.reporter())
    }

    /// Switches the active network, drops any custom relay override, and
    /// persists the new preference. No-op if already on the requested network.
    public func `switch`(to network: Network) {
        guard network != selectedNetwork else { return }
        selectedNetwork = network
        networkDefaults.set(network.rawValue, forKey: Self.selectedNetworkKey)
        try? rpcURLKeychain.delete()
        hasCustomRelayOverride = false
        rpcURL = NetworkConfig.config(for: network, build: .current()).relayURL
    }

    public var redactedRPCURLString: String {
        NetworkSettingsStore.redactedRPCURLString(for: rpcURL)
    }

    public var rpcURLInfo: RPCURLInfo {
        NetworkSettingsStore.rpcURLInfo(for: rpcURL)
    }

    public func saveRPCURL(_ value: String) throws {
        let url = try NetworkSettingsStore.validatedRPCURL(from: value)
        try rpcURLKeychain.save(url.absoluteString)
        rpcURL = url
        hasCustomRelayOverride = true
        pendingRPCURLDraft = nil
        loadErrorMessage = nil
    }

    public func resetRPCURL() throws {
        try rpcURLKeychain.delete()
        rpcURL = NetworkConfig.config(for: selectedNetwork, build: .current()).relayURL
        hasCustomRelayOverride = false
        pendingRPCURLDraft = nil
        loadErrorMessage = nil
    }

    public func prepareRPCURLUpdate(from url: URL) throws {
        let rpcURL = try NetworkSettingsStore.rpcURL(fromDeepLink: url)
        pendingRPCURLDraft = PendingRPCURLDraft(rpcURL: rpcURL)
    }

    public func discardPendingRPCURLDraft() {
        pendingRPCURLDraft = nil
    }
}

public extension NetworkSettingsStore {
    static func validatedRPCURL(from value: String) throws -> URL {
        try validatedHTTPURL(from: value, invalidError: .invalidRPCURL)
    }

    private static func validatedHTTPURL(from value: String, invalidError: NetworkSettingsError) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host?.isEmpty == false
        else {
            throw invalidError
        }
        return url
    }

    static func redactedRPCURLString(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        components.queryItems = components.queryItems?.map { queryItem in
            guard isSensitiveQueryItem(queryItem.name) else {
                return queryItem
            }
            return URLQueryItem(name: queryItem.name, value: "redacted")
        }
        return components.url?.absoluteString ?? url.absoluteString
    }

    static func rpcURLInfo(for url: URL) -> RPCURLInfo {
        let host = url.host?.lowercased() ?? ""
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let hasCredentials = queryItems.contains { isSensitiveQueryItem($0.name) && ($0.value?.isEmpty == false) }
        return RPCURLInfo(
            provider: provider(forHost: host),
            cluster: cluster(forHost: host, queryItems: queryItems),
            host: host,
            hasCredentials: hasCredentials,
            redactedURLString: redactedRPCURLString(for: url)
        )
    }

    static func rpcURL(fromDeepLink url: URL) throws -> URL {
        guard
            url.scheme.map(supportedDeveloperRPCURLSchemes.contains) == true,
            url.host == "network",
            ["/rpc", "/relay"].contains(url.path)
        else {
            throw NetworkSettingsError.unsupportedDeepLink
        }

        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let rpcURLString = components.queryItems?.first(where: { $0.name == "url" })?.value
        else {
            throw NetworkSettingsError.missingRPCURL
        }

        return try validatedRPCURL(from: rpcURLString)
    }
}

private extension NetworkSettingsStore {
    private static let supportedDeveloperRPCURLSchemes: Set<String> = [
        developerRPCURLScheme,
        developerDemoRPCURLScheme
    ]

    private static func isSensitiveQueryItem(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized == "api-key" ||
            normalized == "apikey" ||
            normalized == "key" ||
            normalized == "token" ||
            normalized == "access_token"
    }

    private static func provider(forHost host: String) -> RPCURLProvider {
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return .local
        }
        if host.hasSuffix("helius-rpc.com") || host.hasSuffix("helius.xyz") {
            return .helius
        }
        if host.hasSuffix("solana.com") {
            return .solanaPublic
        }
        return .custom
    }

    private static func cluster(forHost host: String, queryItems: [URLQueryItem]) -> RPCCluster {
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return .local
        }

        if let cluster = queryItems.first(where: { $0.name.lowercased() == "cluster" })?.value?.lowercased() {
            switch cluster {
            case "devnet":
                return .devnet
            case "testnet":
                return .testnet
            case "mainnet", "mainnet-beta", "mainnet_beta":
                return .mainnetBeta
            default:
                break
            }
        }

        if host.contains("devnet") {
            return .devnet
        }
        if host.contains("testnet") {
            return .testnet
        }
        if host.contains("mainnet") {
            return .mainnetBeta
        }
        return .unknown
    }
}
