import Foundation
import Signers

struct YubiKeySetupNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

func yubiKeySetupNotice(for error: any Error) -> YubiKeySetupNotice {
    if let registrationError = error as? YubiKeyPIVRegistrationError {
        return yubiKeyRegistrationNotice(for: registrationError)
    }

    if let signerError = error as? YubiKeySignerError {
        return YubiKeySetupNotice(
            title: CosignCopy.YubiKeySigning.checkFailedTitle,
            message: signerError.errorDescription ?? String(describing: signerError)
        )
    }

    if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
        return YubiKeySetupNotice(
            title: CosignCopy.YubiKeySigning.checkFailedTitle,
            message: description
        )
    }

    return YubiKeySetupNotice(
        title: CosignCopy.YubiKeySigning.checkFailedTitle,
        message: String(describing: error)
    )
}

private func yubiKeyRegistrationNotice(for error: YubiKeyPIVRegistrationError) -> YubiKeySetupNotice {
    switch error {
    case let .unsupportedPublicKey(slot):
        YubiKeySetupNotice(
            title: CosignCopy.YubiKeySigning.unsupportedKeyTitle,
            message: CosignCopy.YubiKeySigning.unsupportedKeyMessage(slotName: slot.displayName)
        )
    case let .noEd25519PublicKey(slot):
        YubiKeySetupNotice(
            title: CosignCopy.YubiKeySigning.keyNotFoundTitle,
            message: CosignCopy.YubiKeySigning.keyNotFoundMessage(slotName: slot.displayName)
        )
    case let .noUsablePublicKey(slot, metadataError, certificateError):
        YubiKeySetupNotice(
            title: CosignCopy.YubiKeySigning.keyNotReadableTitle,
            message: CosignCopy.YubiKeySigning.keyNotReadableMessage(
                slotName: slot.displayName,
                metadataError: String(describing: metadataError),
                certificateError: String(describing: certificateError)
            )
        )
    }
}
