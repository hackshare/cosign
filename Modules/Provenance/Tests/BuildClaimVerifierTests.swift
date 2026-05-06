import XCTest
@testable import Provenance

final class BuildClaimVerifierTests: XCTestCase {
    static let claimB64 = "eyJidWlsZCI6IjEiLCJjb21taXRTaGEiOiJhYmMiLCJkZXBlbmRlbmN5TG9ja1Jvb3QiOiJzaGEyNTY6eCIsImJ1aWxkUmVjaXBlU2hhMjU2Ijoic2hhMjU2OnkiLCJrZXlJZCI6ImNvc2lnbi1yZWxlYXNlLXRlc3QiLCJyZXBvc2l0b3J5IjoiaGFja3NoYXJlL2Nvc2lnbiIsInNjaGVtYSI6MSwidGFnIjoidjAuMC4wKzEiLCJ0YWdPYmplY3RTaGEiOiJkZWYiLCJ0b29sY2hhaW4iOnsiaXBob25lT1NTREsiOiIyNi4wIiwibWFjT1NCdWlsZCI6IjI0Rjc0IiwibWFjT1NQcm9kdWN0VmVyc2lvbiI6IjI2LjAiLCJzd2lmdCI6IngiLCJ4Y29kZSI6IjI2LjUifSwidmVyc2lvbiI6IjAuMC4wIn0K"
    static let sigB64 = "yQRKR++PE+uK7dpW7IpKSjc6RWDDDOAHlVPQ1I2F4ezpj8I0ZPoPhmsjXcYcxgBvcQYs+dytjuJanF/En+BMCQ=="

    private var claim: Data {
        Data(base64Encoded: Self.claimB64)!
    }

    private func verify(
        claim: Data,
        sig: String = sigB64,
        version: String = "0.0.0",
        build: String = "1"
    ) throws -> VerifiedBuildClaim {
        try BuildClaimVerifier.verify(
            claimData: claim, signatureBase64: sig,
            bundleVersion: version, bundleBuild: build
        )
    }

    func test_validClaimVerifies() throws {
        let result = try verify(claim: claim)
        XCTAssertEqual(result.claim.version, "0.0.0")
        XCTAssertEqual(result.claim.keyId, "cosign-release-test")
        XCTAssertEqual(result.fingerprint.count, 64)
    }

    func test_tamperedClaimFails() throws {
        var bytes = claim
        let needle = Data("\"commitSha\":\"abc\"".utf8)
        let range = try XCTUnwrap(bytes.range(of: needle))
        bytes[range.upperBound - 2] = UInt8(ascii: "d")
        XCTAssertThrowsError(try verify(claim: bytes)) {
            XCTAssertEqual($0 as? BuildClaimVerificationError, .invalidSignature)
        }
    }

    func test_unknownKeyFails() throws {
        XCTAssertThrowsError(try BuildClaimVerifier.verify(
            claimData: claim, signatureBase64: Self.sigB64,
            bundleVersion: "0.0.0", bundleBuild: "1", publicKeys: [:]
        )) { XCTAssertEqual($0 as? BuildClaimVerificationError, .unknownKey) }
    }

    func test_versionMismatchFails() throws {
        XCTAssertThrowsError(try verify(claim: claim, version: "9.9.9")) {
            XCTAssertEqual($0 as? BuildClaimVerificationError, .versionMismatch)
        }
    }

    func test_buildMismatchFails() throws {
        XCTAssertThrowsError(try verify(claim: claim, build: "999")) {
            XCTAssertEqual($0 as? BuildClaimVerificationError, .buildMismatch)
        }
    }
}
