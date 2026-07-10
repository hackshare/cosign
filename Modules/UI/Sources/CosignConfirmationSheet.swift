import SwiftUI

struct CosignCautionConfirmationSheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    let cancelTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        CosignScreen {
            header

            CosignCard(radius: CosignTheme.Radius.hero, padding: 18) {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(CosignTheme.accent.opacity(0.13))
                        Circle()
                            .stroke(CosignTheme.accent.opacity(0.26), lineWidth: 1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 26))
                            .foregroundStyle(CosignTheme.accent)
                    }
                    .frame(width: 56, height: 56)

                    Text(title)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(CosignTheme.ink)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(CosignTheme.inkDim)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 10) {
                Button {
                    onConfirm()
                } label: {
                    HStack {
                        Image(systemName: "arrow.right")
                            .foregroundStyle(CosignTheme.accentInk)
                        Text(confirmTitle)
                        Spacer()
                    }
                }
                .buttonStyle(CosignButtonStyle(kind: .accent))

                Button(cancelTitle) {
                    onCancel()
                }
                .buttonStyle(CosignButtonStyle(kind: .secondary))
            }
        }
        .presentationDetents([.height(360), .medium])
        .presentationDragIndicator(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(CosignTheme.inkGhost)
                .frame(width: 42, height: 4)
                .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                CosignGlyphButton(glyph: .xmark, accessibilityLabel: CosignCopy.Common.cancel) {
                    onCancel()
                }
            }
        }
    }
}

struct CosignDestructiveConfirmationSheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    let cancelTitle: String

    init(
        title: String,
        message: String,
        confirmTitle: String,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void,
        cancelTitle: String? = nil
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.cancelTitle = cancelTitle ?? CosignCopy.Signers.keepSignerTitle
    }

    var body: some View {
        CosignScreen {
            header

            CosignCard(radius: CosignTheme.Radius.hero, padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    CosignGlyphView(glyph: .warning, size: 24, color: CosignTheme.riskRed)
                        .frame(width: 46, height: 46)
                        .background(CosignTheme.riskRed.opacity(0.10), in: .rect(cornerRadius: CosignTheme.Radius.card))
                        .overlay {
                            RoundedRectangle(cornerRadius: CosignTheme.Radius.card)
                                .stroke(CosignTheme.riskRed.opacity(0.20), lineWidth: 1)
                        }

                    Text(message)
                        .font(CosignTheme.FontStyle.body)
                        .foregroundStyle(CosignTheme.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 10) {
                Button {
                    onConfirm()
                } label: {
                    HStack {
                        CosignGlyphView(glyph: .xmark, size: 15, color: CosignTheme.riskRed)
                        Text(confirmTitle)
                        Spacer()
                    }
                }
                .buttonStyle(CosignButtonStyle(kind: .destructive))

                Button(cancelTitle) {
                    onCancel()
                }
                .buttonStyle(CosignButtonStyle(kind: .secondary))
            }
        }
        .presentationDetents([.height(360), .medium])
        .presentationDragIndicator(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(CosignTheme.inkGhost)
                .frame(width: 42, height: 4)
                .frame(maxWidth: .infinity)

            HStack(alignment: .top) {
                Text(title)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                CosignGlyphButton(glyph: .xmark, accessibilityLabel: CosignCopy.Common.cancel) {
                    onCancel()
                }
            }
        }
    }
}
