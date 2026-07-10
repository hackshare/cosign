import Core
import Foundation

public struct NetworkConfig: Sendable {
    public let relayURL: URL
    public let explorerRPCURL: URL
    public let supportsAirdrop: Bool

    public static func config(for network: Network, build: CosignBuildEnvironment) -> NetworkConfig {
        switch network {
        case .devnet:
            NetworkConfig(
                relayURL: build.devnetRelayURL ?? IndexerEnvironment.devnetRPCURL,
                explorerRPCURL: IndexerEnvironment.devnetRPCURL,
                supportsAirdrop: true
            )
        case .mainnet:
            NetworkConfig(
                relayURL: build.mainnetRelayURL ?? IndexerEnvironment.mainnetRPCURL,
                explorerRPCURL: IndexerEnvironment.mainnetRPCURL,
                supportsAirdrop: false
            )
        }
    }
}

public extension IndexerEnvironment {
    static func forNetwork(
        _ network: Network,
        build: CosignBuildEnvironment = .current(),
        healthReporter: NetworkHealthReporter?
    ) -> IndexerEnvironment {
        let cfg = NetworkConfig.config(for: network, build: build)
        return IndexerEnvironment(
            rpcURL: cfg.relayURL,
            relay: HTTPRelayClient(
                baseURL: cfg.relayURL,
                capabilities: RelayCapability.enhancedFeatures,
                healthReporter: healthReporter
            ),
            webSocketURL: SolanaWebSocketEndpoint.relayWebSocketURL(for: cfg.relayURL),
            explorerRPCURL: cfg.explorerRPCURL,
            supportsAirdrop: cfg.supportsAirdrop
        )
    }
}
