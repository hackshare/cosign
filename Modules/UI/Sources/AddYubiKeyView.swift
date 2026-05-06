import Core
import CosignCore
import Persistence
import Signers
import SwiftData
import SwiftUI

struct AddYubiKeyView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context
    @Query(sort: \RegisteredSigner.createdAt, order: .forward)
    var signers: [RegisteredSigner]

    @State var label = CosignCopy.YubiKey.defaultLabel
    @State var transport = YubiKeyTransportChoice.nfc
    @State var pin = ""
    @State var phase: Phase = .tapOrInsert
    @State var pinAttemptsRemaining = Self.defaultPINAttempts
    @State var addedAddress: String?
    @State var recovery: YubiKeyRecovery?

    static let defaultPINAttempts = 3

    enum Phase: Equatable {
        case tapOrInsert
        case pin
        case touch
        case ready
        case recovery
    }

    init() {}

    var body: some View {
        NavigationStack {
            phaseContent
                .toolbar(.hidden, for: .navigationBar)
                .cosignScreenIdentifier("screen.add-yubikey")
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .tapOrInsert:
            tapOrInsertStep
        case .pin:
            pinStep
        case .touch:
            touchStep
        case .ready:
            readyStep
        case .recovery:
            recoveryStep
        }
    }

    var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasValidPIN: Bool {
        (6 ... 8).contains(pin.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count)
    }

    func header(title: String) -> some View {
        CosignCompactPageHeader(title: title) {
            dismiss()
        }
    }

    func resetToStart() {
        pin = ""
        addedAddress = nil
        recovery = nil
        pinAttemptsRemaining = Self.defaultPINAttempts
        phase = .tapOrInsert
    }
}
