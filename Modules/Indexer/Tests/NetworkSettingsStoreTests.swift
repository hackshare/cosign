import Foundation
import Testing
@testable import Indexer

struct NetworkSettingsStoreTests {
    @Test func validatesHTTPRPCURLs() throws {
        let url = try NetworkSettingsStore.validatedRPCURL(from: " https://devnet.helius-rpc.com/?api-key=secret ")

        #expect(url.absoluteString == "https://devnet.helius-rpc.com/?api-key=secret")
    }

    @Test func rejectsInvalidRPCURLs() {
        #expect(throws: NetworkSettingsError.invalidRPCURL) {
            _ = try NetworkSettingsStore.validatedRPCURL(from: "devnet.helius-rpc.com")
        }
    }

    @Test func redactsSensitiveQueryItems() throws {
        let url = try #require(URL(string: "https://devnet.helius-rpc.com/?api-key=secret&cluster=devnet"))

        #expect(
            NetworkSettingsStore.redactedRPCURLString(for: url) ==
                "https://devnet.helius-rpc.com/?api-key=redacted&cluster=devnet"
        )
    }

    @Test func describesHeliusDevnetURL() throws {
        let url = try #require(URL(string: "https://devnet.helius-rpc.com/?api-key=secret"))

        let info = NetworkSettingsStore.rpcURLInfo(for: url)

        #expect(info.provider == .helius)
        #expect(info.cluster == .devnet)
        #expect(info.host == "devnet.helius-rpc.com")
        #expect(info.hasCredentials)
    }

    @Test func describesPublicSolanaMainnetURL() throws {
        let url = try #require(URL(string: "https://api.mainnet-beta.solana.com"))

        let info = NetworkSettingsStore.rpcURLInfo(for: url)

        #expect(info.provider == .solanaPublic)
        #expect(info.cluster == .mainnetBeta)
        #expect(!info.hasCredentials)
    }

    @Test func parsesRPCURLFromDeveloperDeepLink() throws {
        let deepLink = try makeNetworkSettingsLink(path: "/rpc", url: "https://devnet.helius-rpc.com/?api-key=secret")

        #expect(
            try NetworkSettingsStore.rpcURL(fromDeepLink: deepLink).absoluteString ==
                "https://devnet.helius-rpc.com/?api-key=secret"
        )
    }

    @Test func parsesRPCURLFromDemoDeveloperDeepLink() throws {
        let deepLink = try makeNetworkSettingsLink(
            scheme: NetworkSettingsStore.developerDemoRPCURLScheme,
            path: "/rpc",
            url: "https://relay.cosign.example"
        )

        #expect(
            try NetworkSettingsStore.rpcURL(fromDeepLink: deepLink).absoluteString ==
                "https://relay.cosign.example"
        )
    }

    @Test func parsesRelayURLFromDeveloperDeepLink() throws {
        let deepLink = try makeNetworkSettingsLink(path: "/relay", url: "http://localhost:8787")

        #expect(
            try NetworkSettingsStore.rpcURL(fromDeepLink: deepLink).absoluteString ==
                "http://localhost:8787"
        )
    }

    @Test func deepLinkDraftDoesNotPersistUntilSaved() throws {
        var savedValue: String?
        let store = NetworkSettingsStore(
            rpcURLKeychain: SecureNetworkURLKeychain(
                load: { nil },
                save: { savedValue = $0 },
                delete: {}
            )
        )
        let deepLink = try makeNetworkSettingsLink(path: "/rpc", url: "https://devnet.helius-rpc.com/?api-key=secret")

        try store.prepareRPCURLUpdate(from: deepLink)

        #expect(store.rpcURL == NetworkSettingsStore.defaultRPCURL)
        #expect(store.pendingRPCURLDraft?.rpcURL.absoluteString == "https://devnet.helius-rpc.com/?api-key=secret")
        #expect(savedValue == nil)
    }

    @Test func environmentRoutesEverythingThroughTheRelay() {
        let store = NetworkSettingsStore(
            rpcURLKeychain: SecureNetworkURLKeychain(
                load: { "https://relay.cosign.example/api" },
                save: { _ in },
                delete: {}
            )
        )

        let url = store.environment.relay.proposalInspectionURL(for: ProposalInspectionRequest(
            squadAddress: "squad111",
            transactionIndex: 42
        ))

        #expect(url?
            .absoluteString ==
            "https://relay.cosign.example/api/cosign/v1/squads/squad111/transactions/42/inspection")
        #expect(store.environment.effectiveWebSocketURL?.absoluteString == "wss://relay.cosign.example/api/ws")
    }

    @Test func savingRelayURLUpdatesTheEnvironment() throws {
        var savedValue: String?
        let store = NetworkSettingsStore(
            rpcURLKeychain: SecureNetworkURLKeychain(load: { nil }, save: { savedValue = $0 }, delete: {})
        )

        try store.saveRPCURL("https://my-relay.example")

        #expect(store.rpcURL.absoluteString == "https://my-relay.example")
        #expect(savedValue == "https://my-relay.example")
        #expect(store.environment.rpcURL.absoluteString == "https://my-relay.example")
        #expect(store.environment.effectiveWebSocketURL?.absoluteString == "wss://my-relay.example/ws")
    }

    private func makeNetworkSettingsLink(
        scheme: String = NetworkSettingsStore.developerRPCURLScheme,
        path: String,
        url: String
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "network"
        components.path = path
        components.queryItems = [URLQueryItem(name: "url", value: url)]
        return try #require(components.url)
    }
}
