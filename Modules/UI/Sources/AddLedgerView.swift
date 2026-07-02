import CosignCore
import Persistence
import Signers
import SwiftData
import SwiftUI

struct AddLedgerView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context
    @Query(sort: \RegisteredSigner.createdAt, order: .forward)
    var signers: [RegisteredSigner]

    @State var label = CosignCopy.Ledger.defaultLabel
    @State var transport = CoreBluetoothLedgerTransport()
    @State var devices: [LedgerBLEDevice] = []
    @State var selectedDeviceID: UUID?
    @State var phase: Phase = .checklist
    @State var connectingDeviceName: String?
    @State var derivedAddress: String?
    @State var pairedDevice: LedgerBLEDevice?
    @State var pairedAddress: String?
    @State var recovery: LedgerRecovery?

    enum Phase: Equatable {
        case checklist
        case searching
        case found
        case connecting
        case verifying
        case ready
        case recovery
    }

    init() {}

    var body: some View {
        NavigationStack {
            phaseContent
                .toolbar(.hidden, for: .navigationBar)
                .cosignScreenIdentifier("screen.add-ledger")
                .onDisappear { transport.disconnect() }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .checklist:
            checklistStep
        case .searching, .found:
            searchingStep
        case .connecting:
            connectingStep
        case .verifying:
            verifyStep
        case .ready:
            readyStep
        case .recovery:
            recoveryStep
        }
    }

    var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var selectedDevice: LedgerBLEDevice? {
        devices.first { $0.id == selectedDeviceID }
    }

    var header: some View {
        CosignCompactPageHeader(title: CosignCopy.Ledger.connectChromeTitle) {
            transport.disconnect()
            dismiss()
        }
    }
}
