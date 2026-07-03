import CosignCore
import Signers
import SwiftUI

/// Face-ID-gated read-only reveal of a keyless hot wallet's raw secret key. The
/// key stays blurred until the user taps Reveal, which triggers the Keychain
/// biometric load. There is no copy affordance and the array is privacy-sensitive.
struct SecretKeyRevealView: View {
    let label: String
    let keychainAccount: String
    let onDismiss: () -> Void

    @State private var secretKey: String?
    @State private var unavailable = false

    var body: some View {
        CosignScreen {
            CosignCompactPageHeader(title: CosignCopy.SecretKeyReveal.headerTitle) { onDismiss() }

            VStack(alignment: .leading, spacing: 8) {
                CosignSectionTitle(title: CosignCopy.SecretKeyReveal.sectionTitle)
                Text(label)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
            }

            if unavailable {
                CosignEmptyState(
                    title: CosignCopy.SecretKeyReveal.unavailableTitle,
                    systemImage: "key.slash",
                    message: CosignCopy.SecretKeyReveal.unavailableMessage
                )
            } else {
                keySection
            }

            Button(CosignCopy.SecretKeyReveal.doneButtonTitle) { onDismiss() }
                .cosignPrimaryAction()
                .buttonStyle(.plain)
        }
        .cosignScreenIdentifier("screen.secret-key-reveal")
    }

    private var keySection: some View {
        VStack(spacing: 16) {
            Text(secretKey == nil
                ? CosignCopy.SecretKeyReveal.blurredMessage
                : CosignCopy.SecretKeyReveal.revealedMessage)
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                CosignCard {
                    Text(secretKey ?? CosignCopy.SecretKeyReveal.placeholder)
                        .font(CosignTheme.FontStyle.mono)
                        .foregroundStyle(CosignTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .blur(radius: secretKey == nil ? 9 : 0)
                .privacySensitive()
                if secretKey == nil {
                    revealButton
                }
            }

            HStack(alignment: .top, spacing: 8) {
                CosignGlyphView(glyph: .lock, size: 13, color: CosignTheme.inkFaint)
                Text(CosignCopy.SecretKeyReveal.keychainNote)
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var revealButton: some View {
        Button {
            reveal()
        } label: {
            HStack(spacing: 8) {
                CosignGlyphView(glyph: .faceID, size: 16, color: CosignTheme.accentInk)
                Text(CosignCopy.SecretKeyReveal.revealButtonTitle)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.accentInk)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(CosignTheme.accent, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("secret-key-reveal-button")
    }

    private func reveal() {
        let signer = HotWalletSigner(label: label, pubkey: Data(), keychainAccount: keychainAccount)
        do {
            let bytes = try signer.revealSecretKeyBytes(
                prompt: CosignCopy.SignerDetail.revealSecretKeyPrompt(label: label)
            )
            secretKey = "[" + bytes.map(String.init).joined(separator: ",") + "]"
        } catch {
            unavailable = true
        }
    }
}
