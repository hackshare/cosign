import CosignCore
import Foundation
import Squads
import SwiftUI

extension CreateTransferProposalView {
    var recipientField: some View {
        HStack(spacing: 8) {
            TextField(recipientPlaceholder, text: recipientInput)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(CosignTheme.FontStyle.mono)
                .focused($focusedInput, equals: .recipient)
                .accessibilityIdentifier("proposal-builder-recipient")

            if !recipient.isEmpty {
                clearButton(CosignCopy.ProposalCreation.clearRecipientAddressAccessibilityLabel) {
                    recipient = ""
                }
            }

            #if canImport(UIKit)
            Button {
                pasteRecipient()
            } label: {
                CosignGlyphView(glyph: .copy, size: 16, color: CosignTheme.inkDim)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(CosignCopy.ProposalCreation.pasteRecipientAddressAccessibilityLabel)
            #endif
        }
    }

    func amountField(_ selectedAsset: ProposalCreationAsset?) -> some View {
        HStack(spacing: 8) {
            TextField(selectedAsset?.amountLabel ?? CosignCopy.ProposalCreation.amountLabel, text: amountInput)
                .keyboardType(.decimalPad)
                .font(CosignTheme.FontStyle.body)
                .focused($focusedInput, equals: .amount)
                .accessibilityIdentifier("proposal-builder-amount")

            if !amountText.isEmpty {
                clearButton(CosignCopy.ProposalCreation.clearAmountAccessibilityLabel) {
                    amountText = ""
                }
            }

            if let maximumTransferAmountInput, amountText != maximumTransferAmountInput {
                Button(CosignCopy.ProposalCreation.maxAmountButton) {
                    amountText = maximumTransferAmountInput
                }
                .font(CosignTheme.FontStyle.caption)
                .foregroundStyle(CosignTheme.accentDeep)
                .buttonStyle(.borderless)
            }
        }
    }

    var recipientPlaceholder: String {
        selectedAsset?.mint == nil
            ? CosignCopy.ProposalCreation.recipientAddressPlaceholder
            : CosignCopy.ProposalCreation.recipientOwnerAddressPlaceholder
    }

    func clearButton(_ accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CosignGlyphView(glyph: .xmark, size: 14, color: CosignTheme.inkFaint)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel)
    }

    var recipientInput: Binding<String> {
        Binding(
            get: { recipient },
            set: { recipient = sanitizedAddressInput($0) }
        )
    }

    var amountInput: Binding<String> {
        Binding(
            get: { amountText },
            set: { amountText = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    #if canImport(UIKit)
    func pasteRecipient() {
        if let value = UIPasteboard.general.string {
            recipient = sanitizedAddressInput(value)
        }
    }
    #endif

    func sanitizedAddressInput(_ value: String) -> String {
        value.filter { !$0.isWhitespace }
    }

    var trimmedRecipient: String {
        recipient.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAmountText: String {
        amountText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var maximumTransferAmountInput: String? {
        guard let selectedAsset,
              let selectedAssetBalanceBaseUnits
        else {
            return nil
        }
        return formattedTokenAmount(
            rawAmount: String(selectedAssetBalanceBaseUnits),
            displayAmount: nil,
            decimals: selectedAsset.decimals
        )
    }

    var amountValidationMessage: String? {
        guard !trimmedAmountText.isEmpty else {
            return nil
        }
        guard let selectedAsset else {
            return nil
        }
        guard selectedAsset.mint == nil || selectedAsset.tokenProgramID != nil else {
            return CosignCopy.ProposalCreation.tokenProgramUnavailableForAsset
        }
        guard selectedAsset.isTransferSupported else {
            return CosignCopy.ProposalCreation.unsupportedTokenProgramForTransfer
        }
        guard let parsedAmount else {
            return CosignCopy.ProposalCreation.validAmountPrompt
        }
        guard parsedAmount > 0 else {
            return CosignCopy.ProposalCreation.positiveAmountPrompt
        }
        guard let balance = selectedAssetBalanceBaseUnits else {
            return CosignCopy.ProposalCreation.assetBalanceUnavailable
        }
        guard parsedAmount <= balance else {
            return CosignCopy.ProposalCreation.amountExceedsBalance
        }
        return nil
    }

    var recipientValidationMessage: String? {
        guard !trimmedRecipient.isEmpty else {
            return nil
        }
        guard CosignCore.isValidSolanaPubkey(trimmedRecipient) else {
            return CosignCopy.ProposalCreation.validSolanaAddressPrompt
        }
        return nil
    }

    var recipientWarningMessage: String? {
        guard !trimmedRecipient.isEmpty,
              recipientValidationMessage == nil,
              trimmedRecipient == selectedVault?.ref.address
        else {
            return nil
        }
        return CosignCopy.ProposalCreation.recipientMatchesVaultWarning
    }

    var recipientConfirmationMessage: String? {
        guard !trimmedRecipient.isEmpty,
              recipientValidationMessage == nil,
              recipientWarningMessage == nil
        else {
            return nil
        }
        return CosignCopy.ProposalCreation.recipientValidConfirmation
    }

    var reviewUnavailableMessage: String? {
        if isSubmitting {
            return CosignCopy.ProposalCreation.submittingProposal
        }
        guard let detail else {
            return CosignCopy.ProposalCreation.loadSquadFirst
        }
        guard let selectedSigner else {
            return CosignCopy.ProposalCreation.chooseSigner
        }
        if let signerMessage = signerMessage(for: selectedSigner, detail: detail) {
            return signerMessage
        }
        guard let selectedVault,
              detail.vaults.contains(where: { $0.ref.index == selectedVault.ref.index })
        else {
            return CosignCopy.ProposalCreation.chooseVault
        }
        guard let selectedAsset else {
            return CosignCopy.ProposalCreation.chooseAsset
        }
        guard selectedAsset.mint == nil || selectedAsset.tokenProgramID != nil else {
            return CosignCopy.ProposalCreation.tokenProgramUnavailableForAsset
        }
        guard selectedAsset.isTransferSupported else {
            return CosignCopy.ProposalCreation.unsupportedTokenProgramForTransfer
        }
        guard !trimmedRecipient.isEmpty else {
            return selectedAsset.mint == nil
                ? CosignCopy.ProposalCreation.enterRecipientAddress
                : CosignCopy.ProposalCreation.enterRecipientOwnerAddress
        }
        if let recipientValidationMessage {
            return recipientValidationMessage
        }
        guard !trimmedAmountText.isEmpty else {
            return CosignCopy.ProposalCreation.enterAmount
        }
        if let amountValidationMessage {
            return amountValidationMessage
        }
        guard let parsedAmount, parsedAmount > 0 else {
            return CosignCopy.ProposalCreation.validAmountPrompt
        }
        return nil
    }

    var canReview: Bool {
        reviewUnavailableMessage == nil
    }

    var shouldShowReviewUnavailableMessage: Bool {
        recipientValidationMessage == nil && amountValidationMessage == nil
    }
}
