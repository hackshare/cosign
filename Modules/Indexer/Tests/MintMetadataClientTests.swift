import Foundation
import Testing
@testable import Indexer

struct MintMetadataClientTests {
    @Test func mintMetadataIsAnEnhancedFeature() {
        #expect(RelayCapability.enhancedFeatures.contains(.mintMetadata))
    }

    @Test func noOpRelayReportsUnavailable() async {
        let relay = NoOpRelay()
        #expect(relay.mintMetadataURL(for: MintMetadataRequest(account: "M")) == nil)
        await #expect(throws: RelayClientError.self) {
            _ = try await relay.mintMetadata(for: MintMetadataRequest(account: "M"))
        }
    }

    @Test func decodesResponseWithNullSymbol() throws {
        let json = #"{"kind":"mint_metadata","account":"A","mint":"M","decimals":6,"symbol":null}"#
        let response = try JSONDecoder().decode(MintMetadataResponse.self, from: Data(json.utf8))
        #expect(response.mint == "M")
        #expect(response.decimals == 6)
        #expect(response.symbol == nil)
    }
}
