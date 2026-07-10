import XCTest
@testable import Core
@testable import Indexer

final class NetworkConfigTests: XCTestCase {
    private let build = CosignBuildEnvironment.current(infoDictionary: [
        "CosignDevnetRelayURL": "https://cosign-relay-devnet.fly.dev",
        "CosignMainnetRelayURL": "https://cosign-relay-mainnet.fly.dev"
    ])

    func testDevnet() {
        let cfg = NetworkConfig.config(for: .devnet, build: build)
        XCTAssertEqual(cfg.relayURL.absoluteString, "https://cosign-relay-devnet.fly.dev")
        XCTAssertEqual(cfg.explorerRPCURL, IndexerEnvironment.devnetRPCURL)
        XCTAssertTrue(cfg.supportsAirdrop)
    }

    func testMainnet() {
        let cfg = NetworkConfig.config(for: .mainnet, build: build)
        XCTAssertEqual(cfg.relayURL.absoluteString, "https://cosign-relay-mainnet.fly.dev")
        XCTAssertEqual(cfg.explorerRPCURL, IndexerEnvironment.mainnetRPCURL)
        XCTAssertFalse(cfg.supportsAirdrop)
    }

    func testEnvironmentFactoryWiresRelayAndExplorer() {
        let env = IndexerEnvironment.forNetwork(.mainnet, build: build, healthReporter: nil)
        XCTAssertEqual(env.rpcURL.absoluteString, "https://cosign-relay-mainnet.fly.dev")
        XCTAssertEqual(env.explorerRPCURL, IndexerEnvironment.mainnetRPCURL)
        XCTAssertFalse(env.supportsAirdrop)
    }
}
