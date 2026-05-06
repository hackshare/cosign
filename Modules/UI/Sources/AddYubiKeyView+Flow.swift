import Core
import CosignCore
import Persistence
import Signers
import SwiftUI

extension AddYubiKeyView {
    func beginPINEntry() {
        recovery = nil
        pin = ""
        phase = .pin
    }

    func submitPIN() {
        guard hasValidPIN else { return }
        phase = .touch
        Task { await enroll() }
    }

    @MainActor
    func enroll() async {
        recovery = nil
        let pinToVerify = pin.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let result = try await YubiKeyPIVRegistration.enroll(
                pin: pinToVerify,
                preference: transport.connectionPreference(
                    alertMessage: CosignCopy.YubiKey.tapPrompt
                )
            )

            guard !signers.contains(where: { $0.pubkey == result.pubkey }) else {
                recovery = .alreadyAdded
                phase = .recovery
                return
            }

            try persist(pubkey: result.pubkey)
            addedAddress = CosignCore.base58(result.pubkey)
            phase = .ready
        } catch {
            present(error)
        }
    }

    @MainActor
    func performRecovery(_ recovery: YubiKeyRecovery) async {
        switch recovery.action {
        case .reEnterPIN:
            pin = ""
            self.recovery = nil
            phase = .pin
        case .retryConnect:
            self.recovery = nil
            phase = .touch
            await enroll()
        case .useWired:
            transport = .wired
            self.recovery = nil
            phase = .tapOrInsert
        case .startOver:
            resetToStart()
        case .dismiss:
            dismiss()
        }
    }

    private func persist(pubkey: Pubkey) throws {
        let registered = RegisteredSigner(
            label: trimmedLabel,
            type: .yubikey,
            pubkey: pubkey,
            backedUp: true
        )
        context.insert(registered)
        try context.save()
    }

    private func present(_ error: any Error) {
        let failure = YubiKeyOnboardingFailure.classify(error)
        if case let .wrongPIN(retriesRemaining) = failure {
            pinAttemptsRemaining = retriesRemaining
        }
        recovery = YubiKeyRecovery(failure: failure)
        phase = .recovery
    }
}
