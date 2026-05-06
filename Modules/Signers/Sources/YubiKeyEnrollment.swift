import Core
import Foundation
import YubiKit

/// Result of a guided YubiKey enrollment: the Ed25519 public key read from the
/// PIV signature slot plus where it came from, after the PIN was verified and a
/// presence (touch) check was satisfied in the same session.
public struct YubiKeyEnrollment: Equatable, Sendable {
    public let pubkey: Pubkey
    public let source: YubiKeyPIVPublicKeySource
    public let generatedOnYubiKey: Bool?

    public init(pubkey: Pubkey, source: YubiKeyPIVPublicKeySource, generatedOnYubiKey: Bool?) {
        self.pubkey = pubkey
        self.source = source
        self.generatedOnYubiKey = generatedOnYubiKey
    }
}

public enum YubiKeyEnrollmentError: LocalizedError, Sendable, Equatable {
    case wrongPIN(retriesRemaining: Int)
    case pinLocked

    public var errorDescription: String? {
        switch self {
        case let .wrongPIN(retriesRemaining):
            "Incorrect PIN. \(retriesRemaining) attempt\(retriesRemaining == 1 ? "" : "s") remaining before the key locks."
        case .pinLocked:
            "This YubiKey is locked. Reset the PIN with your PUK using YubiKey Manager."
        }
    }
}

public extension YubiKeyPIVRegistration {
    /// Drives the full onboarding handshake over a single connection:
    /// open (tap/insert) → verify PIN → read the Ed25519 public key → sign a
    /// random challenge to require an on-device touch and prove key control.
    static func enroll(
        pin: String,
        preference: YubiKeyConnectionPreference,
        slot: YubiKeyPIVSlot = .signature
    ) async throws -> YubiKeyEnrollment {
        switch preference {
        case .wired:
            let connection = try await WiredSmartCardConnection.makeConnection()
            return try await enrollAndClose(connection, pin: pin, slot: slot) {
                await connection.close(error: nil)
            }
        case let .nfc(alertMessage):
            let connection = try await NFCSmartCardConnection(alertMessage: alertMessage)
            return try await enrollAndClose(connection, pin: pin, slot: slot) {
                await connection.close(message: "YubiKey connected.")
            }
        }
    }

    private static func enrollAndClose(
        _ connection: some SmartCardConnection,
        pin: String,
        slot: YubiKeyPIVSlot,
        closeSuccess: () async -> Void
    ) async throws -> YubiKeyEnrollment {
        do {
            let result = try await enroll(over: connection, pin: pin, slot: slot)
            await closeSuccess()
            return result
        } catch {
            await connection.close(error: error)
            throw error
        }
    }

    private static func enroll(
        over connection: some SmartCardConnection,
        pin: String,
        slot: YubiKeyPIVSlot
    ) async throws -> YubiKeyEnrollment {
        let session = try await PIVSession.makeSession(connection: connection)

        switch try await session.verifyPin(pin) {
        case .success:
            break
        case let .fail(retriesLeft):
            throw YubiKeyEnrollmentError.wrongPIN(retriesRemaining: retriesLeft)
        case .pinLocked:
            throw YubiKeyEnrollmentError.pinLocked
        }

        let slotKey = try await readEd25519PublicKey(from: session, slot: slot)

        // A private-key operation forces the gold-disc touch (when the key has a
        // touch policy) and proves the holder controls the slot, not just the PIN.
        _ = try await session.sign(presenceChallenge(), in: slot.yubiKitSlot, keyType: .ed25519)

        return YubiKeyEnrollment(
            pubkey: slotKey.pubkey,
            source: slotKey.source,
            generatedOnYubiKey: slotKey.generatedOnYubiKey
        )
    }

    private static func presenceChallenge() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0 ..< 32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}
