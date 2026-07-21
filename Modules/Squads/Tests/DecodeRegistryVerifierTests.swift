import CryptoKit
import Foundation
import Indexer
import Testing
@testable import Squads

struct DecodeRegistryVerifierTests {
    private func signedBundle(keyId: String) throws -> (DecodeRegistryResponse, [String: String]) {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
        let bundleJSON = "{\"schema\":1,\"keyId\":\"\(keyId)\",\"specs\":[]}"
        let bundleData = Data(bundleJSON.utf8)
        let signature = try privateKey.signature(for: bundleData).base64EncodedString()
        let response = DecodeRegistryResponse(bundleData: bundleData, signatureBase64: signature)
        return (response, [keyId: publicKeyBase64])
    }

    @Test func verifiesAValidBundle() throws {
        let (response, keys) = try signedBundle(keyId: "k1")
        let bundle = try DecodeRegistryVerifier.verify(response, publicKeys: keys)
        #expect(bundle.keyId == "k1")
        #expect(bundle.specs.isEmpty)
    }

    @Test func rejectsATamperedBundle() throws {
        var (response, keys) = try signedBundle(keyId: "k1")
        // Same signature, but validly-decodable different bytes (schema 1 -> 2):
        // this decodes fine and finds the key, so it must fail at the signature check.
        response = DecodeRegistryResponse(
            bundleData: Data("{\"schema\":2,\"keyId\":\"k1\",\"specs\":[]}".utf8),
            signatureBase64: response.signatureBase64
        )
        #expect(throws: DecodeRegistryVerificationError.invalidSignature) {
            _ = try DecodeRegistryVerifier.verify(response, publicKeys: keys)
        }
    }

    @Test func rejectsAnUnknownKey() throws {
        let (response, _) = try signedBundle(keyId: "k1")
        #expect(throws: DecodeRegistryVerificationError.unknownKey) {
            _ = try DecodeRegistryVerifier.verify(response, publicKeys: [:])
        }
    }
}
