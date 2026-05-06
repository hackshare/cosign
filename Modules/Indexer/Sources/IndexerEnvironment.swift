import Foundation

/// The app is always a relay client. `rpcURL` is the relay endpoint — a
/// Solana-compatible RPC + WebSocket surface (passthrough) plus the cosign/v1
/// add-ons. Everything goes through this one URL; there is no direct-RPC path.
public struct IndexerEnvironment: Sendable {
    public var rpcURL: URL
    public var relay: any RelayClient
    /// Relay WebSocket URL (the relay's `/ws` proxy). Nil disables live updates
    /// (the demo build), leaving polling.
    public var webSocketURL: URL?
    public var explorerRPCURL: URL?

    public init(
        rpcURL: URL,
        relay: any RelayClient = NoOpRelay(),
        webSocketURL: URL? = nil,
        explorerRPCURL: URL? = nil
    ) {
        self.rpcURL = rpcURL
        self.relay = relay
        self.webSocketURL = webSocketURL
        self.explorerRPCURL = explorerRPCURL
    }
}

public extension IndexerEnvironment {
    static let mainnetRPCURL = URL(string: "https://mainnet.helius-rpc.com")!
    static let devnetRPCURL = URL(string: "https://api.devnet.solana.com")!

    static var devnet: IndexerEnvironment {
        IndexerEnvironment(rpcURL: devnetRPCURL)
    }

    var effectiveRPCURL: URL {
        rpcURL
    }

    var effectiveWebSocketURL: URL? {
        webSocketURL
    }

    var effectiveExplorerRPCURL: URL {
        explorerRPCURL ?? rpcURL
    }
}
