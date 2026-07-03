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
                Text((secretKeyMode ? CosignCopy.HotWallet.secretKeySectionTitle : CosignCopy.HotWallet
                        .recoveryPhraseSectionTitle).uppercased())
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(CosignTheme.inkFaint)
                Spacer()
                if !secretKeyMode { countChip }
                wordCountToggle
            }

            if secretKeyMode {
                secretKeySection
            } else {
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
                    toggleSeparator
                }
                Button {
                    selectWordCount(count)
                } label: {
                    Text(CosignCopy.HotWallet.wordCountLabel(count))
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(!secretKeyMode && count == importWords.count ? CosignTheme.ink : CosignTheme
                            .inkDim)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hot-wallet-word-count-\(count)")
            }
            toggleSeparator
            Button {
                secretKeyMode = true
            } label: {
                Text(CosignCopy.HotWallet.secretKeyModeLabel)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(secretKeyMode ? CosignTheme.ink : CosignTheme.inkDim)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hot-wallet-secret-key-mode")
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.small))
        .overlay {
            RoundedRectangle(cornerRadius: CosignTheme.Radius.small)
                .stroke(CosignTheme.line, lineWidth: 1)
        }
    }

    private var toggleSeparator: some View {
        Text(CosignCopy.HotWallet.wordCountSeparator)
            .font(CosignTheme.FontStyle.caption)
            .foregroundStyle(CosignTheme.inkFaint)
    }

    private func selectWordCount(_ count: Int) {
        secretKeyMode = false
        setWordCount(count)
    }

    private var secretKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CosignCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(maskedSecretKey)
                        .font(CosignTheme.FontStyle.mono)
                        .foregroundStyle(secretKeyNumbers == nil ? CosignTheme.inkFaint : CosignTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .privacySensitive()
                    if let secretKeyDerivedAddress {
                        Text(CosignCopy.HotWallet.secretKeyValid(address: secretKeyDerivedAddress))
                            .font(CosignTheme.FontStyle.caption)
                            .foregroundStyle(CosignTheme.mint)
                    }
                }
                .padding(.vertical, 4)
            }

            if let secretKeyError {
                Text(secretKeyError)
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.riskRed)
            } else {
                Text(CosignCopy.HotWallet.secretKeyNeverShown)
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
            }

            Button {
                pasteSecretKey()
            } label: {
                HStack(spacing: 8) {
                    CosignGlyphView(glyph: .copy, size: 14, color: CosignTheme.ink)
                    Text(CosignCopy.HotWallet.pasteSecretKeyTitle)
                }
                .cosignSecondaryAction()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hot-wallet-paste-secret-key")

            HStack(alignment: .top, spacing: 8) {
                CosignGlyphView(glyph: .lock, size: 13, color: CosignTheme.riskAmber)
                Text(CosignCopy.HotWallet.secretKeyCaution)
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var maskedSecretKey: String {
        guard let numbers = secretKeyNumbers, !numbers.isEmpty else {
            return CosignCopy.HotWallet.secretKeyPlaceholder
        }
        if numbers.count <= 6 {
            return "[" + numbers.map(String.init).joined(separator: ",") + "]"
        }
        let head = numbers.prefix(4).map(String.init).joined(separator: ",")
        let tail = numbers.suffix(2).map(String.init).joined(separator: ",")
        return "[\(head), •••••••••••• ,\(tail)]"
    }

    func pasteSecretKey() {
        guard let clipboard = UIPasteboard.general.string else { return }
        defer { UIPasteboard.general.string = "" }
        secretKeyBytes = []
        secretKeyDerivedAddress = nil
        secretKeyError = nil
        guard
            let data = clipboard.data(using: .utf8),
            let numbers = try? JSONDecoder().decode([Int].self, from: data)
        else {
            secretKeyNumbers = nil
            secretKeyError = CosignCopy.HotWallet.secretKeyNotArray
            return
        }
        secretKeyNumbers = numbers
        guard numbers.count == 64 else {
            secretKeyError = CosignCopy.HotWallet.secretKeyWrongLength(got: numbers.count)
            return
        }
        guard numbers.allSatisfy({ (0 ... 255).contains($0) }) else {
            secretKeyError = CosignCopy.HotWallet.secretKeyInvalid
            return
        }
        let bytes = numbers.map { UInt8($0) }
        do {
            let keyPair = try CosignCore.keypairFromSecretBytes(secretBytes: Data(bytes))
            secretKeyBytes = bytes
            secretKeyDerivedAddress = CosignCore.base58(keyPair.publicKey)
        } catch {
            secretKeyError = CosignCopy.HotWallet.secretKeyInvalid
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
                Text(secretKeyMode ? CosignCopy.HotWallet.secretKeyValidationHint : CosignCopy.HotWallet
                    .importValidationHint)
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
        if secretKeyMode {
            return secretKeyError == nil && secretKeyBytes.count == 64 && !isLabelEmpty
        }
        return allWordsValid && !isLabelEmpty
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
        if secretKeyMode {
            do {
                let signer = try HotWalletSigner.restore(label: label, secretBytes: Data(secretKeyBytes))
                generated = GeneratedWallet(signer: signer, mnemonic: "")
                secretKeyBytes = []
                secretKeyNumbers = nil
                saveAndAdvance(importedWithoutPhrase: true)
            } catch {
                errorMessage = String(describing: error)
            }
            return
        }
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
