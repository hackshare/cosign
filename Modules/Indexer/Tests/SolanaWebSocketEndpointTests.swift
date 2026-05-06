import Foundation
import Testing
@testable import Indexer

struct SolanaWebSocketEndpointTests {
    @Test func derivesRelayWebSocketURL() throws {
        let relayURL = try #require(URL(string: "https://relay.cosign.example"))

        #expect(
            SolanaWebSocketEndpoint.relayWebSocketURL(for: relayURL)?.absoluteString ==
                "wss://relay.cosign.example/ws"
        )
    }

    @Test func relayWebSocketURLKeepsPathPrefix() throws {
        let relayURL = try #require(URL(string: "https://relay.cosign.example/api/"))

        #expect(
            SolanaWebSocketEndpoint.relayWebSocketURL(for: relayURL)?.absoluteString ==
                "wss://relay.cosign.example/api/ws"
        )
    }

    @Test func environmentUsesExplicitWebSocketURL() throws {
        let relayURL = try #require(URL(string: "https://relay.cosign.example/api"))
        let webSocketURL = try #require(URL(string: "wss://relay.cosign.example/ws"))
        let explorerRPCURL = try #require(URL(string: "https://api.devnet.solana.com"))
        let environment = IndexerEnvironment(
            rpcURL: relayURL,
            relay: HTTPRelayClient(baseURL: relayURL),
            webSocketURL: webSocketURL,
            explorerRPCURL: explorerRPCURL
        )

        #expect(environment.effectiveWebSocketURL?.absoluteString == "wss://relay.cosign.example/ws")
        #expect(environment.effectiveExplorerRPCURL.absoluteString == "https://api.devnet.solana.com")
    }

    @Test func environmentWithoutWebSocketURLIsNil() throws {
        let relayURL = try #require(URL(string: "https://relay.cosign.example/api"))
        let environment = IndexerEnvironment(
            rpcURL: relayURL,
            relay: HTTPRelayClient(baseURL: relayURL)
        )

        #expect(environment.effectiveWebSocketURL == nil)
    }
}
