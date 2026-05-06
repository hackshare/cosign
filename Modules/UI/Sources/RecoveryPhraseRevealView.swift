import CosignCore
import Signers
import SwiftUI

/// Face-ID-gated read-only reveal of a hot wallet's recovery phrase. The words
/// stay blurred behind a placeholder grid until the user taps Reveal, which
/// triggers the Keychain biometric load (the load itself is the Face-ID gate).
/// There is no copy affordance and the words are marked privacy-sensitive.
struct RecoveryPhraseRevealView: View {
    let label: String
    let keychainAccount: String
    let onDismiss: () -> Void

    @State private var words: [String]?
    @State private var unavailable = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        CosignScreen {
            CosignCompactPageHeader(title: CosignCopy.RecoveryPhraseReveal.headerTitle) { onDismiss() }

            VStack(alignment: .leading, spacing: 8) {
                CosignSectionTitle(title: CosignCopy.RecoveryPhraseReveal.sectionTitle)
                Text(label)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
            }

            if unavailable {
                CosignEmptyState(
                    title: CosignCopy.RecoveryPhraseReveal.unavailableTitle,
                    systemImage: "key.slash",
                    message: CosignCopy.RecoveryPhraseReveal.unavailableMessage
                )
            } else {
                phraseSection
            }

            doneButton
        }
        .cosignScreenIdentifier("screen.recovery-phrase-reveal")
    }

    private var phraseSection: some View {
        VStack(spacing: 16) {
            Text(words == nil
                ? CosignCopy.RecoveryPhraseReveal.blurredMessage
                : CosignCopy.RecoveryPhraseReveal.revealedMessage)
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                grid
                    .blur(radius: words == nil ? 9 : 0)
                    .privacySensitive()
                if words == nil {
                    revealButton
                }
            }

            HStack(alignment: .top, spacing: 8) {
                CosignGlyphView(glyph: .lock, size: 13, color: CosignTheme.inkFaint)
                Text(CosignCopy.RecoveryPhraseReveal.keychainNote)
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(displayWords.enumerated()), id: \.offset) { index, word in
                HStack(spacing: 7) {
                    Text(CosignCopy.RecoveryPhraseReveal.wordOrdinal(index + 1))
                        .font(CosignTheme.FontStyle.monoSmall)
                        .foregroundStyle(CosignTheme.inkFaint)
                        .frame(width: 18, alignment: .trailing)
                    Text(word)
                        .font(CosignTheme.FontStyle.mono)
                        .foregroundStyle(CosignTheme.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.small))
                .overlay {
                    RoundedRectangle(cornerRadius: CosignTheme.Radius.small)
                        .stroke(CosignTheme.line, lineWidth: 1)
                }
            }
        }
    }

    private var displayWords: [String] {
        words ?? Array(repeating: "••••", count: 12)
    }

    private var revealButton: some View {
        Button {
            reveal()
        } label: {
            HStack(spacing: 8) {
                CosignGlyphView(glyph: .faceID, size: 16, color: CosignTheme.accentInk)
                Text(CosignCopy.RecoveryPhraseReveal.revealButtonTitle)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.accentInk)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(CosignTheme.accent, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recovery-phrase-reveal-button")
    }

    private var doneButton: some View {
        Button(CosignCopy.RecoveryPhraseReveal.doneButtonTitle) {
            onDismiss()
        }
        .cosignPrimaryAction()
        .buttonStyle(.plain)
    }

    private func reveal() {
        let signer = HotWalletSigner(label: label, pubkey: Data(), keychainAccount: keychainAccount)
        do {
            let mnemonic = try signer.revealMnemonic(
                prompt: CosignCopy.SignerDetail.revealPrompt(label: label)
            )
            words = mnemonic.split(separator: " ").map(String.init)
        } catch {
            unavailable = true
        }
    }
}
