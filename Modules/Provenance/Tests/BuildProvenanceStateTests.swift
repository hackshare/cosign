import XCTest
@testable import Provenance

final class BuildProvenanceStateTests: XCTestCase {
    func test_testBundleHasNoEmbeddedClaim_reportsDevelopmentBuild() {
        let state = BuildClaimVerifier.provenanceState(bundle: .main)
        guard case .developmentBuild = state else {
            return XCTFail("Expected development build in a bundle without an embedded claim, got \(state)")
        }
    }
}
