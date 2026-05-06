import Core
import CosignCore
import Persistence
import Signers
import SwiftUI
import UIKit

extension AddLedgerView {
    @MainActor
    func startScan() async {
        recovery = nil
        devices = []
        selectedDeviceID = nil
        pairedDevice = nil
        derivedAddress = nil
        phase = .searching

        do {
            let found = try await transport.scan(timeout: 8)
            guard !found.isEmpty else {
                recovery = .noDevices
                phase = .recovery
                return
            }
            devices = found
            selectedDeviceID = found.first?.id
            phase = .found
        } catch {
            present(error)
        }
    }

    @MainActor
    func connectAndVerify(_ device: LedgerBLEDevice) async {
        recovery = nil
        connectingDeviceName = device.name
        phase = .connecting

        do {
            try await transport.connect(to: device)

            let configuration = try await transport.exchange(LedgerSolanaAPDU.appConfigurationCommand())
            _ = try LedgerSolanaAPDU.parseAppConfiguration(configuration.successfulData())

            let lookup = try await transport.exchange(LedgerSolanaAPDU.addressCommand(displayOnDevice: false))
            let pubkey = try LedgerSolanaAPDU.parseAddress(lookup.successfulData())

            guard !signers.contains(where: { $0.pubkey == pubkey }) else {
                recovery = .alreadyAdded
                phase = .recovery
                return
            }

            pairedDevice = device
            derivedAddress = CosignCore.base58(pubkey)
            phase = .verifying

            let confirmation = try await transport.exchange(LedgerSolanaAPDU.addressCommand(displayOnDevice: true))
            let confirmedPubkey = try LedgerSolanaAPDU.parseAddress(confirmation.successfulData())
            guard confirmedPubkey == pubkey else {
                recovery = LedgerRecovery(failure: .addressMismatch, hasSelectedDevice: true)
                phase = .recovery
                return
            }

            try persist(pubkey: pubkey)
            pairedAddress = CosignCore.base58(pubkey)
            phase = .ready
        } catch {
            present(error)
        }
    }

    @MainActor
    func performRecovery(_ recovery: LedgerRecovery) async {
        switch recovery.action {
        case .openSettings:
            openSettings()
        case .rescan:
            await startScan()
        case .reconnect:
            if let device = selectedDevice ?? pairedDevice {
                await connectAndVerify(device)
            } else {
                await startScan()
            }
        case .dismiss:
            dismiss()
        }
    }

    private func persist(pubkey: Pubkey) throws {
        let registered = RegisteredSigner(
            label: trimmedLabel,
            type: .ledger,
            pubkey: pubkey,
            backedUp: true
        )
        context.insert(registered)
        try context.save()
    }

    private func present(_ error: any Error) {
        recovery = LedgerRecovery(
            failure: LedgerOnboardingFailure.classify(error),
            hasSelectedDevice: selectedDevice != nil
        )
        phase = .recovery
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
