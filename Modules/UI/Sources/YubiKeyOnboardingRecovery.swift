import Signers
import SwiftUI

enum YubiKeyOnboardingFailure {
    case wrongPIN(retriesRemaining: Int)
    case pinLocked
    case notProvisioned
    case noKey
    case nfcUnavailable
    case touchTimedOut
    case lostConnection

    static func classify(_ error: any Error) -> YubiKeyOnboardingFailure {
        if let enrollment = error as? YubiKeyEnrollmentError {
            switch enrollment {
            case let .wrongPIN(retriesRemaining): return .wrongPIN(retriesRemaining: retriesRemaining)
            case .pinLocked: return .pinLocked
            }
        }

        if let signer = error as? YubiKeySignerError {
            switch signer {
            case let .invalidPIN(retriesRemaining): return .wrongPIN(retriesRemaining: retriesRemaining)
            case .pinBlocked: return .pinLocked
            default: return .lostConnection
            }
        }

        if error is YubiKeyPIVRegistrationError {
            return .notProvisioned
        }

        return classifyByDescription(error)
    }

    private static func classifyByDescription(_ error: any Error) -> YubiKeyOnboardingFailure {
        let text = String(describing: error).lowercased()
        if text.contains("nfc"), text.contains("not") || text.contains("unavailable") || text.contains("support") {
            return .nfcUnavailable
        }
        if text.contains("timeout") || text.contains("timed out") || text.contains("expired") {
            return .touchTimedOut
        }
        if text.contains("no tag") || text.contains("not found") || text.contains("no key") {
            return .noKey
        }
        return .lostConnection
    }
}

enum YubiKeyRecoveryAction {
    case reEnterPIN
    case retryConnect
    case useWired
    case startOver
    case dismiss
}

struct YubiKeyRecovery: Equatable {
    enum Kind {
        case wrongPIN
        case pinLocked
        case notProvisioned
        case noKey
        case nfcUnavailable
        case touchTimedOut
        case lostConnection
        case addressMismatch
        case alreadyAdded
    }

    let kind: Kind
    let action: YubiKeyRecoveryAction
    let retriesRemaining: Int?

    static let alreadyAdded = YubiKeyRecovery(kind: .alreadyAdded, action: .dismiss)

    init(kind: Kind, action: YubiKeyRecoveryAction, retriesRemaining: Int? = nil) {
        self.kind = kind
        self.action = action
        self.retriesRemaining = retriesRemaining
    }

    init(failure: YubiKeyOnboardingFailure) {
        switch failure {
        case let .wrongPIN(retriesRemaining):
            self.init(kind: .wrongPIN, action: .reEnterPIN, retriesRemaining: retriesRemaining)
        case .pinLocked:
            self.init(kind: .pinLocked, action: .startOver)
        case .notProvisioned:
            self.init(kind: .notProvisioned, action: .startOver)
        case .noKey:
            self.init(kind: .noKey, action: .retryConnect)
        case .nfcUnavailable:
            self.init(kind: .nfcUnavailable, action: .useWired)
        case .touchTimedOut:
            self.init(kind: .touchTimedOut, action: .retryConnect)
        case .lostConnection:
            self.init(kind: .lostConnection, action: .retryConnect)
        }
    }
}

extension YubiKeyRecovery {
    typealias Copy = CosignCopy.YubiKey.Recovery

    var title: String {
        switch kind {
        case .wrongPIN: Copy.wrongPINTitle
        case .pinLocked: Copy.pinLockedTitle
        case .notProvisioned: Copy.notProvisionedTitle
        case .noKey: Copy.noKeyTitle
        case .nfcUnavailable: Copy.nfcUnavailableTitle
        case .touchTimedOut: Copy.touchTimedOutTitle
        case .lostConnection: Copy.lostConnectionTitle
        case .addressMismatch: Copy.mismatchTitle
        case .alreadyAdded: Copy.alreadyAddedTitle
        }
    }

    var message: String {
        switch kind {
        case .wrongPIN: Copy.wrongPINMessage(retriesRemaining: retriesRemaining ?? 0)
        case .pinLocked: Copy.pinLockedMessage
        case .notProvisioned: Copy.notProvisionedMessage
        case .noKey: Copy.noKeyMessage
        case .nfcUnavailable: Copy.nfcUnavailableMessage
        case .touchTimedOut: Copy.touchTimedOutMessage
        case .lostConnection: Copy.lostConnectionMessage
        case .addressMismatch: Copy.mismatchMessage
        case .alreadyAdded: Copy.alreadyAddedMessage
        }
    }

    var actionTitle: String {
        switch kind {
        case .wrongPIN: Copy.wrongPINAction
        case .pinLocked: Copy.pinLockedAction
        case .notProvisioned: Copy.notProvisionedAction
        case .noKey: Copy.noKeyAction
        case .nfcUnavailable: Copy.nfcUnavailableAction
        case .touchTimedOut: Copy.touchTimedOutAction
        case .lostConnection: Copy.lostConnectionAction
        case .addressMismatch: Copy.mismatchAction
        case .alreadyAdded: CosignCopy.YubiKey.doneButtonTitle
        }
    }

    var isDanger: Bool {
        switch kind {
        case .wrongPIN, .pinLocked, .notProvisioned, .addressMismatch: true
        default: false
        }
    }

    var accent: Color {
        isDanger ? CosignTheme.riskRed : CosignTheme.riskAmber
    }

    var glyph: CosignGlyph {
        switch kind {
        case .wrongPIN, .pinLocked: .lock
        case .notProvisioned, .addressMismatch: .warning
        case .noKey: .search
        case .nfcUnavailable, .lostConnection: .wave
        case .touchTimedOut: .clock
        case .alreadyAdded: .check
        }
    }
}

struct YubiKeyRecoveryCard: View {
    let recovery: YubiKeyRecovery
    let action: () -> Void

    var body: some View {
        CosignCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    CosignGlyphView(glyph: recovery.glyph, size: 18, color: recovery.accent)
                        .frame(width: 38, height: 38)
                        .background(recovery.accent.opacity(0.12), in: .rect(cornerRadius: CosignTheme.Radius.medium))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(recovery.title)
                            .font(CosignTheme.FontStyle.titleM)
                            .foregroundStyle(CosignTheme.ink)
                        Text(recovery.message)
                            .font(CosignTheme.FontStyle.caption)
                            .foregroundStyle(CosignTheme.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: action) {
                    Text(recovery.actionTitle)
                        .font(CosignTheme.FontStyle.body)
                        .foregroundStyle(recovery.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: CosignTheme.Radius.control)
                                .stroke(CosignTheme.line, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("yubikey-recovery-action")
            }
        }
    }
}
