import XCTest
@testable import Indexer

final class IndexerEnvironmentAirdropTests: XCTestCase {
    func testDevnetSupportsAirdrop() {
        XCTAssertTrue(IndexerEnvironment.devnet.supportsAirdrop)
        XCTAssertEqual(
            IndexerEnvironment.devnet.airdropRPCURL,
            IndexerEnvironment.devnetRPCURL
        )
    }

    func testDefaultInitDoesNotSupportAirdrop() {
        let env = IndexerEnvironment(rpcURL: IndexerEnvironment.mainnetRPCURL)
        XCTAssertFalse(env.supportsAirdrop)
    }
}
