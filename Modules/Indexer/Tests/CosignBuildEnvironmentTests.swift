import XCTest
@testable import Indexer

final class CosignBuildEnvironmentTests: XCTestCase {
    func testReadsBothRelayURLs() {
        let env = CosignBuildEnvironment.current(infoDictionary: [
            "CosignDevnetRelayURL": "https://cosign-relay-devnet.fly.dev",
            "CosignMainnetRelayURL": "https://cosign-relay-mainnet.fly.dev"
        ])
        XCTAssertEqual(env.devnetRelayURL?.absoluteString, "https://cosign-relay-devnet.fly.dev")
        XCTAssertEqual(env.mainnetRelayURL?.absoluteString, "https://cosign-relay-mainnet.fly.dev")
    }

    func testMissingKeysAreNil() {
        let env = CosignBuildEnvironment.current(infoDictionary: [:])
        XCTAssertNil(env.devnetRelayURL)
        XCTAssertNil(env.mainnetRelayURL)
    }
}
