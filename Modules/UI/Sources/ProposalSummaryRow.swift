import Indexer
import Squads
import SwiftUI

struct ProposalSummaryRow: View {
    let proposal: SquadProposalSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(CosignCopy.ProposalDetail.proposalNumber(index: proposal.transactionIndex))
                .font(CosignTheme.FontStyle.monoSmall)
                .foregroundStyle(CosignTheme.inkFaint)
                .monospacedDigit()
                .frame(width: 34, alignment: .leading)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(subtitle)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkFaint)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        if isReady {
                            Text(CosignCopy.ProposalList.readyBadge)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(CosignTheme.accentDeep)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(CosignTheme.accentWash, in: .capsule)
                        }
                        StatusBadge(status: proposal.status)
                    }
                    .fixedSize()
                }

                HStack(alignment: .center, spacing: 10) {
                    Text(voteSummary)
                        .font(CosignTheme.FontStyle.monoSmall)
                        .foregroundStyle(CosignTheme.inkFaint)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if proposal.threshold > 0 {
                        CosignApprovalTicks(
                            approvals: Int(proposal.votesYes),
                            threshold: Int(proposal.threshold)
                        )
                        Text(approvalRatio)
                            .font(CosignTheme.FontStyle.monoSmall)
                            .foregroundStyle(CosignTheme.inkDim)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private var isReady: Bool {
        proposal.status.lowercased() == "approved" ||
            (proposal.threshold > 0 && proposal.votesYes >= UInt32(proposal.threshold))
    }

    private var title: String {
        proposal.action?.summary ?? "#\(proposal.transactionIndex)"
    }

    private var subtitle: String {
        guard let action = proposal.action else {
            return voteSummary
        }

        var components = [String]()
        if let label = actionMetadataLabel(action) {
            components.append(label)
        }
        components.append(displayLabel(action.classification))
        return components.joined(separator: " · ")
    }

    private var voteSummary: String {
        CosignCopy.ProposalList.voteSummary(
            approvals: proposal.votesYes,
            rejections: proposal.votesNo,
            cancellations: proposal.votesCancelled
        )
    }

    private var approvalRatio: String {
        "\(min(Int(proposal.votesYes), Int(proposal.threshold)))/\(proposal.threshold)"
    }

    private func actionMetadataLabel(_ action: RelayInspectionAction) -> String? {
        guard let label = action.effects.compactMap(\.asset).first ?? action.effects.compactMap(\.program).first else {
            return proposal.kind.map(displayLabel)
        }

        return label.count <= 6 ? label.uppercased() : displayLabel(label)
    }
}

struct StatusBadge: View {
    let status: String

    var body: some View {
        CosignStatusBadge(status: status)
    }
}

private struct CosignApprovalTicks: View {
    let approvals: Int
    let threshold: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< max(threshold, 1), id: \.self) { index in
                Capsule()
                    .fill(index < approvals ? CosignTheme.accent : CosignTheme.surface3)
                    .frame(width: 4, height: 16)
            }
        }
    }
}
