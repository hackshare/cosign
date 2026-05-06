import Signers
import SwiftUI

/// Numbered BIP-39 word grid with per-cell membership validation and prefix
/// autocomplete. Invalid words read in the danger tone; the focused cell shows
/// a chip row of suggestions that fill the cell and advance focus.
struct RecoveryPhraseGrid: View {
    @Binding var words: [String]
    @FocusState private var focusedField: Int?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(words.indices, id: \.self) { index in
                    cell(index)
                }
            }

            if let focused = focusedField {
                suggestionRow(for: focused)
            }
        }
        .accessibilityIdentifier("hot-wallet-recovery-grid")
    }

    private func cell(_ index: Int) -> some View {
        let state = cellState(index)
        return HStack(spacing: 7) {
            Text(CosignCopy.HotWallet.wordIndexLabel(index + 1))
                .font(CosignTheme.FontStyle.monoSmall)
                .foregroundStyle(state.indexColor)
                .frame(width: 16, alignment: .leading)

            TextField("", text: wordBinding(index))
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(state.textColor)
                .tint(CosignTheme.accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(nil)
                .submitLabel(.next)
                .focused($focusedField, equals: index)
                .onSubmit { advanceFocus(from: index) }
                .accessibilityIdentifier("recovery-word-\(index)")
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(state.background, in: .rect(cornerRadius: CosignTheme.Radius.small))
        .overlay { cellBorder(state) }
    }

    @ViewBuilder
    private func cellBorder(_ state: RecoveryCellState) -> some View {
        let shape = RoundedRectangle(cornerRadius: CosignTheme.Radius.small)
        switch state.kind {
        case .empty:
            shape.stroke(CosignTheme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        case .focused:
            shape.stroke(CosignTheme.accent, lineWidth: 1)
        case .invalid:
            shape.stroke(CosignTheme.riskRed.opacity(0.40), lineWidth: 1)
        case .filled:
            shape.stroke(CosignTheme.line, lineWidth: 1)
        }
    }

    private func suggestionRow(for index: Int) -> some View {
        let suggestions = BIP39.suggestions(forPrefix: words[index], limit: 3)
        return HStack(spacing: 8) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    words[index] = suggestion
                    advanceFocus(from: index)
                } label: {
                    Text(suggestion)
                        .font(CosignTheme.FontStyle.mono)
                        .foregroundStyle(CosignTheme.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(CosignTheme.surface2, in: .capsule)
                        .overlay { Capsule().stroke(CosignTheme.line, lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .frame(height: suggestions.isEmpty ? 0 : 32)
        .opacity(suggestions.isEmpty ? 0 : 1)
    }

    private func wordBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { words[index] },
            set: { words[index] = $0.lowercased().trimmingCharacters(in: .whitespaces) }
        )
    }

    private func advanceFocus(from index: Int) {
        focusedField = index + 1 < words.count ? index + 1 : nil
    }

    private func cellState(_ index: Int) -> RecoveryCellState {
        let word = words[index].trimmingCharacters(in: .whitespaces)
        if focusedField == index {
            return RecoveryCellState(kind: .focused)
        }
        if word.isEmpty {
            return RecoveryCellState(kind: .empty)
        }
        return RecoveryCellState(kind: BIP39.isValidWord(word) ? .filled : .invalid)
    }
}

private struct RecoveryCellState {
    enum Kind { case empty, focused, filled, invalid }
    let kind: Kind

    var background: Color {
        kind == .empty ? CosignTheme.background : CosignTheme.surface2
    }

    var textColor: Color {
        kind == .invalid ? CosignTheme.riskRed : CosignTheme.ink
    }

    var indexColor: Color {
        switch kind {
        case .invalid: CosignTheme.riskRed
        case .empty: CosignTheme.inkGhost
        default: CosignTheme.inkFaint
        }
    }
}
