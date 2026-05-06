import Indexer
import Squads
import SwiftUI

private struct ProposalCreationSheetHeader: View {
    let isSubmitting: Bool
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Capsule()
                    .fill(CosignTheme.inkGhost)
                    .frame(width: 42, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                CosignGlyphButton(
                    glyph: .xmark,
                    accessibilityLabel: CosignCopy.Common.cancel
                ) {
                    onCancel()
                }
                .disabled(isSubmitting)
            }

            VStack(spacing: 2) {
                Text(CosignCopy.ProposalCreation.signTransferTitle)
                    .font(CosignTheme.FontStyle.titleL)
                    .foregroundStyle(CosignTheme.ink)
                Text(CosignCopy.ProposalCreation.createProposalSubtitle)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkDim)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct ProposalCreationReviewSheet: View {
    let request: ProposalCreationSigningRequest
    let isSubmitting: Bool
    let errorMessage: String?
    let deviceStatusMessage: String?
    @Binding var yubiKeyOptions: YubiKeySigningOptions
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @State private var footerHeight = CosignLayout.estimatedSheetStickyFooterHeight

    var body: some View {
        CosignScreen(bottomPadding: CosignLayout.screenBottomPadding(stickyFooterHeight: footerHeight)) {
            ProposalCreationSheetHeader(
                isSubmitting: isSubmitting,
                onCancel: onCancel
            )

            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.ProposalCreation.reviewSectionTitle)
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

            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.ProposalCreation.signerSectionTitle)
                CosignCard {
                    VStack(spacing: 0) {
                        CosignKeyValueRow(
                            label: CosignCopy.ProposalCreation.signerLabel,
                            value: request.signer.label
                        )
                        CosignKeyValueRow(
                            label: CosignCopy.ProposalCreation.signerTypeLabel,
                            value: request.signer.type.displayName
                        )
                        CosignKeyValueRow(
                            label: CosignCopy.ProposalCreation.vaultLabel,
                            value: CosignCopy.ProposalCreation.vaultDisplayName(index: request.vault.index),
                            isLast: true
                        )
                    }
                    CosignAddressBlock(
                        title: CosignCopy.ProposalCreation.signerAddressTitle,
                        address: request.signer.address,
                        accessibilityLabel: CosignCopy.ProposalCreation.copySignerAddressAccessibilityLabel()
                    )
                    .padding(.top, 12)
                    CosignAddressBlock(
                        title: CosignCopy.ProposalCreation.vaultAddressTitle,
                        address: request.vault.address,
                        accessibilityLabel: CosignCopy.ProposalCreation.copyVaultAddressAccessibilityLabel()
                    )
                    .padding(.top, 12)
                }
            }

