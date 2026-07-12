import Core
import SwiftUI

/// Persistent network identity chip shown beside the wordmark on the Signers home header.
/// Mainnet renders a calm identity chip; devnet renders an amber mono test badge.
struct NetworkIndicator: View {
    let network: Network

    var body: some View {
        switch network {
        case .mainnet:
            mainnetChip
        case .devnet:
            devnetBadge
        }
    }

    private var mainnetChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(CosignTheme.accent)
                .frame(width: 7, height: 7)
            Text(network.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CosignTheme.ink.opacity(0.82))
        }
        .padding(.leading, 9)
        .padding(.trailing, 11)
        .padding(.vertical, 5)
        .background(CosignTheme.surface2, in: .capsule)
        .overlay {
            Capsule().stroke(CosignTheme.ink.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CosignCopy.Common.networkIndicatorAccessibility(network.displayName))
    }

    private var devnetBadge: some View {
        Text(network.displayName.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(CosignTheme.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(CosignTheme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7).stroke(CosignTheme.accent.opacity(0.22), lineWidth: 1)
            }
            .accessibilityLabel(CosignCopy.Common.networkIndicatorAccessibility(network.displayName))
    }
}
