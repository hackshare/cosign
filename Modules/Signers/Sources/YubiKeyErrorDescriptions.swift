import Foundation

extension YubiKeySignerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .malformedResponse:
            "The YubiKey returned a malformed response."
        case .malformedTLV:
            "The YubiKey returned malformed TLV data."
        case let .unexpectedTLVTag(expected, actual):
            "The YubiKey returned TLV tag 0x\(Self.hex(actual)) instead of 0x\(Self.hex(expected))."
        case .invalidPINLength:
            "YubiKey PIV PINs must be 6 to 8 characters."
        case let .invalidPIN(retriesRemaining):
            "The YubiKey PIV PIN was rejected. \(retriesRemaining) retries remain."
        case .pinBlocked:
            "The YubiKey PIV PIN is blocked. Reset or unblock PIV with YubiKey Manager before using this signer."
        case .authenticationRequired:
            "The YubiKey requires PIV PIN verification."
        case let .deviceStatus(status):
            "The YubiKey returned status 0x\(Self.hex(status))."
        case let .invalidSignatureLength(length):
            "The YubiKey returned a signature with \(length) bytes."
        case .missingPINProvider:
            "YubiKey signing requires a PIN prompt."
        }
    }

    private static func hex(_ value: UInt8) -> String {
        String(value, radix: 16, uppercase: true)
    }

    private static func hex(_ value: UInt16) -> String {
        String(value, radix: 16, uppercase: true)
    }
}
