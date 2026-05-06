import Foundation

extension LedgerBluetoothUnavailableReason {
    var message: String {
        switch self {
        case .off:
            "Bluetooth is turned off."
        case .unauthorized:
            "Bluetooth permission is not available."
        case .unsupported:
            "Bluetooth is not supported on this device."
        case .resetting:
            "Bluetooth is resetting."
        case .notReady:
            "Bluetooth is not ready yet."
        case .unavailable:
            "Bluetooth is unavailable."
        }
    }
}

extension LedgerBLETransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .bluetoothUnavailable(reason):
            reason.message
        case .scanInProgress:
            "A Ledger scan is already running."
        case .connectInProgress:
            "A Ledger connection is already in progress."
        case .exchangeInProgress:
            "A Ledger request is already in progress."
        case .unknownDevice:
            "Select a scanned Ledger device."
        case .notConnected:
            "The Ledger is not connected."
        case .disconnected:
            "The Ledger disconnected."
        case .missingService:
            "The Ledger Bluetooth service was not found."
        case .missingCharacteristic:
            "The Ledger Bluetooth channel was not found."
        case let .connectionFailed(message):
            message
        }
    }
}

extension LedgerSignerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .malformedResponse:
            "The Ledger returned a malformed response."
        case .blindSigningRequired:
            "Blind signing is required on the Ledger device."
        case let .deviceStatus(status):
            "The Ledger returned status 0x\(String(status, radix: 16, uppercase: true))."
        case .addressMismatch:
            "The connected Ledger address does not match the saved signer."
        case let .invalidAddressLength(length):
            "The Ledger returned an address with \(length) bytes."
        case let .invalidSignatureLength(length):
            "The Ledger returned a signature with \(length) bytes."
        }
    }
}
