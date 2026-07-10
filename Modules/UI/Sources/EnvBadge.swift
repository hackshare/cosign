import SwiftUI

enum EnvBadgeTone {
    case demo
}

/// A build-environment pill shown beside the wordmark. Only rendered in demo builds;
/// real-network builds use `NetworkIndicator` instead.
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
        case .demo:
            CosignTheme.riskAmber
        }
    }

    private var background: Color {
        switch tone {
        case .demo:
            CosignTheme.accentWash
        }
    }
}
