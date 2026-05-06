import Core
import CosignCore
import Signers
import SwiftUI
import UIKit

extension AddHotWalletView {
    var importScreen: some View {
        CosignAnchoredFooterScreen(
            bottomPadding: CosignLayout.screenBottomPadding(
                stickyFooterHeight: CosignLayout.estimatedSheetStickyFooterHeight
            )
        ) {
            modeHeader(title: CosignCopy.HotWallet.importTitle, headline: CosignCopy.HotWallet.importHeadline)
            recoverySection
        } footer: {
            importFooter
        }
    }

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(CosignCopy.HotWallet.recoveryPhraseSectionTitle.uppercased())
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(CosignTheme.inkFaint)
                Spacer()
                countChip
                wordCountToggle
            }

            RecoveryPhraseGrid(words: $importWords)

            Button {
                pastePhrase()
            } label: {
                HStack(spacing: 8) {
                    CosignGlyphView(glyph: .copy, size: 14, color: CosignTheme.ink)
                    Text(CosignCopy.HotWallet.pastePhraseTitle)
                }
                .cosignSecondaryAction()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hot-wallet-paste-phrase")
            .accessibilityLabel(CosignCopy.HotWallet.pastePhraseAccessibilityLabel)
        }
    }

    private var countChip: some View {
        Text(CosignCopy.HotWallet.validWordCountLabel(valid: validWordCount, total: importWords.count))
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(allWordsValid ? CosignTheme.mint : CosignTheme.inkDim)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                (allWordsValid ? CosignTheme.mint : CosignTheme.ink).opacity(0.10),
                in: .capsule
            )
    }

    private var wordCountToggle: some View {
        HStack(spacing: 8) {
            ForEach(Array(BIP39.standardWordCounts.enumerated()), id: \.offset) { index, count in
                if index > 0 {
                    Text(CosignCopy.HotWallet.wordCountSeparator)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkFaint)
                }
                Button {
                    setWordCount(count)
                } label: {
                    Text(CosignCopy.HotWallet.wordCountLabel(count))
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(count == importWords.count ? CosignTheme.ink : CosignTheme.inkDim)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hot-wallet-word-count-\(count)")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.small))
        .overlay {
            RoundedRectangle(cornerRadius: CosignTheme.Radius.small)
                .stroke(CosignTheme.line, lineWidth: 1)
        }
    }

    private var importFooter: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                CosignGlyphView(glyph: .lock, size: 13, color: CosignTheme.inkFaint)
                Text(CosignCopy.HotWallet.keychainNote)
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                importWallet()
            } label: {
                HStack(spacing: 10) {
                    CosignGlyphView(glyph: .key, size: 16, color: CosignTheme.accentInk)
                    Text(CosignCopy.HotWallet.importButtonTitle)
                }
                .cosignPrimaryAction()
            }
            .buttonStyle(.plain)
            .disabled(!isImportEnabled)
            .accessibilityIdentifier("hot-wallet-import-submit")

            if !isImportEnabled {
                Text(CosignCopy.HotWallet.importValidationHint)
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
            }
        }
    }

    var trimmedWords: [String] {
        importWords.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    }

    var validWordCount: Int {
        trimmedWords.count(where: { BIP39.isValidWord($0) })
    }

    var allWordsValid: Bool {
        trimmedWords.allSatisfy { BIP39.isValidWord($0) }
    }

    var isImportEnabled: Bool {
        allWordsValid && !isLabelEmpty
    }

    func setWordCount(_ count: Int) {
        guard count != importWords.count else { return }
        var updated = Array(repeating: "", count: count)
        for index in 0 ..< min(count, importWords.count) {
            updated[index] = importWords[index]
        }
        importWords = updated
    }

    func pastePhrase() {
        guard let clipboard = UIPasteboard.general.string else { return }
        let parts = clipboard.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        let targetCount = BIP39.standardWordCounts.contains(parts.count) ? parts.count : importWords.count
        var updated = Array(repeating: "", count: targetCount)
        for (index, word) in parts.prefix(targetCount).enumerated() {
            updated[index] = word
        }
        importWords = updated
        UIPasteboard.general.string = ""
    }

    func importWallet() {
        let phrase = trimmedWords.joined(separator: " ")
        do {
            let signer = try HotWalletSigner.restore(label: label, mnemonic: phrase)
            generated = GeneratedWallet(signer: signer, mnemonic: phrase)
            saveAndAdvance()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