            hardwareContext

            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.ProposalCreation.transferSectionTitle)
                CosignCard {
                    VStack(spacing: 0) {
                        CosignKeyValueRow(
                            label: CosignCopy.ProposalCreation.assetLabel,
                            value: request.assetTitle
                        )
                        CosignKeyValueRow(
                            label: CosignCopy.ProposalCreation.amountLabel,
                            value: request.amountText,
                            isLast: request.memo == nil
                        )
                        if let memo = request.memo {
                            CosignKeyValueRow(
                                label: CosignCopy.ProposalCreation.memoLabel,
                                value: memo,
                                isLast: true
                            )
                        }
                    }
                    CosignAddressBlock(
                        title: request.recipientTitle,
                        address: request.recipient,
                        accessibilityLabel: CosignCopy.ProposalCreation.copyRecipientAddressAccessibilityLabel()
                    )
                    .padding(.top, 12)
                }
            }

            if let tokenDetails = request.tokenDetails {
                VStack(alignment: .leading, spacing: 10) {
                    CosignSectionTitle(title: CosignCopy.ProposalCreation.tokenAccountsSectionTitle)
                    CosignCard {
                        VStack(spacing: 0) {
                            CosignKeyValueRow(
                                label: CosignCopy.ProposalCreation.programLabel,
                                value: tokenDetails.programLabel
                            )
                            CosignKeyValueRow(
                                label: CosignCopy.ProposalCreation.baseUnitsLabel,
                                value: tokenDetails.baseUnits.formatted(),
                                isLast: true
                            )
                        }
                        CosignAddressBlock(
                            title: CosignCopy.ProposalCreation.mintTitle,
                            address: tokenDetails.mint,
                            accessibilityLabel: CosignCopy.ProposalCreation.copyMintAddressAccessibilityLabel()
                        )
                        .padding(.top, 12)
                        CosignAddressBlock(
                            title: CosignCopy.ProposalCreation.sourceTokenAccountTitle,
                            address: tokenDetails.sourceTokenAccount,
                            accessibilityLabel: CosignCopy.ProposalCreation.copySourceTokenAccountAccessibilityLabel()
                        )
                        .padding(.top, 12)
                        CosignAddressBlock(
                            title: CosignCopy.ProposalCreation.destinationTokenAccountTitle,
                            address: tokenDetails.destinationTokenAccount,
                            accessibilityLabel: destinationTokenAccountCopyLabel
                        )
                        .padding(.top, 12)
                    }
                }
            }

            if let errorMessage {
                CosignInlineBanner(tone: .red) {
                    Text(errorMessage)
                }
            }

            if request.signer.type == .yubikey {
                YubiKeySigningControls(
                    options: $yubiKeyOptions,
                    isDisabled: isSubmitting
                )
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
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            signControlFooter
                .cosignMeasureHeight($footerHeight)
        }
        .cosignScreenIdentifier("screen.proposal-creation-review")
    }

    private var signControlFooter: some View {
        CosignStickyFooter {
            VStack(spacing: 8) {
                signControl
            }
        }
    }

    @ViewBuilder
    private var signControl: some View {
        if request.signer.type == .hotWallet {
            CosignHoldActionButton(
                title: CosignCopy.ProposalCreation.holdToSign,
                glyph: .lock,
                kind: .accent,
                isLoading: isSubmitting,
                isDisabled: !canConfirm,
                onCommit: onConfirm
            )
            .accessibilityIdentifier("proposal-creation-hold-button")
            Text(CosignCopy.ProposalCreation.holdHelpText)
                .font(CosignTheme.FontStyle.monoSmall)
                .foregroundStyle(CosignTheme.inkFaint)
                .frame(maxWidth: .infinity, alignment: .center)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        } else {
            Button {
                onConfirm()
            } label: {
                HStack {
                    if isSubmitting {
                        ProgressView()
                            .tint(CosignTheme.accentInk)
                    }
                    Text(signButtonTitle)
                }
            }
            .buttonStyle(CosignButtonStyle(kind: .accent))
            .disabled(!canConfirm)
            .accessibilityIdentifier("proposal-creation-sign-button")
        }
    }

    private var canConfirm: Bool {
        !isSubmitting && (request.signer.type != .yubikey || yubiKeyOptions.hasValidPINLength)
    }

    private var destinationTokenAccountCopyLabel: String {
        CosignCopy.ProposalCreation.copyDestinationTokenAccountAccessibilityLabel()
    }

    @ViewBuilder
    private var hardwareContext: some View {
        switch request.signer.type {
        case .hotWallet:
            EmptyView()
        case .ledger:
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.ProposalCreation.hardwareTitle(for: request.signer.type))
                CosignCard {
                    Text(CosignCopy.ProposalCreation.hardwareContext(for: request.signer.type))
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                }
            }
        case .yubikey:
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.ProposalCreation.hardwareTitle(for: request.signer.type))
                CosignCard {
                    Text(CosignCopy.ProposalCreation.hardwareContext(for: request.signer.type))
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                }
            }
        }
    }

    private var deviceStatusTitle: String {
        CosignCopy.ProposalCreation.hardwareTitle(for: request.signer.type)
    }

    private var signButtonTitle: String {
        CosignCopy.ProposalCreation.signButtonTitle(for: request.signer.type)
    }
}
