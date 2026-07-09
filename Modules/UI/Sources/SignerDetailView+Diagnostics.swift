import Core
import CosignCore
import Foundation
import Persistence
import Signers
import SwiftUI

extension SignerDetailView {
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
                        Text(CosignCopy.SignerDiagnostics.buttonTitle(for: signer.type))
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
            diagnosticResult = try await testHotWallet(profile)
        } catch {
            diagnosticResult = SignerDiagnosticResult(
                title: CosignCopy.SignerDiagnostics.testFailedTitle,
                message: diagnosticMessage(for: error),
                isSuccess: false
            )
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
}

func diagnosticMessage(for error: any Error) -> String {
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

    var errorDescription: String? {
        switch self {
        case .missingHotWalletKeychainReference:
            CosignCopy.SignerDiagnostics.missingHotWalletKeychainReference
        case .invalidHotWalletSignature:
            CosignCopy.SignerDiagnostics.invalidHotWalletSignature
        }
    }
}
