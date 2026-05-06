import Core
import Foundation
import YubiKit

public enum YubiKeyPIVPublicKeySource: String, Sendable {
    case metadata
    case certificate
}

public struct YubiKeyPIVSlotPublicKey: Equatable, Sendable {
    public let pubkey: Pubkey
    public let slot: YubiKeyPIVSlot
    public let source: YubiKeyPIVPublicKeySource
    public let generatedOnYubiKey: Bool?

    public init(
        pubkey: Pubkey,
        slot: YubiKeyPIVSlot,
        source: YubiKeyPIVPublicKeySource,
        generatedOnYubiKey: Bool?
    ) {
        self.pubkey = pubkey
        self.slot = slot
        self.source = source
        self.generatedOnYubiKey = generatedOnYubiKey
    }
}

public enum YubiKeyPIVRegistration {
    public static func readEd25519PublicKey(
        preference: YubiKeyConnectionPreference,
        slot: YubiKeyPIVSlot = .signature
    ) async throws -> YubiKeyPIVSlotPublicKey {
        switch preference {
        case .wired:
            let connection = try await WiredSmartCardConnection.makeConnection()
            return try await readAndClose(
                connection,
                slot: slot,
                closeSuccess: {
                    await connection.close(error: nil)
                }
            )
        case let .nfc(alertMessage):
            let connection = try await NFCSmartCardConnection(alertMessage: alertMessage)
            return try await readAndClose(
                connection,
                slot: slot,
                closeSuccess: {
                    await connection.close(message: "YubiKey address read.")
                }
            )
        }
    }

    private static func readAndClose(
        _ connection: some SmartCardConnection,
        slot: YubiKeyPIVSlot,
        closeSuccess: () async -> Void
    ) async throws -> YubiKeyPIVSlotPublicKey {
        do {
            let session = try await PIVSession.makeSession(connection: connection)
            let result = try await readEd25519PublicKey(from: session, slot: slot)
            await closeSuccess()
            return result
        } catch {
            await connection.close(error: error)
            throw error
        }
    }

    static func readEd25519PublicKey(
        from session: PIVSession,
        slot: YubiKeyPIVSlot
    ) async throws -> YubiKeyPIVSlotPublicKey {
        let pivSlot = slot.yubiKitSlot

        let metadataError: Error
        do {
            let metadata = try await session.getMetadata(in: pivSlot)
            return try YubiKeyPIVSlotPublicKey(
                pubkey: ed25519Pubkey(from: metadata.publicKey, slot: slot),
                slot: slot,
                source: .metadata,
                generatedOnYubiKey: metadata.generated
            )
        } catch let error as YubiKeyPIVRegistrationError {
            throw error
        } catch {
            metadataError = error
        }

        do {
            let certificate = try await session.getCertificate(in: pivSlot)
            guard let publicKey = certificate.publicKey else {
                throw YubiKeyPIVRegistrationError.noEd25519PublicKey(slot: slot)
            }
            return try YubiKeyPIVSlotPublicKey(
                pubkey: ed25519Pubkey(from: publicKey, slot: slot),
                slot: slot,
                source: .certificate,
                generatedOnYubiKey: nil
            )
        } catch let error as YubiKeyPIVRegistrationError {
            throw error
        } catch {
            throw YubiKeyPIVRegistrationError.noUsablePublicKey(
                slot: slot,
                metadataError: Self.describe(metadataError),
                certificateError: Self.describe(error)
            )
        }
    }

    private static func ed25519Pubkey(from publicKey: PublicKey, slot: YubiKeyPIVSlot) throws -> Pubkey {
        guard case let .ed25519(key) = publicKey else {
            throw YubiKeyPIVRegistrationError.unsupportedPublicKey(slot: slot)
        }
        return key.keyData
    }

    private static func describe(_ error: any Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }

        return String(describing: error)
    }
}

public enum YubiKeyPIVRegistrationError: LocalizedError, Sendable {
    case unsupportedPublicKey(slot: YubiKeyPIVSlot)
    case noEd25519PublicKey(slot: YubiKeyPIVSlot)
    case noUsablePublicKey(slot: YubiKeyPIVSlot, metadataError: String, certificateError: String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedPublicKey(slot):
            "The \(slot.displayName) contains a key, but it is not an Ed25519 signing key."
        case let .noEd25519PublicKey(slot):
            "No Ed25519 public key was found in the \(slot.displayName)."
        case let .noUsablePublicKey(slot, metadataError, certificateError):
            "No usable Ed25519 public key was found in the \(slot.displayName). Metadata read failed: \(metadataError). Certificate read failed: \(certificateError)."
        }
    }
}

public extension YubiKeyPIVSlot {
    var displayName: String {
        switch self {
        case .authentication:
            "PIV authentication slot (9A)"
        case .signature:
            "PIV signature slot (9C)"
        case .keyManagement:
            "PIV key management slot (9D)"
        case .cardAuthentication:
            "PIV card authentication slot (9E)"
        }
    }
}

extension YubiKeyPIVSlot {
    var yubiKitSlot: PIV.Slot {
        switch self {
        case .authentication:
            .authentication
        case .signature:
            .signature
        case .keyManagement:
            .keyManagement
        case .cardAuthentication:
            .cardAuth
        }
    }
}
