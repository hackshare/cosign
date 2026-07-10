import XCTest
@testable import Core
@testable import Indexer

final class NetworkStoreTests: XCTestCase {
    func testDefaultNetworkFreshInstallIsMainnet() {
        XCTAssertEqual(
            NetworkSettingsStore.defaultNetwork(hasExistingSigners: false, stored: nil),
            .mainnet
        )
    }

    func testDefaultNetworkExistingInstallKeepsDevnet() {
        XCTAssertEqual(
            NetworkSettingsStore.defaultNetwork(hasExistingSigners: true, stored: nil),
            .devnet
        )
    }

    func testStoredPreferenceWins() {
        XCTAssertEqual(
            NetworkSettingsStore.defaultNetwork(hasExistingSigners: true, stored: .mainnet),
            .mainnet
        )
        XCTAssertEqual(
            NetworkSettingsStore.defaultNetwork(hasExistingSigners: false, stored: .devnet),
            .devnet
        )
    }

    func testRpcURLFollowsSelectedNetworkWhenNoOverride() throws {
        try? SecureNetworkURLKeychain.rpcURL.delete() // ensure no custom override
        let suite = "test.combo.rpcurl.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = NetworkSettingsStore(rpcURLKeychain: .rpcURL, networkDefaults: defaults)
        // Fresh install (empty defaults) => mainnet, and rpcURL must be the mainnet relay.
        XCTAssertEqual(store.selectedNetwork, .mainnet)
        XCTAssertEqual(store.rpcURL, IndexerEnvironment.mainnetRPCURL)

        // Existing install (has signers) => devnet, and rpcURL must realign to devnet.
        store.resolveInitialNetwork(hasExistingSigners: true)
        XCTAssertEqual(store.selectedNetwork, .devnet)
        XCTAssertEqual(store.rpcURL, IndexerEnvironment.devnetRPCURL)
    }
}
