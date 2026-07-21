import Foundation
import Testing
@testable import Indexer

struct ProgramIDLClientTests {
    @Test func programIDLIsAnEnhancedFeature() {
        #expect(RelayCapability.enhancedFeatures.contains(.programIDL))
    }

    @Test func noOpRelayReportsUnavailable() async {
        let relay = NoOpRelay()
        #expect(relay.programIDLURL(for: ProgramIDLRequest(programID: "x")) == nil)
        await #expect(throws: RelayClientError.self) {
            _ = try await relay.programIDL(for: ProgramIDLRequest(programID: "x"))
        }
    }

    @Test func decodesResponseEnvelope() throws {
        let json = """
        {
          "ok": true, "kind": "program_idl", "program": "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc",
          "idl": { "metadata": { "name": "whirlpool" }, "instructions": [] },
          "hash": "abc123", "slot": 42, "authority": "auth"
        }
        """
        let response = try JSONDecoder().decode(ProgramIDLResponse.self, from: Data(json.utf8))
        #expect(response.program == "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc")
        #expect(response.idl.name == "whirlpool")
        #expect(response.hash == "abc123")
        #expect(response.slot == 42)
    }
}
