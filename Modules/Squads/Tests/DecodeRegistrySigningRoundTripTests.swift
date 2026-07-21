import CryptoKit
import Foundation
import Indexer
import Testing
@testable import Squads

struct DecodeRegistrySigningRoundTripTests {
    /// Signs the exact served bytes with an ephemeral key; DecodeRegistryVerifier
    /// accepts them, and a single appended newline breaks verification — proving the
    /// signer must sign the untrimmed bundle bytes (the Plan-1 byte-exactness guard).
    @Test func signServeVerifyRoundTrip() throws {
        let key = Curve25519.Signing.PrivateKey()
        let publicKeys = ["cosign-registry-2026": key.publicKey.rawRepresentation.base64EncodedString()]
        let bundle = Data(#"{"schema":1,"keyId":"cosign-registry-2026","specs":[]}"#.utf8)

        let signature = try key.signature(for: bundle).base64EncodedString()
        let validResponse = DecodeRegistryResponse(bundleData: bundle, signatureBase64: signature)
        let verified = try DecodeRegistryVerifier.verify(validResponse, publicKeys: publicKeys)
        #expect(verified.keyId == "cosign-registry-2026")

        let withNewline = DecodeRegistryResponse(bundleData: bundle + Data("\n".utf8), signatureBase64: signature)
        #expect(throws: DecodeRegistryVerificationError.self) {
            _ = try DecodeRegistryVerifier.verify(withNewline, publicKeys: publicKeys)
        }
    }

    /// The committed relay bundle bytes verify when signed as-is (they must never gain
    /// a trailing newline, or Task 9's production signature would be over the wrong bytes).
    @Test func committedBundleBytesRoundTrip() throws {
        let key = Curve25519.Signing.PrivateKey()
        let bundle = Data(#"{"schema":1,"keyId":"cosign-registry-2026","specs":[]}"#
            .utf8) // exact core/registry/decode-registry.json
        let response = try DecodeRegistryResponse(
            bundleData: bundle, signatureBase64: key.signature(for: bundle).base64EncodedString()
        )
        let publicKeys = ["cosign-registry-2026": key.publicKey.rawRepresentation.base64EncodedString()]
        #expect(try DecodeRegistryVerifier.verify(response, publicKeys: publicKeys).specs.isEmpty)
    }
}
