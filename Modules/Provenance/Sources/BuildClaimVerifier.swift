import CryptoKit
import Foundation

public struct VerifiedBuildClaim: Equatable, Sendable {
    public let claim: BuildClaim
    public let fingerprint: String
}

public enum BuildClaimVerificationError: Error, Equatable {
    case missingResource
    case invalidSignatureEncoding
    case unknownKey
    case invalidSignature
    case versionMismatch
    case buildMismatch
}

public enum BuildClaimVerifier {
    public static func verify(
        claimData: Data,
        signatureBase64: String,
        bundleVersion: String?,
        bundleBuild: String?,
        publicKeys: [String: String] = BuildClaimPublicKeys.all
    ) throws -> VerifiedBuildClaim {
        guard let signature = Data(base64Encoded: signatureBase64
            .trimmingCharacters(in: .whitespacesAndNewlines))
        else { throw BuildClaimVerificationError.invalidSignatureEncoding }

        let claim = try JSONDecoder().decode(BuildClaim.self, from: claimData)

        guard let publicKeyBase64 = publicKeys[claim.keyId],
              let publicKeyData = Data(base64Encoded: publicKeyBase64)
        else { throw BuildClaimVerificationError.unknownKey }

        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        guard publicKey.isValidSignature(signature, for: claimData)
        else { throw BuildClaimVerificationError.invalidSignature }

        guard bundleVersion == claim.version else { throw BuildClaimVerificationError.versionMismatch }
        guard bundleBuild == claim.build else { throw BuildClaimVerificationError.buildMismatch }

        let fingerprint = SHA256.hash(data: claimData)
            .map { String(format: "%02x", $0) }.joined()
        return VerifiedBuildClaim(claim: claim, fingerprint: fingerprint)
    }

    public static func loadAndVerify(bundle: Bundle = .main) throws -> VerifiedBuildClaim {
        guard let claimURL = bundle.url(forResource: "BuildClaim", withExtension: "json"),
              let signatureURL = bundle.url(forResource: "BuildClaim", withExtension: "sig")
        else { throw BuildClaimVerificationError.missingResource }
        let claimData = try Data(contentsOf: claimURL)
        let signature = try String(contentsOf: signatureURL, encoding: .utf8)
        return try verify(
            claimData: claimData,
            signatureBase64: signature,
            bundleVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            bundleBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }
}
