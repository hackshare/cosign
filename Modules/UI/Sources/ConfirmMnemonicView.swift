import SwiftUI

struct ConfirmMnemonicView: View {
    let onConfirm: () -> Void
    let onBack: () -> Void

    @State private var checks: [WordCheck]
    @State private var selectedCheckID: UUID?
    @State private var wordChoices: [WordChoice]

    struct WordCheck: Identifiable {
        let id = UUID()
        let index: Int
        let expected: String
        var selected: WordChoice?
    }

    struct WordChoice: Identifiable, Hashable {
        let id = UUID()
        let word: String
    }

    init(
        mnemonic: String,
        onConfirm: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.onConfirm = onConfirm
        self.onBack = onBack
        let words = mnemonic.split(separator: " ").map(String.init)
        let pickedIndices = Array(0 ..< words.count).shuffled().prefix(3).sorted()
        let checks = pickedIndices.map {
            WordCheck(index: $0, expected: words[$0])
        }
        _checks = State(initialValue: checks)
        _selectedCheckID = State(initialValue: checks.first?.id)
        _wordChoices = State(initialValue: words.map { WordChoice(word: $0) }.shuffled())
    }

    var body: some View {
        CosignScreen {
            CosignFlowHeader(
                title: CosignCopy.MnemonicConfirmation.flowTitle,
                cancelTitle: CosignCopy.MnemonicConfirmation.backButtonTitle,
                onCancel: onBack
            )

            VStack(alignment: .leading, spacing: 8) {
                CosignSectionTitle(title: CosignCopy.MnemonicConfirmation.sectionTitle)
                Text(CosignCopy.MnemonicConfirmation.title)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
            }

            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.MnemonicConfirmation.selectedWordsSectionTitle)
                VStack(spacing: 10) {
                    ForEach(checks) { check in
                        wordCheckRow(check)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.MnemonicConfirmation.mnemonicWordsSectionTitle)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(wordChoices) { choice in
                        Button {
                            select(choice)
                        } label: {
                            Text(choice.word)
                                .font(CosignTheme.FontStyle.mono)
                                .foregroundStyle(isSelected(choice) ? CosignTheme.accentInk : CosignTheme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    isSelected(choice) ? CosignTheme.accent : CosignTheme.surface,
                                    in: .rect(cornerRadius: CosignTheme.Radius.medium)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: CosignTheme.Radius.medium)
                                        .stroke(CosignTheme.line, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(spacing: 10) {
                Button {
                    if allMatch {
                        onConfirm()
                    }
                } label: {
                    Text(CosignCopy.MnemonicConfirmation.confirmButtonTitle)
                        .cosignPrimaryAction()
                }
                .buttonStyle(.plain)
                .disabled(!allMatch)

                Button {
                    onBack()
                } label: {
                    Text(CosignCopy.MnemonicConfirmation.backToMnemonicTitle)
                        .cosignSecondaryAction()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func wordCheckRow(_ check: WordCheck) -> some View {
        Button {
            selectedCheckID = check.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(CosignCopy.MnemonicConfirmation.wordTitle(index: check.index + 1))
                        .font(CosignTheme.FontStyle.eyebrow)
                        .foregroundStyle(CosignTheme.inkFaint)
                    Text(check.selected?.word ?? CosignCopy.MnemonicConfirmation.emptySelectionPrompt)
                        .font(CosignTheme.FontStyle.mono)
                        .foregroundStyle(check.selected == nil ? CosignTheme.inkDim : CosignTheme.ink)
                }

                Spacer()

                CosignGlyphView(glyph: statusGlyph(for: check), size: 18, color: statusColor(for: check))
            }
            .padding(16)
            .background(rowBackground(for: check), in: .rect(cornerRadius: CosignTheme.Radius.hero))
            .overlay {
                RoundedRectangle(cornerRadius: CosignTheme.Radius.hero)
                    .stroke(rowBorder(for: check), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func select(_ choice: WordChoice) {
        guard let selectedCheckID,
              let selectedIndex = checks.firstIndex(where: { $0.id == selectedCheckID })
        else {
            return
        }

        checks[selectedIndex].selected = choice

        if let nextCheck = checks.first(where: { $0.selected == nil }) {
            self.selectedCheckID = nextCheck.id
        } else {
            self.selectedCheckID = nil
        }
    }

    private func isSelected(_ choice: WordChoice) -> Bool {
        checks.contains {
            $0.selected == choice
        }
    }

    private var allMatch: Bool {
        checks.allSatisfy {
            $0.selected?.word == $0.expected
        }
    }

    private func rowBackground(for check: WordCheck) -> Color {
        if check.isCorrect {
            return CosignTheme.mintWash
        }
        if check.isIncorrect {
            return CosignTheme.riskRed.opacity(0.12)
        }
        if check.id == selectedCheckID {
            return CosignTheme.accent.opacity(0.12)
        }
        return CosignTheme.surface
    }

    private func rowBorder(for check: WordCheck) -> Color {
        if check.isCorrect {
            return CosignTheme.mintDeep.opacity(0.38)
        }
        if check.isIncorrect {
            return CosignTheme.riskRed.opacity(0.34)
        }
        if check.id == selectedCheckID {
            return CosignTheme.accentDeep.opacity(0.28)
        }
        return CosignTheme.line
    }

    private func statusGlyph(for check: WordCheck) -> CosignGlyph {
        if check.isCorrect {
            return .check
        }
        if check.isIncorrect {
            return .xmark
        }
        return .circle
    }

    private func statusColor(for check: WordCheck) -> Color {
        if check.isCorrect {
            return CosignTheme.mintDeep
        }
        if check.isIncorrect {
            return CosignTheme.riskRed
        }
        return check.id == selectedCheckID ? CosignTheme.accentDeep : CosignTheme.inkGhost
    }
}

private extension ConfirmMnemonicView.WordCheck {
    var isCorrect: Bool {
        selected?.word == expected
    }

    var isIncorrect: Bool {
        selected != nil && !isCorrect
    }
}
