import Core
import CosignCore
import Foundation
import Persistence
import Signers

func makeProposalActionSigner(from signer: RegisteredSigner) -> ProposalActionSigner? {
    let storage: ProposalActionSignerStorage
    switch signer.type {
    case .hotWallet:
        guard let account = signer.keychainItemRef else {
            return nil
        }
        storage = .hotWallet(keychainAccount: account)
    case .ledger:
        storage = .ledger
    case .yubikey:
        storage = .yubikey
    }

    return ProposalActionSigner(
        id: signer.id,
        label: signer.label,
        type: signer.type,
        pubkey: signer.pubkey,
        address: CosignCore.base58(signer.pubkey),
        storage: storage,
        backedUp: signer.backedUp
    )
}

@MainActor
func withResolvedProposalSigner<T>(
    _ signer: ProposalActionSigner,
    yubiKeyOptions: YubiKeySigningOptions? = nil,
    deviceStatus: @escaping @MainActor (String?) -> Void,
    operation: (any Signer) async throws -> T
) async throws -> T {
    deviceStatus(nil)

    switch signer.storage {
    case let .hotWallet(keychainAccount):
        guard signer.backedUp else {
            throw ProposalSignerResolutionError.notBackedUp
        }
        return try await operation(HotWalletSigner(
            label: signer.label,
            pubkey: signer.pubkey,
            keychainAccount: keychainAccount
        ))
    case .ledger:
        return try await withResolvedLedgerSigner(
            signer,
            deviceStatus: deviceStatus,
            operation: operation
        )
    case .yubikey:
        return try await withResolvedYubiKeySigner(
            signer,
            options: yubiKeyOptions,
            deviceStatus: deviceStatus,
            operation: operation
        )
    }
}

@MainActor
private func withResolvedLedgerSigner<T>(
    _ signer: ProposalActionSigner,
    deviceStatus: @escaping @MainActor (String?) -> Void,
    operation: (any Signer) async throws -> T
) async throws -> T {
    let transport = CoreBluetoothLedgerTransport()
    defer {
        transport.disconnect()
        deviceStatus(nil)
    }

    deviceStatus(CosignCopy.ProposalSigning.scanningLedgerStatus)
    let devices = try await transport.scan(timeout: 8)
    guard let device = devices.first else {
        throw ProposalSignerResolutionError.noLedgerDevices
    }

    deviceStatus(CosignCopy.ProposalSigning.connectingLedgerStatus(deviceName: device.name))
    try await transport.connect(to: device)

    deviceStatus(CosignCopy.ProposalSigning.verifyingLedgerAddressStatus)
    try await LedgerSignerPreflight.verifySolanaAppAndAddress(
        expectedPubkey: signer.pubkey,
        transport: transport
    )

    deviceStatus(CosignCopy.ProposalSigning.confirmLedgerStatus)
    return try await operation(LedgerSigner(
        label: signer.label,
        pubkey: signer.pubkey,
        transport: transport
    ))
}

@MainActor
private func withResolvedYubiKeySigner<T>(
    _ signer: ProposalActionSigner,
    options: YubiKeySigningOptions?,
    deviceStatus: @escaping @MainActor (String?) -> Void,
    operation: (any Signer) async throws -> T
) async throws -> T {
    guard let options else {
        throw ProposalSignerResolutionError.missingYubiKeyOptions
    }

    let pin = options.trimmedPIN
    guard options.hasValidPINLength else {
        throw YubiKeySignerError.invalidPINLength
    }

    deviceStatus(CosignCopy.YubiKeySigning.connectingStatus(transport: options.transport.statusLabel))
    let transport = try await YubiKitYubiKeyAPDUTransport.open(
        options.transport.connectionPreference(
            alertMessage: CosignCopy.YubiKeySigning.tapPrompt
        )
    )

    do {
        deviceStatus(CosignCopy.YubiKeySigning.signStatus)
        let result = try await operation(YubiKeySigner(
            label: signer.label,
            pubkey: signer.pubkey,
            transport: transport,
            pinProvider: { pin }
        ))
        await transport.close()
        deviceStatus(nil)
        return result
    } catch {
        await transport.close(error: error)
        deviceStatus(nil)
        throw error
    }
}

enum ProposalSignerResolutionError: LocalizedError {
    case noLedgerDevices
    case missingYubiKeyOptions
    case notBackedUp

    var errorDescription: String? {
        switch self {
        case .noLedgerDevices:
            CosignCopy.ProposalSigning.noLedgerDevicesError
        case .missingYubiKeyOptions:
            CosignCopy.ProposalSigning.missingYubiKeyOptionsError
        case .notBackedUp:
            CosignCopy.ProposalSigning.notBackedUpError
        }
    }
}
