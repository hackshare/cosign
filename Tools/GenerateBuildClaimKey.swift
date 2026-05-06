import CryptoKit
import Foundation

let privateKey = Curve25519.Signing.PrivateKey()
print("BUILD_CLAIM_PRIVATE_KEY_B64=\(privateKey.rawRepresentation.base64EncodedString())")
print("BUILD_CLAIM_PUBLIC_KEY_B64=\(privateKey.publicKey.rawRepresentation.base64EncodedString())")
