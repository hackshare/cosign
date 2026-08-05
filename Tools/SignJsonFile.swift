import CryptoKit
import Darwin
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

/// Reads a line from the terminal with echo disabled, so a pasted secret never
/// lands in the scrollback. Echo is turned off (flushing any type-ahead) BEFORE
/// the prompt is printed, so nothing typed can be echoed. The terminal state is
/// restored before returning, even on the failure path, so a bad paste can't
/// leave the shell with echo off.
func readSecret(prompt: String) -> String {
    var original = termios()
    let managed = tcgetattr(STDIN_FILENO, &original) == 0
    if managed {
        var hidden = original
        hidden.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &hidden)
    }
    FileHandle.standardError.write(Data(prompt.utf8))
    let entered = readLine(strippingNewline: true)
    if managed {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
    }
    FileHandle.standardError.write(Data("\n".utf8)) // the Return keypress wasn't echoed
    guard let entered else { fail("No key entered") }
    return entered
}

/// The signing key comes from `SIGNING_PRIVATE_KEY_B64` when set (the CI path),
/// otherwise from a hidden interactive prompt, so a human signing locally never
/// exposes the key in their environment or shell history.
func loadKeyData() -> Data {
    if let encoded = ProcessInfo.processInfo.environment["SIGNING_PRIVATE_KEY_B64"], !encoded.isEmpty {
        guard let data = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            fail("SIGNING_PRIVATE_KEY_B64 is not valid base64")
        }
        return data
    }
    guard isatty(STDIN_FILENO) == 1 else {
        fail("Set SIGNING_PRIVATE_KEY_B64, or run in an interactive terminal to be prompted for the key.")
    }
    let entered = readSecret(prompt: "Signing private key (base64, input hidden): ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = Data(base64Encoded: entered) else {
        fail("Entered value is not valid base64")
    }
    return data
}

guard CommandLine.arguments.count == 3 else {
    fail("Usage: SignJsonFile <input.json> <output.sig>")
}

let keyData = loadKeyData()
guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else {
    fail("Not a valid Curve25519 private key (expected 32 raw bytes, got \(keyData.count))")
}

let payload = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let signature = try privateKey.signature(for: payload)
try (signature.base64EncodedString() + "\n").write(
    to: URL(fileURLWithPath: CommandLine.arguments[2]), atomically: true, encoding: .utf8
)
