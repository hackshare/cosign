import Core
import CosignCore
import Foundation
import Persistence
import Signers
import SwiftUI

extension SignerDetailView {
    var yubiKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.SignerDiagnostics.yubiKeySectionTitle)
            CosignCard {
                YubiKeyTransportSelector(selection: $yubiKeyTransport, isDisabled: isTesting)

                Text(CosignCopy.SignerDiagnostics.yubiKeyMessage)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkDim)
                    .padding(.top, 8)
            }
        }
    }

    func diagnosticSection(_ signer: RegisteredSigner) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.SignerDiagnostics.diagnosticsSectionTitle)
            CosignCard {
                Button {
                    Task {
                        await testSigner(signer)
                    }
                } label: {
                    HStack {
                        Text(diagnosticButtonTitle(for: signer.type))
                        Spacer()
                        if isTesting {
                            ProgressView()
                        }
                    }
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.ink)
                }
                .buttonStyle(.plain)
                .disabled(isTesting)

                if let diagnosticStatusMessage {
                    HStack(spacing: 8) {
                        CosignGlyphView(glyph: .clock, size: 14, color: CosignTheme.inkFaint)
                        Text(diagnosticStatusMessage)
                            .font(CosignTheme.FontStyle.caption)
                            .foregroundStyle(CosignTheme.inkDim)
                    }
                    .padding(.top, 8)
                }

                if let diagnosticResult {
                    HStack(spacing: 8) {
                        CosignGlyphView(
                            glyph: diagnosticResult.isSuccess ? .check : .xmark,
                            size: 16,
                            color: diagnosticResult.isSuccess ? CosignTheme.mintDeep : CosignTheme.riskRed
                        )
                        Text(diagnosticResult.title)
                            .font(CosignTheme.FontStyle.body)
                            .foregroundStyle(diagnosticResult.isSuccess ? CosignTheme.mintDeep : CosignTheme.riskRed)
                    }
                    .padding(.top, 8)

                    Text(diagnosticResult.message)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                }
            }
        }
    }

    @MainActor
    func testSigner(_ signer: RegisteredSigner) async {
        guard !isTesting else { return }

        let profile = SignerDiagnosticProfile(
            label: signer.label,
            type: signer.type,
            pubkey: signer.pubkey,
            address: CosignCore.base58(signer.pubkey),
            keychainAccount: signer.keychainItemRef
        )

        isTesting = true
        diagnosticResult = nil
        diagnosticStatusMessage = nil
        defer {
            isTesting = false
            diagnosticStatusMessage = nil
        }

        do {
            diagnosticResult = try await runDiagnostic(profile)
        } catch {
            diagnosticResult = SignerDiagnosticResult(
                title: CosignCopy.SignerDiagnostics.testFailedTitle,
                message: diagnosticMessage(for: error),
                isSuccess: false
            )
        }
    }

    @MainActor
    func runDiagnostic(_ profile: SignerDiagnosticProfile) async throws -> SignerDiagnosticResult {
        switch profile.type {
        case .hotWallet:
            try await testHotWallet(profile)
        case .ledger:
            try await testLedger(profile)
        case .yubikey:
            try await testYubiKey(profile)
        }
    }

    @MainActor
    func testHotWallet(_ profile: SignerDiagnosticProfile) async throws -> SignerDiagnosticResult {
        guard let keychainAccount = profile.keychainAccount else {
            throw SignerDiagnosticError.missingHotWalletKeychainReference
        }

        diagnosticStatusMessage = CosignCopy.SignerDiagnostics.checkingKeychainStatus
        let signer = HotWalletSigner(
            label: profile.label,
            pubkey: profile.pubkey,
            keychainAccount: keychainAccount
        )
        let message = Data(CosignCopy.SignerDiagnostics.diagnosticPayload.utf8)
        let signature = try await signer.sign(message: message)
        guard CosignCore.verifyBytes(publicKey: profile.pubkey, message: message, signature: signature) else {
            throw SignerDiagnosticError.invalidHotWalletSignature
        }

        return SignerDiagnosticResult(
            title: CosignCopy.SignerDiagnostics.hotWalletReadyTitle,
            message: CosignCopy.SignerDiagnostics.hotWalletReadyMessage,
            isSuccess: true
        )
    }

    @MainActor
    func testLedger(_ profile: SignerDiagnosticProfile) async throws -> SignerDiagnosticResult {
        let transport = CoreBluetoothLedgerTransport()
        defer {
            transport.disconnect()
        }

        diagnosticStatusMessage = CosignCopy.Ledger.scanningStatus()
        let devices = try await transport.scan(timeout: 8)
        guard let device = devices.first else {
            throw SignerDiagnosticError.noLedgerDevices
        }

        diagnosticStatusMessage = CosignCopy.Ledger.connectingStatus(deviceName: device.name)
        try await transport.connect(to: device)

        diagnosticStatusMessage = CosignCopy.SignerDiagnostics.verifyingAddressStatus
        let configuration = try await LedgerSignerPreflight.verifySolanaAppAndAddress(
            expectedPubkey: profile.pubkey,
            transport: transport
        )
        let blindSigning = configuration.blindSigningEnabled
            ? CosignCopy.SignerDiagnostics.blindSigningEnabled
            : CosignCopy.SignerDiagnostics.blindSigningDisabled

        return SignerDiagnosticResult(
            title: CosignCopy.SignerDiagnostics.ledgerReadyTitle,
            message: CosignCopy.SignerDiagnostics.ledgerReadyMessage(
                deviceName: device.name,
                version: configuration.version,
                blindSigning: blindSigning
            ),
            isSuccess: true
        )
    }

    @MainActor
    func testYubiKey(_ profile: SignerDiagnosticProfile) async throws -> SignerDiagnosticResult {
        diagnosticStatusMessage = CosignCopy.YubiKey.connectingStatus(transport: yubiKeyTransport.statusLabel)
        let publicKey = try await YubiKeyPIVRegistration.readEd25519PublicKey(
            preference: yubiKeyTransport.connectionPreference(
                alertMessage: CosignCopy.SignerDiagnostics.yubiKeyTestPrompt
            )
        )
        guard publicKey.pubkey == profile.pubkey else {
            throw SignerDiagnosticError.addressMismatch(
                expected: profile.address,
                actual: CosignCore.base58(publicKey.pubkey)
            )
        }

        var details = [
            CosignCopy.SignerDiagnostics.sourceDetail(displayLabel(publicKey.source.rawValue))
        ]
        if let generatedOnYubiKey = publicKey.generatedOnYubiKey {
            details.append(CosignCopy.SignerDiagnostics.keyOriginDetail(generatedOnYubiKey: generatedOnYubiKey))
        }

        return SignerDiagnosticResult(
            title: CosignCopy.SignerDiagnostics.yubiKeyReadyTitle,
            message: CosignCopy.SignerDiagnostics.yubiKeyReadyMessage(details: details.joined(separator: " ")),
            isSuccess: true
        )
    }
}

