import CosignCore
import SwiftUI

extension AddYubiKeyView {
    var tapOrInsertStep: some View {
        CosignAnchoredFooterScreen {
            header(title: CosignCopy.YubiKey.connectChromeTitle)

            VStack(alignment: .leading, spacing: 8) {
                Text(CosignCopy.YubiKey.tapEyebrow.uppercased())
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(CosignTheme.inkFaint)
                Text(CosignCopy.YubiKey.tapTitle)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
                Text(CosignCopy.YubiKey.tapSubtitle)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.inkDim)
            }

            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.YubiKey.labelFieldTitle)
                CosignCard {
                    TextField(CosignCopy.YubiKey.defaultLabel, text: $label)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .cosignField()
                }
            }

            VStack(spacing: 16) {
                YubiKeyHaloView(pulses: transport == .nfc)
                YubiKeyStatusPill(
                    text: transport == .nfc ? CosignCopy.YubiKey.listeningNFC : CosignCopy.YubiKey.listeningWired
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            Button(transport == .nfc ? CosignCopy.YubiKey.useWiredButton : CosignCopy.YubiKey.useNFCButton) {
                transport = transport == .nfc ? .wired : .nfc
            }
            .buttonStyle(CosignButtonStyle(kind: .secondary))
            .accessibilityIdentifier("yubikey-toggle-transport")
        } footer: {
            Button(CosignCopy.YubiKey.continueButton) {
                beginPINEntry()
            }
            .buttonStyle(CosignButtonStyle(kind: .accent))
            .disabled(trimmedLabel.isEmpty)
            .accessibilityIdentifier("yubikey-continue")
        }
    }

    var pinStep: some View {
        CosignAnchoredFooterScreen {
            header(title: CosignCopy.YubiKey.connectChromeTitle)

            VStack(alignment: .leading, spacing: 8) {
                Text(CosignCopy.YubiKey.pinEyebrow.uppercased())
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(CosignTheme.inkFaint)
                Text(CosignCopy.YubiKey.pinTitle)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
                Text(CosignCopy.YubiKey.pinAttemptsRemaining(pinAttemptsRemaining))
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkDim)
            }

            YubiKeyPINDots(count: pin.count)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

            YubiKeyPINPad(pin: $pin)
        } footer: {
            Button(CosignCopy.YubiKey.continueButton) {
                submitPIN()
            }
            .buttonStyle(CosignButtonStyle(kind: .accent))
            .disabled(!hasValidPIN)
            .accessibilityIdentifier("yubikey-pin-continue")
        }
    }

    var touchStep: some View {
        CosignScreen {
            header(title: CosignCopy.YubiKey.confirmChromeTitle)

            VStack(alignment: .leading, spacing: 8) {
                Text(CosignCopy.YubiKey.touchEyebrow.uppercased())
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(CosignTheme.inkFaint)
                Text(CosignCopy.YubiKey.touchTitle)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
                Text(CosignCopy.YubiKey.touchSubtitle)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.inkDim)
            }

            VStack(spacing: 16) {
                YubiKeyHaloView(pulses: true)
                YubiKeyStatusPill(text: CosignCopy.YubiKey.waitingForTouch)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
    }

    var readyStep: some View {
        CosignAnchoredFooterScreen {
            header(title: CosignCopy.YubiKey.connectChromeTitle)

            VStack(spacing: 18) {
                CosignGlyphView(glyph: .check, size: 30, color: CosignTheme.mint)
                    .frame(width: 72, height: 72)
                    .background(CosignTheme.mintWash, in: .circle)
                    .overlay { Circle().stroke(CosignTheme.mint.opacity(0.40), lineWidth: 1) }

                VStack(spacing: 8) {
                    Text(CosignCopy.YubiKey.readyTitle)
                        .font(CosignTheme.FontStyle.display)
                        .foregroundStyle(CosignTheme.ink)
                    Text(CosignCopy.YubiKey.readySubtitle)
                        .font(CosignTheme.FontStyle.body)
                        .foregroundStyle(CosignTheme.inkDim)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            YubiKeySignerSummaryCard(name: trimmedLabel, address: addedAddress ?? "")
        } footer: {
            Button(CosignCopy.YubiKey.doneButtonTitle) {
                dismiss()
            }
            .buttonStyle(CosignButtonStyle(kind: .primary))
            .accessibilityIdentifier("yubikey-done")
        }
    }

    var recoveryStep: some View {
        CosignScreen {
            header(title: CosignCopy.YubiKey.connectChromeTitle)
            if let recovery {
                YubiKeyRecoveryCard(recovery: recovery) {
                    Task { await performRecovery(recovery) }
                }
            }
        }
    }
}
