import SwiftUI

struct CosignAddressText: View {
    let address: String
    var displayAddress: String?
    var size: CGFloat = 12
    var color = CosignTheme.inkDim
    var copyOnTap = true
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .leading) {
            addressText
                .opacity(copied ? 0 : 1)

            if copied {
                CosignCopiedValueFeedback(value: address)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .onTapGesture {
            if copyOnTap {
                copyToPasteboard(address)
                copied = true
                Task {
                    try? await Task.sleep(for: .milliseconds(1600))
                    await MainActor.run {
                        copied = false
                    }
                }
            }
        }
        .modifier(CosignAddressTextAccessibility(address: address, isCopyEnabled: copyOnTap))
    }

    private var addressText: some View {
        Text(displayAddress ?? address)
            .font(.system(size: size, weight: .regular, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

struct CosignCopiedValueFeedback: View {
    var label = CosignCopy.Common.copied
    var value: String?

    var body: some View {
        HStack(spacing: 6) {
            CosignGlyphView(glyph: .check, size: 10, color: CosignTheme.mint)
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CosignTheme.mint)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 9)
        .frame(minWidth: 78, alignment: .center)
        .background(CosignTheme.mintWash, in: .capsule)
        .overlay {
            Capsule().stroke(CosignTheme.mint.opacity(0.30), lineWidth: 1)
        }
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
    }
}

private struct CosignAddressTextAccessibility: ViewModifier {
    let address: String
    let isCopyEnabled: Bool

    func body(content: Content) -> some View {
        if isCopyEnabled {
            content
                .accessibilityLabel(CosignCopy.Common.copyAddressAccessibilityLabel)
                .accessibilityAddTraits(.isButton)
        } else {
            content
                .accessibilityLabel(address)
        }
    }
}

/// Renders a numeric amount with the financial-receipt convention: the integer
/// part reads at full ink weight while the fractional part (including the
/// decimal separator) dims to tertiary ink at a lighter weight, so balances
/// scan like a ledger rather than a flat string.
struct CosignAmountText: View {
    let amount: String
    var size: CGFloat = 48
    var integerWeight: Font.Weight = .medium
    var fractionWeight: Font.Weight = .regular
    var integerColor: Color = CosignTheme.ink
    var fractionColor: Color = CosignTheme.inkFaint

    var body: some View {
        Text(attributed)
            .monospacedDigit()
    }

    private var attributed: AttributedString {
        let integerFont = Font.system(size: size, weight: integerWeight, design: .rounded)
        let fractionFont = Font.system(size: size, weight: fractionWeight, design: .rounded)

        let separator = Character(Locale.current.decimalSeparator ?? ".")
        guard let separatorIndex = amount.lastIndex(of: separator) else {
            var whole = AttributedString(amount)
            whole.font = integerFont
            whole.foregroundColor = integerColor
            return whole
        }

        var integerPart = AttributedString(String(amount[..<separatorIndex]))
        integerPart.font = integerFont
        integerPart.foregroundColor = integerColor

        var fractionPart = AttributedString(String(amount[separatorIndex...]))
        fractionPart.font = fractionFont
        fractionPart.foregroundColor = fractionColor

        return integerPart + fractionPart
    }
}
