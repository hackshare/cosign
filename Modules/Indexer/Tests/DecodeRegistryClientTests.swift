import Foundation
import Testing
@testable import Indexer

struct DecodeRegistryClientTests {
    @Test func decodeRegistryIsAnEnhancedFeature() {
        #expect(RelayCapability.enhancedFeatures.contains(.decodeRegistry))
    }

    @Test func noOpRelayReportsUnavailable() async {
        let relay = NoOpRelay()
        #expect(relay.decodeRegistryURL() == nil)
        await #expect(throws: RelayClientError.self) {
            _ = try await relay.decodeRegistry()
        }
    }
}
