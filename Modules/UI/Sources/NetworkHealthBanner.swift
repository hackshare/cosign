import Indexer
import SwiftUI

public struct NetworkHealthBanner: View {
    @Environment(NetworkHealth.self) private var networkHealth: NetworkHealth?

    public init() {}

    public var body: some View {
        if let networkHealth, networkHealth.status != .healthy {
            NetworkHealthBannerBar(
                status: networkHealth.status,
                lastSuccess: networkHealth.lastSuccess
            ) {
                networkHealth.retry()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

private struct NetworkHealthBannerBar: View {
    let status: NetworkHealthStatus
    var lastSuccess: Date?
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CosignGlyphView(glyph: glyph, size: 13, color: tone)
                .frame(width: 26, height: 26)
                .background(tone.opacity(0.14), in: .circle)

            VStack(alignment: .leading, spacing: 1) {
                Text(CosignCopy.NetworkHealth.title(for: status))
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.ink)
                Text(CosignCopy.NetworkHealth.detail(for: status))
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkDim)
            }

            Spacer(minLength: 8)

            if showsTimestamp, let lastSuccess {
                Text(CosignCopy.NetworkHealth.updatedAgo(lastSuccess))
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkFaint)
            }

            if status == .offline {
                Button(action: onRetry) {
                    Text(CosignCopy.NetworkHealth.retry)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.accentInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(CosignTheme.accent, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("network-health-retry")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CosignTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CosignTheme.line)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(CosignCopy.NetworkHealth.bannerAccessibilityIdentifier)
    }

    private var showsTimestamp: Bool {
        status == .webSocketDown || status == .offline
    }

    private var tone: Color {
        switch status {
        case .offline:
            CosignTheme.riskRed
        case .webSocketDown, .healthy:
            CosignTheme.inkDim
        }
    }

    private var glyph: CosignGlyph {
        switch status {
        case .offline:
            .warning
        case .webSocketDown, .healthy:
            .wave
        }
    }
}
