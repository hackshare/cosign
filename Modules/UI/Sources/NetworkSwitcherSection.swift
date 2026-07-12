import Core
import Indexer
import SwiftUI

struct NetworkSwitcherSection: View {
    @Environment(NetworkSettingsStore.self) private var networkSettings
    @State private var showMainnetConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.Network.networkSelectionSection)
            CosignCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(Network.allCases.enumerated()), id: \.element) { index, network in
                        if index > 0 {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                        NetworkSwitcherRow(
                            network: network,
                            isSelected: networkSettings.selectedNetwork == network
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard networkSettings.selectedNetwork != network else { return }
                            if network == .mainnet {
                                showMainnetConfirm = true
                            } else {
                                networkSettings.switch(to: network)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("network-row-\(network.rawValue)")
                    }
                }
            }
            Text(CosignCopy.Network.switchHelper)
                .font(CosignTheme.FontStyle.caption)
                .foregroundStyle(CosignTheme.inkDim)
        }
        .sheet(isPresented: $showMainnetConfirm) {
            CosignCautionConfirmationSheet(
                title: CosignCopy.Network.switchToMainnetTitle,
                message: CosignCopy.Network.switchToMainnetMessage,
                confirmTitle: CosignCopy.Network.switchToMainnetConfirm,
                cancelTitle: CosignCopy.Network.switchToMainnetCancel,
                onCancel: { showMainnetConfirm = false },
                onConfirm: {
                    showMainnetConfirm = false
                    networkSettings.switch(to: .mainnet)
                }
            )
        }
    }
}

private struct NetworkSwitcherRow: View {
    let network: Network
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 13) {
            networkIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(network.displayName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(titleColor)
                Text(subtitle)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(subtitleColor)
            }
            Spacer(minLength: 8)
            selectionIndicator
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(rowBackground)
    }

    private var networkIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(iconBackground)
                .overlay {
                    if network == .devnet {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(CosignTheme.ink.opacity(0.06), lineWidth: 1)
                    }
                }
            Image(systemName: iconName)
                .font(.system(size: iconSize))
                .foregroundStyle(iconColor)
        }
        .frame(width: 34, height: 34)
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if isSelected {
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CosignTheme.accent)
        } else {
            Circle()
                .stroke(CosignTheme.ink.opacity(0.14), lineWidth: 1.6)
                .frame(width: 22, height: 22)
        }
    }

    private var rowBackground: Color {
        network == .mainnet && isSelected ? CosignTheme.accent.opacity(0.055) : .clear
    }

    private var titleColor: Color {
        network == .mainnet ? CosignTheme.ink : CosignTheme.ink.opacity(0.82)
    }

    private var subtitleColor: Color {
        network == .mainnet ? CosignTheme.accent : CosignTheme.ink.opacity(0.5)
    }

    private var iconBackground: Color {
        network == .mainnet ? CosignTheme.accent.opacity(0.13) : CosignTheme.surface2
    }

    private var iconColor: Color {
        network == .mainnet ? CosignTheme.accent : CosignTheme.inkDim
    }

    private var iconName: String {
        network == .mainnet ? "globe" : "testtube.2"
    }

    private var iconSize: CGFloat {
        network == .mainnet ? 18 : 17
    }

    private var subtitle: String {
        switch network {
        case .mainnet: CosignCopy.Network.mainnetRowSubtitle
        case .devnet: CosignCopy.Network.devnetRowSubtitle
        }
    }
}
