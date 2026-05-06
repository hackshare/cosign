import Signers
import SwiftUI

enum LedgerRecoveryAction {
    case openSettings
    case rescan
    case reconnect
    case dismiss
}

struct LedgerRecovery: Equatable {
    enum Kind {
        case bluetoothOff
        case permissionDenied
        case deviceLocked
        case solanaAppNotOpen
        case lostConnection
        case timedOut
        case noDevices
        case addressMismatch
        case alreadyAdded
    }

    let kind: Kind
    let action: LedgerRecoveryAction

    static let noDevices = LedgerRecovery(kind: .noDevices, action: .rescan)
    static let alreadyAdded = LedgerRecovery(kind: .alreadyAdded, action: .dismiss)

    init(kind: Kind, action: LedgerRecoveryAction) {
        self.kind = kind
        self.action = action
    }

    init(failure: LedgerOnboardingFailure, hasSelectedDevice: Bool) {
        let reconnectOrRescan: LedgerRecoveryAction = hasSelectedDevice ? .reconnect : .rescan
        switch failure {
        case .bluetoothOff, .bluetoothUnsupported:
            self.init(kind: .bluetoothOff, action: .openSettings)
        case .bluetoothPermissionDenied:
            self.init(kind: .permissionDenied, action: .openSettings)
        case .deviceLocked:
            self.init(kind: .deviceLocked, action: .rescan)
        case .solanaAppNotOpen:
            self.init(kind: .solanaAppNotOpen, action: reconnectOrRescan)
        case .lostConnection:
            self.init(kind: .lostConnection, action: reconnectOrRescan)
        case .timedOut, .userRejected, .other:
            self.init(kind: .timedOut, action: reconnectOrRescan)
        case .addressMismatch:
            self.init(kind: .addressMismatch, action: .rescan)
        }
    }
}

extension LedgerRecovery {
    typealias Copy = CosignCopy.Ledger.Recovery

    var title: String {
        switch kind {
        case .bluetoothOff: Copy.bluetoothOffTitle
        case .permissionDenied: Copy.permissionDeniedTitle
        case .deviceLocked: Copy.deviceLockedTitle
        case .solanaAppNotOpen: Copy.solanaAppTitle
        case .lostConnection: Copy.lostConnectionTitle
        case .timedOut: Copy.timedOutTitle
        case .noDevices: Copy.noDevicesTitle
        case .addressMismatch: Copy.mismatchTitle
        case .alreadyAdded: Copy.alreadyAddedTitle
        }
    }

    var message: String {
        switch kind {
        case .bluetoothOff: Copy.bluetoothOffMessage
        case .permissionDenied: Copy.permissionDeniedMessage
        case .deviceLocked: Copy.deviceLockedMessage
        case .solanaAppNotOpen: Copy.solanaAppMessage
        case .lostConnection: Copy.lostConnectionMessage
        case .timedOut: Copy.timedOutMessage
        case .noDevices: Copy.noDevicesMessage
        case .addressMismatch: Copy.mismatchMessage
        case .alreadyAdded: Copy.alreadyAddedMessage
        }
    }

    var actionTitle: String {
        switch kind {
        case .bluetoothOff: Copy.bluetoothOffAction
        case .permissionDenied: Copy.permissionDeniedAction
        case .deviceLocked: Copy.deviceLockedAction
        case .solanaAppNotOpen: Copy.solanaAppAction
        case .lostConnection: Copy.lostConnectionAction
        case .timedOut: Copy.timedOutAction
        case .noDevices: Copy.noDevicesAction
        case .addressMismatch: Copy.mismatchAction
        case .alreadyAdded: CosignCopy.Ledger.doneButtonTitle
        }
    }

    var isDanger: Bool {
        switch kind {
        case .permissionDenied, .addressMismatch: true
        default: false
        }
    }

    var accent: Color {
        isDanger ? CosignTheme.riskRed : CosignTheme.riskAmber
    }

    var glyph: CosignGlyph {
        switch kind {
        case .bluetoothOff, .lostConnection: .wave
        case .permissionDenied: .xmark
        case .deviceLocked: .lock
        case .solanaAppNotOpen, .addressMismatch: .warning
        case .timedOut: .clock
        case .noDevices: .search
        case .alreadyAdded: .check
        }
    }
}

struct LedgerRecoveryCard: View {
    let recovery: LedgerRecovery
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
                .accessibilityIdentifier("ledger-recovery-action")
            }
        }
    }
}
