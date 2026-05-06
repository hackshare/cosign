import SwiftUI

/// Two-to-three peer segmented control. Tracks `surface2`, slides a `surface3`
/// thumb under the selected segment; selected label reads `ink`, peers `inkDim`.
struct CosignSegmentedControl: View {
    let labels: [String]
    @Binding var selectedIndex: Int

    private let inset: CGFloat = 3
    private let spacing: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let count = max(labels.count, 1)
            let segWidth = (proxy.size.width - inset * 2 - spacing * CGFloat(count - 1)) / CGFloat(count)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(CosignTheme.surface3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(CosignTheme.line, lineWidth: 1)
                    }
                    .frame(width: segWidth, height: proxy.size.height - inset * 2)
                    .offset(x: inset + (segWidth + spacing) * CGFloat(selectedIndex), y: inset)
                    .animation(.snappy(duration: 0.22), value: selectedIndex)

                HStack(spacing: spacing) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                        Button {
                            selectedIndex = index
                        } label: {
                            Text(label)
                                .font(.system(
                                    size: 13,
                                    weight: index == selectedIndex ? .semibold : .medium,
                                    design: .rounded
                                ))
                                .foregroundStyle(index == selectedIndex ? CosignTheme.ink : CosignTheme.inkDim)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("segment-\(label.lowercased())")
                    }
                }
                .padding(.horizontal, inset)
            }
        }
        .frame(height: 40)
        .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: CosignTheme.Radius.medium)
                .stroke(CosignTheme.line, lineWidth: 1)
        }
    }
}
