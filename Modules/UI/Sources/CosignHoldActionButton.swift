import SwiftUI

struct CosignHoldActionButton: View {
    private let height: CGFloat = 56

    let title: String
    let glyph: CosignGlyph
    let kind: CosignButtonKind
    let isLoading: Bool
    let isDisabled: Bool
    let onCommit: () -> Void

    @State private var progress: Double = 0
    @State private var progressTask: Task<Void, Never>?

    var body: some View {
        let colors = kind.colors(isEnabled: !isDisabled)

        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: CosignTheme.Radius.medium)
                .fill(colors.background)

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: CosignTheme.Radius.medium)
                    .fill(CosignTheme.ink.opacity(0.10))
                    .frame(width: proxy.size.width * progress)
                    .frame(maxHeight: .infinity)
            }
            .allowsHitTesting(false)

            HStack(spacing: 10) {
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    CosignGlyphView(glyph: glyph, size: 16, color: colors.foreground)
                    Text(title)
                        .font(CosignTheme.FontStyle.body)
                        .foregroundStyle(colors.foreground)
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(.rect(cornerRadius: CosignTheme.Radius.medium))
        .overlay {
            if let border = colors.border {
                RoundedRectangle(cornerRadius: CosignTheme.Radius.medium)
                    .stroke(border, lineWidth: 1)
            }
        }
        .opacity(isDisabled ? 0.55 : 1)
        .contentShape(.rect(cornerRadius: CosignTheme.Radius.medium))
        .allowsHitTesting(!isDisabled && !isLoading)
        .onLongPressGesture(
            minimumDuration: 1.5,
            maximumDistance: 50,
            pressing: handlePressing,
            perform: {
                finishHold()
                onCommit()
            }
        )
        .onDisappear {
            progressTask?.cancel()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }

    private func handlePressing(_ isPressing: Bool) {
        if isPressing {
            startHold()
        } else if progress < 1 {
            cancelHold()
        }
    }

    private func startHold() {
        progressTask?.cancel()
        progress = 0
        progressTask = Task {
            for step in 1 ... 15 {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    withAnimation(.linear(duration: 0.08)) {
                        progress = Double(step) / 15
                    }
                }
            }
        }
    }

    private func cancelHold() {
        progressTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            progress = 0
        }
    }

    private func finishHold() {
        progressTask?.cancel()
        progress = 1
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            await MainActor.run {
                progress = 0
            }
        }
    }
}
