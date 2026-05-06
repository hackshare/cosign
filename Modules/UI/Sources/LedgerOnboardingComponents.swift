import Signers
import SwiftUI

enum LedgerChecklistState {
    case done
    case active
    case pending
}

struct LedgerChecklistItem: Identifiable {
    let id = UUID()
    let title: String
    let state: LedgerChecklistState
}

struct LedgerChecklistCard: View {
    let items: [LedgerChecklistItem]

    var body: some View {
        CosignCard(padding: 4) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    LedgerChecklistRow(item: item)
                    if index < items.count - 1 {
                        Divider().overlay(CosignTheme.line)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

private struct LedgerChecklistRow: View {
    let item: LedgerChecklistItem

    var body: some View {
        HStack(spacing: 12) {
            indicator
            Text(item.title)
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(item.state == .pending ? CosignTheme.inkFaint : CosignTheme.ink)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var indicator: some View {
        switch item.state {
        case .done:
            CosignGlyphView(glyph: .check, size: 12, color: CosignTheme.mint)
                .frame(width: 22, height: 22)
                .background(CosignTheme.mintWash, in: .circle)
        case .active:
            ZStack {
                Circle().stroke(CosignTheme.accent, lineWidth: 2)
                Circle().fill(CosignTheme.accent).frame(width: 7, height: 7)
            }
            .frame(width: 22, height: 22)
        case .pending:
            Circle()
                .stroke(CosignTheme.lineStrong, lineWidth: 2)
                .frame(width: 22, height: 22)
        }
    }
}

struct LedgerDeviceMark: View {
    var size: CGFloat = 120
    var color: Color = CosignTheme.accent

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 120
            func rect(_ originX: CGFloat, _ originY: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
                CGRect(x: originX * scale, y: originY * scale, width: width * scale, height: height * scale)
            }

            let band = Path(roundedRect: rect(28, 34, 26, 52), cornerRadius: 9 * scale)
            context.fill(band, with: .color(color.opacity(0.12)))

            let bodyPath = Path(roundedRect: rect(28, 34, 64, 52), cornerRadius: 9 * scale)
            context.stroke(bodyPath, with: .color(color), lineWidth: 3 * scale)

            let button = Path(ellipseIn: rect(63, 51, 18, 18))
            context.stroke(button, with: .color(color), lineWidth: 3 * scale)
        }
        .frame(width: size, height: size)
    }
}

struct LedgerRadarView: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            ForEach(Array([140.0, 96.0, 52.0].enumerated()), id: \.offset) { index, diameter in
                Circle()
                    .stroke(CosignTheme.accent.opacity(0.30 - Double(index) * 0.08), lineWidth: 1)
                    .frame(width: diameter, height: diameter)
            }
            Circle()
                .stroke(CosignTheme.accent.opacity(0.45), lineWidth: 1)
                .frame(width: 140, height: 140)
                .scaleEffect(pulsing ? 1.0 : 0.4)
                .opacity(pulsing ? 0 : 0.7)
            LedgerDeviceMark(size: 110)
        }
        .frame(width: 140, height: 140)
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

struct LedgerFoundDeviceRow: View {
    let device: LedgerBLEDevice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LedgerDeviceMark(size: 22)
                    .frame(width: 38, height: 38)
                    .background(CosignTheme.accentWash, in: .rect(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(CosignTheme.FontStyle.titleM)
                        .foregroundStyle(CosignTheme.ink)
                    Text(CosignCopy.Ledger.deviceSubtitle(rssi: device.rssi))
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkFaint)
                }

                Spacer(minLength: 8)

                if isSelected {
                    CosignGlyphView(glyph: .check, size: 16, color: CosignTheme.accentDeep)
                }
                Circle()
                    .fill(CosignTheme.mint)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? CosignTheme.accentWash : CosignTheme.surface,
                in: .rect(cornerRadius: CosignTheme.Radius.card)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CosignTheme.Radius.card)
                    .stroke(isSelected ? CosignTheme.accent.opacity(0.40) : CosignTheme.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct LedgerSignerSummaryCard: View {
    let deviceName: String
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

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(deviceName)
                            .font(CosignTheme.FontStyle.titleM)
                            .foregroundStyle(CosignTheme.ink)
                        Text(CosignCopy.Ledger.hardwareTag)
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
