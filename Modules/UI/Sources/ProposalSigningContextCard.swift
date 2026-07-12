import Core
import SwiftUI

struct ProposalSigningContextItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var detail: String?
}

struct ProposalNetworkContextRow: View {
    let network: Network
    var isLast = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: CosignFactLayout.columnSpacing) {
                CosignFactLabel(CosignCopy.ProposalSigning.networkLabel)
                    .frame(width: CosignFactLayout.labelWidth, alignment: .leading)
                    .padding(.top, 2)
                    .layoutPriority(3)
                valueArea
                    .layoutPriority(2)
            }
            .padding(.vertical, CosignFactLayout.verticalPadding)
            .padding(.horizontal, CosignFactLayout.horizontalPadding)

            if !isLast {
                Divider()
                    .overlay(CosignTheme.line)
                    .padding(
                        .leading,
                        CosignFactLayout.horizontalPadding
                            + CosignFactLayout.labelWidth
                            + CosignFactLayout.columnSpacing
                    )
            }
        }
    }

    private var valueArea: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(network == .mainnet ? CosignTheme.accent : CosignTheme.ink.opacity(0.3))
                .frame(width: 7, height: 7)
            Text(network.displayName)
                .font(
                    network == .mainnet
                        ? .system(size: 13, weight: .semibold)
                        : .system(size: 13, weight: .medium)
                )
                .foregroundStyle(
                    network == .mainnet
                        ? CosignTheme.ink
                        : CosignTheme.ink.opacity(0.82)
                )
            if network == .mainnet {
                Text(CosignCopy.ProposalSigning.mainnetSigningDetail)
                    .textCase(.uppercase)
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(CosignTheme.accent)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(CosignTheme.accent.opacity(0.13), in: Capsule())
            } else {
                Text(CosignCopy.ProposalSigning.devnetSigningDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(CosignTheme.ink.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProposalSigningContextCard: View {
    var network: Network?
    let items: [ProposalSigningContextItem]

    var body: some View {
        CosignCard(padding: 0) {
            VStack(spacing: 0) {
                if let network {
                    ProposalNetworkContextRow(network: network, isLast: items.isEmpty)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ProposalSigningContextRow(
                        label: item.label,
                        value: item.value,
                        detail: item.detail,
                        isLast: index == items.count - 1
                    )
                }
            }
        }
    }
}

private struct ProposalSigningContextRow: View {
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
