import Squads
import Testing
@testable import UI

struct RegistryConfidenceTests {
    private let registry = DecodeProvenance.registry(action: "Swap", source: "Cosign", boundProgram: nil)

    @Test func confirmedEarnsKnown() {
        #expect(registryConfidence(provenance: registry, crossCheck: .confirmed) == .known)
    }

    @Test func unconfirmedStaysIdl() {
        #expect(registryConfidence(provenance: registry, crossCheck: .unconfirmed) == .idl)
    }

    @Test func noVerdictStaysIdl() {
        #expect(registryConfidence(provenance: registry, crossCheck: nil) == .idl)
    }

    @Test func contradictedDropsAction() {
        #expect(registryConfidence(provenance: registry, crossCheck: .contradicted) == nil)
    }

    @Test func idlProvenanceUnchanged() {
        #expect(registryConfidence(provenance: .onChainIDL(idlName: "x", hash: "h", slot: 1), crossCheck: nil) == .idl)
    }
}
