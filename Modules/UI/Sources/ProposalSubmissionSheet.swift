import Indexer
import Squads
import SwiftUI

struct ProposalSubmissionSheet: View {
    @Environment(Coordinator.self) private var coordinator
    @Environment(\.squadsService) private var squadsService

    let result: ProposalSubmissionResult
    let squadAddress: String
    let onDone: () -> Void
    var onFinishExecution: (() -> Void)?
    @State private var footerHeight = CosignLayout.estimatedSheetStickyFooterHeight
    @State private var executedStatus: ExecutedTransactionInspectionStatus?
    @State private var executedFee: UInt64?

    var body: some View {
        CosignScreen(bottomPadding: CosignLayout.screenBottomPadding(stickyFooterHeight: footerHeight)) {
            if result.kind == .partialApproveExecuted {
                PartialReceiptHeadline()

                ReceiptTwoStepCard()

                if let sig = result.signatures.first {
                    VStack(alignment: .leading, spacing: 10) {
                        CosignSectionTitle(title: CosignCopy.ProposalReceipt.signaturesTitle)
                        SignatureReceiptCard(transaction: sig) {
                            onDone()
                            coordinator.go(to: .transactionInspection(signature: sig.signature, squad: squadAddress))
                        }
                    }
                }
            } else {
                ReceiptHeadline(result: result)

                SignatureReceiptSection(result: result) { signature in
                    onDone()
                    coordinator.go(to: .transactionInspection(signature: signature, squad: squadAddress))
                }

                ReceiptFactsCard(
                    result: result,
                    executedStatus: executedStatus,
                    executedFee: executedFee
                ) { signature in
                    onDone()
                    coordinator.go(to: .transactionInspection(signature: signature, squad: squadAddress))
                }
            }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier(result.kind == .partialApproveExecuted ? "screen.partial-receipt" : "")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if result.kind == .partialApproveExecuted {
                ReceiptPartialFooter(
                    onFinishExecution: onFinishExecution ?? {},
                    onDone: onDone
                )
                .cosignMeasureHeight($footerHeight)
            } else {
                CosignReceiptDoneFooter(onViewProposal: onDone, onDone: onDone)
                    .cosignMeasureHeight($footerHeight)
            }
        }
        .task {
            if result.kind != .partialApproveExecuted {
                await loadExecutedStatus()
            }
        }
    }

    private func loadExecutedStatus() async {
        guard let signature = result.signatures.last?.signature else {
            return
        }
        executedStatus = await squadsService.executedTransactionStatus(signature: signature)
        executedFee = await squadsService.executedTransactionFee(signature: signature)
    }
}

private struct ReceiptHeadline: View {
    let result: ProposalSubmissionResult

    var body: some View {
        CosignCard(radius: CosignTheme.Radius.hero, padding: 22) {
            HStack(alignment: .top, spacing: 14) {
                CosignGlyphView(glyph: glyph, size: 26, color: toneColor)
                    .frame(width: 54, height: 54)
                    .background(toneColor.opacity(0.12), in: .circle)
                    .overlay {
                        Circle().stroke(toneColor.opacity(0.24), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text(CosignCopy.ProposalReceipt.title(for: result.action))
                        .font(CosignTheme.FontStyle.titleL)
                        .foregroundStyle(CosignTheme.ink)
                    Text(CosignCopy.ProposalReceipt.subtitle(
                        for: result.action,
                        status: result.status,
                        broadcastCount: result.signatures.count,
                        proposalIndex: result.proposalIndex
                    ))
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var glyph: CosignGlyph {
        switch result.action {
        case .reject, .cancel:
            .xmark
        case .approve, .approveAndExecute, .execute:
            .check
        }
    }

    private var toneColor: Color {
        switch result.action {
        case .reject, .cancel:
            CosignTheme.inkDim
        case .approve, .approveAndExecute, .execute:
            CosignTheme.mint
        }
    }
}

private struct SignatureReceiptSection: View {
    let result: ProposalSubmissionResult
    let onInspect: (String) -> Void

    var body: some View {
        if let signature = result.signatures.first, result.signatures.count == 1 {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.ProposalReceipt.signaturesTitle)
                SignatureReceiptCard(transaction: signature) {
                    onInspect(signature.signature)
                }
            }
        }
    }
}

private struct ReceiptFactsCard: View {
    let result: ProposalSubmissionResult
    var executedStatus: ExecutedTransactionInspectionStatus?
    var executedFee: UInt64?
    let onInspect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.ProposalReceipt.factsTitle)
            CosignCard(padding: 0) {
                VStack(spacing: 0) {
                    if let summary = result.summary {
                        ReceiptSummaryHeader(summary: summary)
                    }
                    ReceiptFactRow(
                        label: CosignCopy.ProposalReceipt.broadcastLabel,
                        value: CosignCopy.ProposalReceipt.broadcastValue(result.signatures.count),
                        detail: CosignCopy.ProposalReceipt.broadcastDetail(for: result.signatures)
                    )
                    if result.signatures.count > 1 {
                        ForEach(result.signatures, id: \.id) { transaction in
                            ReceiptSignatureFactRow(
                                transaction: transaction,
                                onInspect: { onInspect(transaction.signature) }
                            )
                        }
                    }
                    ReceiptFactRow(
                        label: CosignCopy.ProposalReceipt.statusLabel,
                        value: displayLabel(result.status)
                    )
                    if let executedStatus {
                        if let slot = executedStatus.slot {
                            ReceiptFactRow(
                                label: CosignCopy.ProposalReceipt.slotLabel,
                                value: slot.formatted(.number.grouping(.automatic))
                            )
                        }
                        if let executedFee {
                            ReceiptFactRow(
                                label: CosignCopy.ProposalReceipt.feeLabel,
                                value: CosignCopy.ProposalReceipt.feeValue(lamports: executedFee)
                            )
                        }
                        if let blockTime = executedStatus.blockTime {
                            ReceiptFactRow(
                                label: CosignCopy.ProposalReceipt.blockTimeLabel,
                                value: Date(timeIntervalSince1970: TimeInterval(blockTime))
                                    .formatted(date: .abbreviated, time: .shortened)
                            )
                        }
                        ReceiptFactRow(
                            label: CosignCopy.ProposalReceipt.confirmationLabel,
                            value: displayLabel(executedStatus.status)
                        )
                    }
                    ReceiptFactRow(
                        label: CosignCopy.ProposalReceipt.outcomeLabel,
                        value: CosignCopy.ProposalReceipt.outcome(for: result.action),
                        detail: CosignCopy.ProposalReceipt.outcomeDetail(for: result.action),
                        isLast: true
                    )
                }
            }
        }
    }
}

