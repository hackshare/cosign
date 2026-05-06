import Squads
import SwiftUI

struct ProposalCreationResultSheet: View {
    let result: ProposalCreationResult
    let onDone: () -> Void
    let onOpenProposal: () -> Void
    let onInspectSignature: () -> Void
    @State private var copiedSignature = false
    @State private var footerHeight = CosignLayout.estimatedSheetStickyFooterHeight

    var body: some View {
        CosignScreen(bottomPadding: CosignLayout.screenBottomPadding(stickyFooterHeight: footerHeight)) {
            CosignSuccessReceipt(
                title: CosignCopy.ProposalCreation.proposalSubmittedTitle,
                message: CosignCopy.ProposalCreation.proposalSubmittedMessage
            )

            signatureSection
            factsSection
            addressesSection
        }
        .presentationDetents([.large])
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CosignReceiptDoneFooter(onDone: onDone)
                .cosignMeasureHeight($footerHeight)
        }
        .cosignScreenIdentifier("screen.proposal-creation-result")
    }

    private var factsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.ProposalReceipt.factsTitle)
            CosignCard {
                VStack(spacing: 0) {
                    CosignKeyValueRow(
                        label: CosignCopy.ProposalCreation.proposalLabel,
                        value: proposalValue
                    )
                    CosignKeyValueRow(
                        label: CosignCopy.ProposalReceipt.broadcastLabel,
                        value: CosignCopy.ProposalReceipt.broadcastValue(1),
                        detail: CosignCopy.ProposalCreation.submittedSignatureTitle
                    )
                    if let proposal = result.submission.proposal {
                        CosignKeyValueRow(
                            label: CosignCopy.ProposalCreation.statusLabel,
                            value: displayLabel(proposal.status)
                        )
                    }
                    CosignKeyValueRow(
                        label: CosignCopy.ProposalCreation.outcomeLabel,
                        value: CosignCopy.ProposalCreation.proposalCreatedOutcome,
                        detail: CosignCopy.ProposalCreation.proposalCreatedOutcomeDetail,
                        isLast: true
                    )
                }
            }
        }
    }

    private var signatureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.ProposalCreation.signatureSectionTitle)
            CosignCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(CosignCopy.ProposalCreation.submittedSignatureTitle)
                            .font(CosignTheme.FontStyle.titleM)
                            .foregroundStyle(CosignTheme.ink)
                        Spacer()
                        InspectionBadge(label: CosignCopy.Common.sent, color: CosignTheme.accentDeep)
                    }

                    CosignAddressBlock(
                        title: CosignCopy.ProposalCreation.transactionSignatureTitle,
                        address: result.submission.signature,
                        accessibilityLabel: CosignCopy.ProposalCreation.copyTransactionSignatureAccessibilityLabel()
                    )

                    CosignReceiptActionGrid {
                        CosignReceiptActionChip(
                            title: copyButtonTitle,
                            glyph: copiedSignature ? .check : .copy,
                            accessibilityIdentifier: "proposal-creation-copy-signature"
                        ) {
                            copySignature()
                        }

                        if let explorerURL = result.explorerURL {
                            Link(destination: explorerURL) {
                                CosignReceiptActionChipLabel(title: CosignCopy.Common.explorer, glyph: .external)
                            }
                            .buttonStyle(.plain)
                        }

                        CosignReceiptActionChip(
                            title: CosignCopy.Common.inspect,
                            glyph: .search,
                            accessibilityIdentifier: "proposal-creation-inspect-signature",
                            action: onInspectSignature
                        )

                        CosignReceiptActionChip(
                            title: CosignCopy.ProposalCreation.openProposalTitle,
                            glyph: .document,
                            accessibilityIdentifier: "proposal-creation-open-proposal",
                            action: onOpenProposal
                        )
                    }
                }
            }
        }
    }

    private var addressesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.ProposalCreation.addressesSectionTitle)
            CosignCard {
                CosignAddressBlock(
                    title: CosignCopy.ProposalCreation.proposalAccountTitle,
                    address: result.submission.proposalAddress,
                    accessibilityLabel: CosignCopy.ProposalCreation.copyProposalAddressAccessibilityLabel()
                )
                CosignAddressBlock(
                    title: CosignCopy.ProposalCreation.transactionAccountTitle,
                    address: result.submission.transactionAddress,
                    accessibilityLabel: CosignCopy.ProposalCreation.copyTransactionAddressAccessibilityLabel()
                )
                .padding(.top, 12)
                CosignAddressBlock(
                    title: CosignCopy.ProposalCreation.vaultAddressTitle,
                    address: result.submission.vaultAddress,
                    accessibilityLabel: CosignCopy.ProposalCreation.copyVaultAddressAccessibilityLabel()
                )
                .padding(.top, 12)
            }
        }
    }

    private func copySignature() {
        copyToPasteboard(result.submission.signature)
        copiedSignature = true
        Task {
            try? await Task.sleep(for: .milliseconds(1600))
            await MainActor.run {
                copiedSignature = false
            }
        }
    }

    private var copyButtonTitle: String {
        copiedSignature ? CosignCopy.Common.copied : CosignCopy.Common.copy
    }

    private var proposalValue: String {
        "\(CosignCopy.ProposalCreation.proposalLabel) \(result.submission.transactionIndex)"
    }
}
