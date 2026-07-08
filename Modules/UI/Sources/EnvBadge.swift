import SwiftUI

enum EnvBadgeTone {
    case neutral
    case demo
}

/// A build-environment pill shown beside the wordmark. Never rendered on
/// mainnet — see `SignersListView.envBadge` for the resolution.
struct EnvBadge: View {
    let label: String
    let tone: EnvBadgeTone

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(CosignTheme.Tracking.badge)
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background, in: .capsule)
            .overlay {
                Capsule().stroke(foreground.opacity(0.22), lineWidth: 1)
            }
            .accessibilityLabel(CosignCopy.Common.buildBadgeAccessibility(label))
    }

    private var foreground: Color {
        switch tone {
        case .neutral:
            CosignTheme.inkDim
        case .demo:
            CosignTheme.riskAmber
        }
    }

    private var background: Color {
        switch tone {
        case .neutral:
            CosignTheme.surface2
        case .demo:
            CosignTheme.accentWash
        }
    }
}
