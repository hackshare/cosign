import CryptoKit
import Darwin
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

guard CommandLine.arguments.count == 4 else {
    fail("Usage: VerifyBuildClaim <claim.json> <claim.sig> <publicKeyB64>")
}
let claimData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let sigB64 = try String(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]), encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard let signature = Data(base64Encoded: sigB64) else { fail("bad signature encoding") }
guard let keyData = Data(base64Encoded: CommandLine.arguments[3]) else { fail("bad public key") }
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
guard publicKey.isValidSignature(signature, for: claimData) else { fail("INVALID signature") }
let fp = SHA256.hash(data: claimData).map { String(format: "%02x", $0) }.joined()
print("OK fingerprint=\(fp)")
