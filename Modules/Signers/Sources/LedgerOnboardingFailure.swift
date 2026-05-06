import Foundation

/// A coarse, UI-facing classification of why a Ledger onboarding attempt failed.
/// The concrete transport/APDU error types are internal to this module, so this
/// enum is the bridge the UI uses to pick a recovery path.
public enum LedgerOnboardingFailure: Equatable, Sendable {
    case bluetoothOff
    case bluetoothPermissionDenied
    case bluetoothUnsupported
    case deviceLocked
    case solanaAppNotOpen
    case userRejected
    case lostConnection
    case timedOut
    case addressMismatch
    case other(String)

    public static func classify(_ error: any Error) -> LedgerOnboardingFailure {
        if let transportError = error as? LedgerBLETransportError {
            return classify(transportError)
        }
        if let signerError = error as? LedgerSignerError {
            return classify(signerError)
        }
        return .other((error as? LocalizedError)?.errorDescription ?? String(describing: error))
    }

    private static func classify(_ error: LedgerBLETransportError) -> LedgerOnboardingFailure {
        switch error {
        case let .bluetoothUnavailable(reason):
            switch reason {
            case .unauthorized:
                .bluetoothPermissionDenied
            case .unsupported:
                .bluetoothUnsupported
            case .off, .resetting, .notReady, .unavailable:
                .bluetoothOff
            }
        case let .connectionFailed(message):
            message.localizedCaseInsensitiveContains("timed out") ? .timedOut : .lostConnection
        case .disconnected, .notConnected, .missingService, .missingCharacteristic, .unknownDevice:
            .lostConnection
        case .scanInProgress, .connectInProgress, .exchangeInProgress:
            .timedOut
        }
    }

    private static func classify(_ error: LedgerSignerError) -> LedgerOnboardingFailure {
        switch error {
        case .addressMismatch:
            .addressMismatch
        case let .deviceStatus(status):
            classify(status: status)
        case .blindSigningRequired, .malformedResponse, .invalidAddressLength, .invalidSignatureLength:
            .other(error.errorDescription ?? String(describing: error))
        }
    }

    private static func classify(status: UInt16) -> LedgerOnboardingFailure {
        switch status {
        case 0x5515, 0x6804:
            .deviceLocked
        case 0x6985, 0x5501:
            .userRejected
        case 0x6E00, 0x6D00, 0x6807, 0x6511, 0x6A82, 0x6F00:
            .solanaAppNotOpen
        default:
            .other("The Ledger returned status 0x\(String(status, radix: 16, uppercase: true)).")
        }
    }
}
