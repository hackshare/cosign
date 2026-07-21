import CryptoKit
import Foundation
import Indexer

public enum DecodeRegistryPublicKeys {
    /// Curve25519 public keys keyed by `keyId`. Populated with the Cosign registry
    /// key when the production bundle is signed; empty until then.
    public static let all: [String: String] = [:]
}

public enum DecodeRegistryVerificationError: Error, Equatable {
    case invalidSignatureEncoding
    case unknownKey
    case invalidSignature
    case malformedBundle
}

public enum DecodeRegistryVerifier {
    public static func verify(
        _ response: DecodeRegistryResponse,
        publicKeys: [String: String] = DecodeRegistryPublicKeys.all
    ) throws -> DecodeRegistryBundle {
        guard let signature = Data(base64Encoded: response.signatureBase64
            .trimmingCharacters(in: .whitespacesAndNewlines))
        else { throw DecodeRegistryVerificationError.invalidSignatureEncoding }

        guard let bundle = try? JSONDecoder().decode(DecodeRegistryBundle.self, from: response.bundleData)
        else { throw DecodeRegistryVerificationError.malformedBundle }

        guard let publicKeyBase64 = publicKeys[bundle.keyId],
              let publicKeyData = Data(base64Encoded: publicKeyBase64)
        else { throw DecodeRegistryVerificationError.unknownKey }

        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        guard publicKey.isValidSignature(signature, for: response.bundleData)
        else { throw DecodeRegistryVerificationError.invalidSignature }

        return bundle
    }
}
