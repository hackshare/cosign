import Indexer
import Squads
import SwiftUI

struct ProposalSigningSheet: View {
    let request: ProposalSigningRequest
    let proposal: SquadProposalDetail?
    let isSubmitting: Bool
    let errorMessage: String?
    let deviceStatusMessage: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @Environment(\.squadsService) private var squadsService
    @Environment(NetworkSettingsStore.self) private var networkSettings: NetworkSettingsStore?
    @State private var confirmationText = ""
    @State private var footerHeight = CosignLayout.estimatedSheetStickyFooterHeight
    @State private var frozenSolPrice: Double?
    @State private var frozenPriceAt: Date?

    private static let solMint = "So11111111111111111111111111111111111111112"

    var body: some View {
        CosignScreen(bottomPadding: CosignLayout.screenBottomPadding(stickyFooterHeight: footerHeight)) {
            sheetHeader

            SigningActionSummary(
                action: reviewAction,
                proposalAction: request.action,
                approvalWouldReachThreshold: approvalWouldReachThreshold
            )

            ProposalSigningContextCard(network: networkSettings?.selectedNetwork, items: signingContextItems)

            hardwareContext

            if requiresTypedConfirmation {
                VStack(alignment: .leading, spacing: 10) {
                    CosignSectionTitle(title: CosignCopy.ProposalSigning.highRiskConfirmationTitle)
                    CosignCard {
                        Text(CosignCopy.ProposalSigning.highRiskConfirmationPrompt(confirmationPhrase))
                            .font(CosignTheme.FontStyle.caption)
                            .foregroundStyle(CosignTheme.inkDim)
                        TextField(confirmationPhrase, text: $confirmationText)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .cosignField()
                            .accessibilityIdentifier("proposal-signing-confirmation-field")
                    }
                }
            }

            if let errorMessage {
                CosignInlineBanner(tone: .red) {
                    Text(errorMessage)
                }
            }

            if let deviceStatusMessage {
                VStack(alignment: .leading, spacing: 10) {
                    CosignSectionTitle(title: deviceStatusTitle)
                    CosignCard {
                        Text(deviceStatusMessage)
                            .font(CosignTheme.FontStyle.body)
                            .foregroundStyle(CosignTheme.inkDim)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            confirmationFooter
                .cosignMeasureHeight($footerHeight)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .task {
            let price = await squadsService.prices(for: [Self.solMint])[Self.solMint]
            frozenSolPrice = price
            if price != nil {
                frozenPriceAt = Date()
            }
        }
    }

    private var sheetHeader: some View {
        ZStack(alignment: .topTrailing) {
            Capsule()
                .fill(CosignTheme.inkGhost)
                .frame(width: 42, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

            CosignGlyphButton(
                glyph: .xmark,
                accessibilityLabel: CosignCopy.ProposalSigning.cancelSigningAccessibilityLabel
            ) {
                onCancel()
            }
            .disabled(isSubmitting)
        }
    }

    private var proposalLabel: String {
        proposal.map { "\(CosignCopy.ProposalSigning.proposalLabel) \($0.transactionIndex)" }
            ?? CosignCopy.ProposalSigning.proposalLabel
    }

    private var canConfirm: Bool {
        !isSubmitting && (!requiresTypedConfirmation || confirmationText == confirmationPhrase)
    }

    private var requiresTypedConfirmation: Bool {
        reviewAction.severity == .high
    }

    private var confirmationPhrase: String {
        CosignCopy.ProposalSigning.highRiskConfirmationPhrase(proposalIndex: proposal?.transactionIndex)
    }

    private var afterSigningText: String {
        CosignCopy.ProposalSigning.afterSigningText(
            for: request.action,
            approvalWouldReachThreshold: approvalWouldReachThreshold
        )
    }

    private var approvalWouldReachThreshold: Bool {
        guard let proposal else {
            return false
        }
        return Int(proposal.votesYes) + 1 >= Int(proposal.threshold)
    }

    private var signButtonTitle: String {
        CosignCopy.ProposalSigning.buttonTitle(for: request.action, signerType: request.signer.type)
    }

    private var confirmationFooter: some View {
        ProposalSigningFooter(
            usesHoldConfirmation: usesHoldConfirmation,
            holdButtonTitle: holdButtonTitle,
            holdHelpText: holdHelpText,
            signButtonTitle: signButtonTitle,
            signButtonKind: signButtonKind,
            isSubmitting: isSubmitting,
            canConfirm: canConfirm,
            onCancel: onCancel,
            onConfirm: onConfirm
        )
    }

    private var feeDetail: String {
        guard let frozenPriceAt, frozenSolPrice != nil else {
            return CosignCopy.ProposalSigning.networkFeeEstimateDetail
        }
        return "\(CosignCopy.ProposalSigning.networkFeeEstimateDetail) · \(CosignCopy.ProposalSigning.priceAsOf(frozenPriceAt))"
    }

    private var estimatedFeeLamports: UInt64 {
        // Solana base fee is 5000 lamports per signature; approve-and-execute
        // broadcasts two transactions.
        request.action == .approveAndExecute ? 10000 : 5000
    }

    private var signingContextItems: [ProposalSigningContextItem] {
        let signerItem = ProposalSigningContextItem(
            label: CosignCopy.ProposalSigning.signingAsLabel,
            value: request.signer.label,
            detail: shortAddress(request.signer.address)
        )
        let feeItem = ProposalSigningContextItem(
            label: CosignCopy.ProposalSigning.networkFeeLabel,
            value: CosignCopy.ProposalSigning.networkFeeEstimate(
                lamports: estimatedFeeLamports,
                solPrice: frozenSolPrice
            ),
            detail: feeDetail
        )

        var items: [ProposalSigningContextItem] = [signerItem]

        switch request.action {
        case .approveAndExecute:
            items.append(ProposalSigningContextItem(
                label: CosignCopy.ProposalSigning.actionOneLabel,
                value: CosignCopy.ProposalSigning.approveProposalTitle(
                    proposalIndex: proposal?.transactionIndex
                ),
                detail: CosignCopy.ProposalSigning.approvalActionDetail
            ))
            items.append(ProposalSigningContextItem(
                label: CosignCopy.ProposalSigning.actionTwoLabel,
                value: CosignCopy.ProposalSigning.executeActionTitle(actionTitle: reviewAction.title),
                detail: CosignCopy.ProposalSigning.executeAfterApprovalDetail
            ))
        case .execute:
            items.append(ProposalSigningContextItem(
                label: CosignCopy.ProposalSigning.approvedByLabel,
                value: approvalSummary
            ))
        case .approve:
            items.append(ProposalSigningContextItem(
                label: CosignCopy.ProposalSigning.afterSigningLabel,
                value: afterSigningText,
                detail: CosignCopy.ProposalSigning.approvalActionDetail
            ))
        case .reject:
            items.append(ProposalSigningContextItem(
                label: CosignCopy.ProposalSigning.effectLabel,
                value: CosignCopy.ProposalSigning.rejectEffectValue
            ))
        case .cancel:
            items.append(ProposalSigningContextItem(
                label: CosignCopy.ProposalSigning.effectLabel,
                value: CosignCopy.ProposalSigning.cancelEffectValue,
                detail: CosignCopy.ProposalSigning.cancelEffectDetail
            ))
        }

        items.append(feeItem)
        return items
    }

    private var approvalSummary: String {
        guard let proposal else {
            return CosignCopy.ProposalSigning.approvedByUnknownValue
        }

        return CosignCopy.ProposalSigning.approvedByValue(
            approvals: Int(proposal.votesYes),
            threshold: Int(proposal.threshold)
        )
    }

    private func shortAddress(_ address: String) -> String {
        guard address.count > 16 else {
            return address
        }

        return "\(address.prefix(4))...\(address.suffix(4))"
    }
}

private extension ProposalSigningSheet {
    var holdButtonTitle: String {
        CosignCopy.ProposalSigning.holdButtonTitle(for: request.action)
    }

    var holdHelpText: String {
        CosignCopy.ProposalSigning.holdHelpText(for: request.action)
    }

    var signButtonKind: CosignButtonKind {
        switch request.action {
        case .reject, .cancel:
            .destructive
        case .approve, .approveAndExecute, .execute:
            reviewAction.severity == .high ? .destructive : .accent
        }
    }

    var usesHoldConfirmation: Bool {
        if requiresTypedConfirmation {
            return false
        }
        switch request.action {
        case .approveAndExecute, .execute:
            return true
        case .approve, .reject, .cancel:
            return request.signer.type == .hotWallet
        }
    }

    var reviewAction: ActionObject {
        if let action = request.inspectionAction {
            return action.actionObject
        }

        return ActionObject(
            title: request.action.label,
            subtitle: CosignCopy.ProposalSigning.fallbackSubtitle(for: request.action),
            severity: .routine,
            confidence: .known,
            source: "Squads",
            roles: [
                ActionRole(
                    label: CosignCopy.ProposalSigning.signerLabel,
                    value: request.signer.address,
                    isAddressLike: true
                ),
                ActionRole(label: CosignCopy.ProposalSigning.proposalLabel, value: proposalLabel)
            ],
            warnings: []
        )
    }

    var hardwareContext: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.ProposalSigning.deviceCheckTitle)
            CosignCard {
                HStack(spacing: 12) {
                    CosignGlyphView(glyph: .faceID, size: 22, color: CosignTheme.accentDeep)
                        .frame(width: 38, height: 38)
                        .background(CosignTheme.accentWash, in: .rect(cornerRadius: CosignTheme.Radius.medium))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(CosignCopy.ProposalSigning.localHotWalletTitle)
                            .font(CosignTheme.FontStyle.body)
                            .foregroundStyle(CosignTheme.ink)
                        Text(CosignCopy.ProposalSigning.deviceContext)
                            .font(CosignTheme.FontStyle.caption)
                            .foregroundStyle(CosignTheme.inkDim)
                    }
                }
            }
        }
    }

    var deviceStatusTitle: String {
        CosignCopy.ProposalSigning.signerLabel
    }
}

extension SquadProposalAction {
    var glyph: CosignGlyph {
        switch self {
        case .approve:
            .check
        case .reject:
            .xmark
        case .cancel:
            .xmark
        case .execute:
            .play
        case .approveAndExecute:
            .check
        }
    }
}
