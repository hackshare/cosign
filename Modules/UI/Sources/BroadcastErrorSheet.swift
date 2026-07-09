import Squads
import SwiftUI

struct BroadcastErrorSheet: View {
    let failure: BroadcastFailure
    let isTerminal: Bool
    let isRetrying: Bool
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @State private var footerHeight = CosignLayout.estimatedSheetStickyFooterHeight

    var body: some View {
        CosignScreen(bottomPadding: CosignLayout.screenBottomPadding(stickyFooterHeight: footerHeight)) {
            sheetHeader

            mainCard

            CosignInlineBanner(tone: .mint) {
                Text(CosignCopy.BroadcastError.signatureSafeLine)
            }

            if !isTerminal {
                reasonRow

                CosignInlineBanner(tone: .neutral) {
                    Text(CosignCopy.BroadcastError.idempotencyCaption)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionFooter
                .cosignMeasureHeight($footerHeight)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(isRetrying)
        .accessibilityIdentifier("screen.broadcast-error")
    }

    private var sheetHeader: some View {
        ZStack(alignment: .topTrailing) {
            Capsule()
                .fill(CosignTheme.inkGhost)
                .frame(width: 42, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

            CosignGlyphButton(glyph: .xmark, accessibilityLabel: CosignCopy.Common.dismiss) {
                onDismiss()
            }
            .disabled(isRetrying)
        }
    }

    private var mainCard: some View {
        CosignCard(radius: CosignTheme.Radius.hero, padding: 22) {
            VStack(alignment: .leading, spacing: 16) {
                CosignGlyphView(glyph: .warning, size: 28, color: iconColor)
                    .frame(width: 62, height: 62)
                    .background(iconColor.opacity(0.10), in: .circle)

                Text(titleText)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reasonRow: some View {
        CosignCard {
            HStack(alignment: .top, spacing: 12) {
                Text(CosignCopy.BroadcastError.reasonLabel)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .frame(minWidth: 52, alignment: .leading)
                Text(CosignCopy.BroadcastError.reasonValue(reason: failure.reason, attempt: failure.attempt))
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var actionFooter: some View {
        CosignStickyFooter {
            VStack(spacing: 10) {
                if isTerminal {
                    Button(CosignCopy.BroadcastError.terminalPrimary) {
                        onDismiss()
                    }
                    .buttonStyle(CosignButtonStyle(kind: .primary))
                    .disabled(isRetrying)
                    .accessibilityIdentifier("broadcast-error-done")

                    Button(CosignCopy.BroadcastError.terminalSecondary) {
                        onRetry()
                    }
                    .buttonStyle(CosignButtonStyle(kind: .secondary, isLoading: isRetrying))
                    .disabled(isRetrying)
                    .accessibilityIdentifier("broadcast-error-try-again")
                } else {
                    Button(CosignCopy.BroadcastError.retryPrimary) {
                        onRetry()
                    }
                    .buttonStyle(CosignButtonStyle(kind: .primary, isLoading: isRetrying))
                    .disabled(isRetrying)
                    .accessibilityIdentifier("broadcast-error-retry")

                    Button(CosignCopy.BroadcastError.retrySecondary) {
                        onDismiss()
                    }
                    .buttonStyle(CosignButtonStyle(kind: .secondary))
                    .disabled(isRetrying)
                    .accessibilityIdentifier("broadcast-error-dismiss")
                }
            }
        }
    }

    private var titleText: String {
        isTerminal ? CosignCopy.BroadcastError.terminalTitle : CosignCopy.BroadcastError.retryableTitle
    }

    private var iconColor: Color {
        isTerminal ? CosignTheme.inkDim : CosignTheme.riskAmber
    }
}