func diagnosticButtonTitle(for type: SignerType) -> String {
    switch type {
    case .hotWallet:
        CosignCopy.SignerDiagnostics.buttonTitle(for: .hotWallet)
    case .ledger:
        CosignCopy.SignerDiagnostics.buttonTitle(for: .ledger)
    case .yubikey:
        CosignCopy.SignerDiagnostics.buttonTitle(for: .yubikey)
    }
}

func diagnosticMessage(for error: any Error) -> String {
    if error is YubiKeyPIVRegistrationError || error is YubiKeySignerError {
        return yubiKeySetupNotice(for: error).message
    }

    if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
        return description
    }

    return String(describing: error)
}

struct SignerDiagnosticProfile {
    let label: String
    let type: SignerType
    let pubkey: Pubkey
    let address: String
    let keychainAccount: String?
}

struct SignerDiagnosticResult {
    let title: String
    let message: String
    let isSuccess: Bool
}

enum SignerDiagnosticError: LocalizedError {
    case missingHotWalletKeychainReference
    case invalidHotWalletSignature
    case noLedgerDevices
    case addressMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .missingHotWalletKeychainReference:
            CosignCopy.SignerDiagnostics.missingHotWalletKeychainReference
        case .invalidHotWalletSignature:
            CosignCopy.SignerDiagnostics.invalidHotWalletSignature
        case .noLedgerDevices:
            CosignCopy.SignerDiagnostics.noLedgerDevices
        case let .addressMismatch(expected, actual):
            CosignCopy.SignerDiagnostics.addressMismatch(expected: expected, actual: actual)
        }
    }
}
