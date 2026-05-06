import CryptoKit
import Darwin
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

guard CommandLine.arguments.count == 3 else {
    fail("Usage: SignBuildClaim <input.json> <output.sig>")
}
guard
    let encodedKey = ProcessInfo.processInfo.environment["BUILD_CLAIM_PRIVATE_KEY_B64"],
    let keyData = Data(base64Encoded: encodedKey)
else { fail("Missing or invalid BUILD_CLAIM_PRIVATE_KEY_B64") }

let claimData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
let signature = try privateKey.signature(for: claimData)
try (signature.base64EncodedString() + "\n").write(
    to: URL(fileURLWithPath: CommandLine.arguments[2]), atomically: true, encoding: .utf8
)
