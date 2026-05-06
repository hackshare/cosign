import Squads
import SwiftUI

extension CreateTransferProposalView {
    func builderHeader(_ detail: SquadDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(CosignCopy.ProposalCreation.builderTitle(squadName: proposalSquadName(detail)))
                    .font(CosignTheme.FontStyle.titleL)
                    .foregroundStyle(CosignTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(CosignCopy.ProposalCreation.stepCounter(
                    current: builderStep.index,
                    total: TransferProposalBuilderStep.allCases.count
                ))
                .font(CosignTheme.FontStyle.mono)
                .foregroundStyle(CosignTheme.inkFaint)
            }

            CosignStepProgress(
                currentStep: builderStep.index,
                totalSteps: TransferProposalBuilderStep.allCases.count
            )

            VStack(alignment: .leading, spacing: 7) {
                Text(builderStep.headline)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(builderStep.subtitle)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    func builderStepContent(_ detail: SquadDetail) -> some View {
        switch builderStep {
        case .vaultAsset:
            vaultAssetStep(detail)
        case .recipient:
            recipientStep
        case .amount:
            amountStep
        case .review:
            reviewStep(detail)
        }
    }

    var builderNavigation: some View {
        HStack(spacing: 12) {
            if builderStep.previous != nil {
                Button {
                    goToPreviousBuilderStep()
                } label: {
                    HStack {
                        CosignGlyphView(glyph: .chevronLeft, size: 14, color: CosignTheme.ink)
                        Text(CosignCopy.ProposalCreation.backButton)
                    }
                }
                .buttonStyle(CosignButtonStyle(kind: .secondary))
            }

            if builderStep.next != nil {
                Button {
                    goToNextBuilderStep()
                } label: {
                    HStack {
                        Text(CosignCopy.ProposalCreation.nextButton)
                        CosignGlyphView(glyph: .chevronRight, size: 14, color: nextButtonGlyphColor)
                    }
                }
                .disabled(!canAdvanceFromCurrentStep)
                .buttonStyle(CosignButtonStyle(kind: nextButtonKind))
                .accessibilityIdentifier("proposal-builder-next")
            } else {
                Button {
                    startReview()
                } label: {
                    HStack {
                        CosignGlyphView(glyph: .external, size: 15, color: reviewButtonGlyphColor)
                        Text(CosignCopy.ProposalCreation.reviewAndSignButton)
                    }
                }
                .disabled(!canReview)
                .buttonStyle(CosignButtonStyle(kind: reviewButtonKind))
            }
        }
    }

    var nextButtonKind: CosignButtonKind {
        canAdvanceFromCurrentStep ? .accent : .secondary
    }

    var nextButtonGlyphColor: Color {
        canAdvanceFromCurrentStep ? CosignTheme.accentInk : CosignTheme.inkFaint
    }

    var reviewButtonKind: CosignButtonKind {
        canReview ? .accent : .secondary
    }

    var reviewButtonGlyphColor: Color {
        canReview ? CosignTheme.accentInk : CosignTheme.inkFaint
    }

    var builderFooter: some View {
        CosignStickyFooter {
            builderNavigation
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("proposal-builder-footer")
    }

    func vaultAssetStep(_ detail: SquadDetail) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                Text(CosignCopy.ProposalCreation.fromVaultLabel.uppercased())
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(CosignTheme.inkFaint)
                CosignSelectorField(
                    title: selectedVault
                        .map { CosignCopy.ProposalCreation.vaultDisplayName(index: $0.ref.index) } ??
                        CosignCopy.ProposalCreation.selectVaultTitle,
                    subtitle: selectedVault?.nativeBalanceLamports.map(solAmount),
                    detail: selectedVault.map { cosignShortAddress($0.ref.address) },
                    isDisabled: detail.vaults.isEmpty,
                    accessibilityIdentifier: "selector-field-vault"
                ) {
                    presentSelector(.vault)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(CosignCopy.ProposalCreation.assetLabel.uppercased())
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(CosignTheme.inkFaint)
                CosignSelectorField(
                    title: selectedAsset?.title ?? CosignCopy.ProposalCreation.selectAssetTitle,
                    subtitle: selectedAsset.map(selectedAssetBalanceText),
                    detail: selectedAsset?.programDetail,
                    isDisabled: transferAssets.isEmpty,
                    accessibilityIdentifier: "selector-field-asset"
                ) {
                    presentSelector(.asset)
                }
            }

            if unsupportedTransferTokenCount > 0 {
                CosignInlineBanner {
                    Text(CosignCopy.ProposalCreation.unsupportedTokenProgramMessage)
                }
            }
        }
    }

    var recipientStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            recipientInputGroup

            HStack(spacing: 10) {
                proposalBuilderUtilityButton(
                    title: CosignCopy.ProposalCreation.pasteButton,
                    glyph: .copy,
                    isDisabled: false
                ) {
                    pasteRecipientIfAvailable()
                }
                proposalBuilderUtilityButton(
                    title: CosignCopy.ProposalCreation.scanQRButton,
                    glyph: .search,
                    isDisabled: true
                ) {}
                proposalBuilderUtilityButton(
                    title: CosignCopy.ProposalCreation.knownRecipientButton,
                    glyph: .circle,
                    isDisabled: true
                ) {}
            }
        }
    }

    var amountStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let amountRouteSubtitle {
                Text(amountRouteSubtitle)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.inkDim)
            }
            amountInputGroup
            memoInputGroup
        }
    }

    func reviewStep(_ detail: SquadDetail) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let request = makeSigningRequestIfPossible() {
                CosignCard {
                    RelayInspectionActionView(
                        action: request.reviewAction,
                        fallbackLabel: request.actionLabel,
                        fallbackColor: CosignTheme.accentDeep
                    )
                    Text(CosignCopy.ProposalCreation.reviewContext)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                        .padding(.top, 8)
                }
            }

            signerSection(detail)

            if let reviewUnavailableMessage, shouldShowReviewUnavailableMessage {
                CosignInlineBanner(tone: .amber) {
                    Text(reviewUnavailableMessage)
                }
            }

            if let errorMessage {
                CosignInlineBanner(tone: .red) {
                    Text(errorMessage)
                }
            }
        }
    }

    func proposalSquadName(_ detail: SquadDetail) -> String {
        detail.displayName ?? cosignShortAddress(detail.address, prefix: 4, suffix: 4)
    }

    func goToNextBuilderStep() {
        guard canAdvanceFromCurrentStep, let nextStep = builderStep.next else {
            return
        }
        focusedInput = nil
        builderStep = nextStep
    }

    func goToPreviousBuilderStep() {
        guard let previousStep = builderStep.previous else {
            return
        }
        focusedInput = nil
        builderStep = previousStep
    }

    var canAdvanceFromCurrentStep: Bool {
        switch builderStep {
        case .vaultAsset:
            selectedVault != nil && selectedAsset != nil
        case .recipient:
            !trimmedRecipient.isEmpty && recipientValidationMessage == nil
        case .amount:
            !trimmedAmountText.isEmpty && amountValidationMessage == nil
        case .review:
            canReview
        }
    }

    var amountRouteSubtitle: String? {
        guard let selectedVault else {
            return nil
        }
        let vaultName = CosignCopy.ProposalCreation.vaultDisplayName(index: selectedVault.ref.index)
        let recipientName = trimmedRecipient.isEmpty
            ? CosignCopy.ProposalCreation.recipientTitle
            : cosignShortAddress(trimmedRecipient)
        return CosignCopy.ProposalCreation.amountRouteSubtitle(
            vaultName: vaultName,
            recipient: recipientName
        )
    }

    func proposalBuilderUtilityButton(
        title: String,
        glyph: CosignGlyph,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                CosignGlyphView(glyph: glyph, size: 15, color: isDisabled ? CosignTheme.inkFaint : CosignTheme.ink)
                Text(title)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(minHeight: 54)
        }
        .disabled(isDisabled)
        .buttonStyle(CosignButtonStyle(kind: .secondary))
    }

    func pasteRecipientIfAvailable() {
        #if canImport(UIKit)
        pasteRecipient()
        #endif
    }

    func makeSigningRequestIfPossible() -> ProposalCreationSigningRequest? {
        try? makeSigningRequest()
    }

    func makeSigningRequest() throws -> ProposalCreationSigningRequest {
        guard
            let selectedSigner,
            let selectedVault,
            let selectedAsset,
            let amount = parsedAmount,
            amount > 0
        else {
            throw ProposalCreationBuilderError.incomplete
        }

        let draft = transferDraft(asset: selectedAsset, vault: selectedVault, amount: amount)
        return try ProposalCreationSigningRequest(
            draft: draft,
            signer: selectedSigner,
            vault: selectedVault.ref,
            assetTitle: selectedAsset.title,
            amountText: amountText(for: selectedAsset, amount: amount),
            tokenDetails: tokenDetails(
                asset: selectedAsset,
                vault: selectedVault,
                amount: amount
            )
        )
    }
}

enum ProposalCreationBuilderError: Error {
    case incomplete
}
