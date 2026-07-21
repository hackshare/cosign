import CryptoKit
import Darwin
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

guard CommandLine.arguments.count == 3 else {
    fail("Usage: SignDecodeRegistry <bundle.json> <output.sig>")
}

guard
    let encodedKey = ProcessInfo.processInfo.environment["SIGNING_PRIVATE_KEY_B64"],
    let keyData = Data(base64Encoded: encodedKey)
else { fail("Missing or invalid SIGNING_PRIVATE_KEY_B64") }

let bundle = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
let signature = try privateKey.signature(for: bundle)
try (signature.base64EncodedString() + "\n").write(
    to: URL(fileURLWithPath: CommandLine.arguments[2]), atomically: true, encoding: .utf8
)