private struct SignatureReceiptCard: View {
    let transaction: ProposalSubmissionSignature
    let onInspect: () -> Void
    @State private var copiedSignature = false

    var body: some View {
        CosignCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(transaction.label)
                        .font(CosignTheme.FontStyle.titleM)
                        .foregroundStyle(CosignTheme.ink)
                    Spacer()
                    InspectionBadge(label: CosignCopy.Common.sent, color: CosignTheme.accentDeep)
                }

                CosignAddressBlock(
                    title: CosignCopy.ProposalReceipt.signatureLabel,
                    address: transaction.signature,
                    accessibilityLabel: CosignCopy.ProposalReceipt.copyAccessibilityLabel(for: transaction.label)
                )

                CosignReceiptActionGrid {
                    CosignReceiptActionChip(title: copyButtonTitle, glyph: copiedSignature ? .check : .copy) {
                        copySignature()
                    }
                    if let explorerURL = transaction.explorerURL {
                        Link(destination: explorerURL) {
                            CosignReceiptActionChipLabel(title: CosignCopy.Common.explorer, glyph: .external)
                        }
                        .buttonStyle(.plain)
                    }
                    CosignReceiptActionChip(
                        title: CosignCopy.Common.inspect,
                        glyph: .search,
                        accessibilityIdentifier: inspectAccessibilityIdentifier,
                        action: onInspect
                    )
                }
            }
        }
    }

    private func copySignature() {
        copyToPasteboard(transaction.signature)
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

    private var inspectAccessibilityIdentifier: String {
        "receipt-inspect-\(transaction.label.lowercased())"
    }
}

private struct ReceiptSignatureFactRow: View {
    let transaction: ProposalSubmissionSignature
    let onInspect: () -> Void
    @State private var copiedSignature = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    signatureRow(showsTrailingActions: true)
                    VStack(alignment: .leading, spacing: 10) {
                        signatureInfoRow
                        signatureActions
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, CosignFactLayout.horizontalPadding)
            .padding(.vertical, CosignFactLayout.verticalPadding)

            Divider()
                .overlay(CosignTheme.line)
                .padding(.leading, CosignFactLayout.horizontalPadding)
        }
    }

    private func signatureRow(showsTrailingActions: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            signatureInfoRow
            if showsTrailingActions {
                signatureActions
                    .fixedSize()
            }
        }
    }

    private var signatureInfoRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            CosignFactLabel(transaction.label, lineLimit: 1)
                .frame(width: CosignFactLayout.labelWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(CosignCopy.Common.sent)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.ink)
                Text(cosignShortAddress(transaction.signature))
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var signatureActions: some View {
        HStack(spacing: 6) {
            ReceiptSignatureIconButton(
                title: copyButtonTitle,
                glyph: copiedSignature ? .check : .copy,
                accessibilityIdentifier: "receipt-copy-\(transaction.label.lowercased())"
            ) {
                copySignature()
            }
            if let explorerURL = transaction.explorerURL {
                Link(destination: explorerURL) {
                    ReceiptSignatureIconLabel(glyph: .external)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CosignCopy.Common.explorer)
                .accessibilityIdentifier("receipt-explorer-\(transaction.label.lowercased())")
            }
            ReceiptSignatureIconButton(
                title: CosignCopy.Common.inspect,
                glyph: .search,
                accessibilityIdentifier: "receipt-inspect-\(transaction.label.lowercased())",
                action: onInspect
            )
        }
    }

    private func copySignature() {
        copyToPasteboard(transaction.signature)
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
}

private struct ReceiptFactRow: View {
    let label: String
    let value: String
    var detail: String?
    var isLast = false

    var body: some View {
        CosignKeyValueRow(
            label: label,
            value: value,
            detail: detail,
            isLast: isLast
        )
    }
}
