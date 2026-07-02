import SwiftUI

struct YubiKeyMark: View {
    var size: CGFloat = 120
    var color: Color = CosignTheme.accent

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 120
            func rect(_ originX: CGFloat, _ originY: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
                CGRect(x: originX * scale, y: originY * scale, width: width * scale, height: height * scale)
            }

            let bodyPath = Path(roundedRect: rect(40, 28, 40, 64), cornerRadius: 14 * scale)
            context.stroke(bodyPath, with: .color(color), lineWidth: 3 * scale)

            let disc = Path(ellipseIn: rect(51, 41, 18, 18))
            context.stroke(disc, with: .color(color), lineWidth: 3 * scale)

            var stem = Path()
            stem.move(to: CGPoint(x: 60 * scale, y: 59 * scale))
            stem.addLine(to: CGPoint(x: 60 * scale, y: 77 * scale))
            stem.move(to: CGPoint(x: 54 * scale, y: 70 * scale))
            stem.addLine(to: CGPoint(x: 66 * scale, y: 70 * scale))
            context.stroke(stem, with: .color(color), style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

/// Concentric rings around the key mark, used on the tap/insert and touch screens.
struct YubiKeyHaloView: View {
    var pulses = false
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(CosignTheme.accent.opacity(0.25), lineWidth: 1)
                .frame(width: 150, height: 150)
            Circle()
                .stroke(CosignTheme.accent.opacity(0.16), lineWidth: 1)
                .frame(width: 90, height: 90)
            if pulses {
                Circle()
                    .stroke(CosignTheme.accent.opacity(0.40), lineWidth: 2)
                    .frame(width: 132, height: 132)
                    .scaleEffect(pulsing ? 1.0 : 0.5)
                    .opacity(pulsing ? 0 : 0.8)
            }
            YubiKeyMark(size: 120)
        }
        .frame(width: 150, height: 150)
        .onAppear {
            guard pulses else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

struct YubiKeyStatusPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(CosignTheme.accent).frame(width: 8, height: 8)
            Text(text)
                .font(CosignTheme.FontStyle.caption)
                .foregroundStyle(CosignTheme.accent)
        }
    }
}

struct YubiKeyPINDots: View {
    let count: Int
    var capacity = 8

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0 ..< capacity, id: \.self) { index in
                Circle()
                    .fill(index < count ? CosignTheme.accent : CosignTheme.surface3)
                    .frame(width: 14, height: 14)
                    .overlay { Circle().stroke(CosignTheme.line, lineWidth: 1) }
            }
        }
    }
}

struct YubiKeyPINPad: View {
    @Binding var pin: String
    var maxLength = 8
    var isDisabled = false

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0 ..< 3, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(0 ..< 3, id: \.self) { column in
                        digitKey(keys[row * 3 + column])
                    }
                }
            }
            HStack(spacing: 12) {
                Color.clear.frame(maxWidth: .infinity, minHeight: 58)
                digitKey("0")
                deleteKey
            }
        }
        .disabled(isDisabled)
    }

    private func digitKey(_ value: String) -> some View {
        Button {
            guard pin.count < maxLength else { return }
            pin.append(value)
        } label: {
            Text(value)
                .font(CosignTheme.FontStyle.titleL)
                .foregroundStyle(CosignTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: CosignTheme.Radius.medium)
                        .stroke(CosignTheme.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("yubikey-pin-\(value)")
    }

    private var deleteKey: some View {
        Button {
            guard !pin.isEmpty else { return }
            pin.removeLast()
        } label: {
            Text(CosignCopy.YubiKey.pinDeleteLabel)
                .font(CosignTheme.FontStyle.caption)
                .foregroundStyle(CosignTheme.inkDim)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: CosignTheme.Radius.medium)
                        .stroke(CosignTheme.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CosignCopy.YubiKey.pinDeleteAccessibility)
        .accessibilityIdentifier("yubikey-pin-delete")
    }
}

struct YubiKeySignerSummaryCard: View {
    let name: String
    let address: String

    var body: some View {
        CosignCard {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 13)
                    .fill(
                        LinearGradient(
                            colors: [CosignTheme.accent, Color(hex: 0x241808)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay { YubiKeyMark(size: 26, color: CosignTheme.accentInk) }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(CosignTheme.FontStyle.titleM)
                            .foregroundStyle(CosignTheme.ink)
                        Text(CosignCopy.YubiKey.hardwareTag)
                            .font(CosignTheme.FontStyle.eyebrow)
                            .foregroundStyle(CosignTheme.mint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(CosignTheme.mintWash, in: .rect(cornerRadius: 4))
                    }
                    Text(cosignShortAddress(address))
                        .font(CosignTheme.FontStyle.mono)
                        .foregroundStyle(CosignTheme.inkDim)
                }

                Spacer(minLength: 0)
            }
        }
    }
}
