import Signers
import SwiftUI

enum YubiKeyTransportChoice: String, CaseIterable, Identifiable {
    case wired
    case nfc

    var id: Self {
        self
    }

    var label: String {
        switch self {
        case .wired:
            CosignCopy.YubiKeySigning.pluggedInTransportTitle
        case .nfc:
            CosignCopy.YubiKeySigning.tapTransportTitle
        }
    }

    var statusLabel: String {
        switch self {
        case .wired:
            CosignCopy.YubiKeySigning.pluggedInTransportStatus
        case .nfc:
            CosignCopy.YubiKeySigning.nfcTransportStatus
        }
    }

    func connectionPreference(alertMessage: String) -> YubiKeyConnectionPreference {
        switch self {
        case .wired:
            .wired
        case .nfc:
            .nfc(alertMessage: alertMessage)
        }
    }
}

struct YubiKeySigningOptions: Equatable {
    var pin = ""
    var transport: YubiKeyTransportChoice = .wired

    var trimmedPIN: String {
        pin.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasValidPINLength: Bool {
        (6 ... 8).contains(trimmedPIN.utf8.count)
    }
}

struct YubiKeySigningControls: View {
    @Binding var options: YubiKeySigningOptions
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.YubiKeySigning.sectionTitle)
            CosignCard {
                YubiKeyTransportSelector(selection: $options.transport, isDisabled: isDisabled)

                SecureField(CosignCopy.YubiKeySigning.pinPlaceholder, text: $options.pin)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .disabled(isDisabled)

                if !options.pin.isEmpty, !options.hasValidPINLength {
                    Text(CosignCopy.YubiKeySigning.pinLengthMessage)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.riskRed)
                }
            }
        }
    }
}

struct YubiKeyTransportSelector: View {
    @Binding var selection: YubiKeyTransportChoice
    var isDisabled = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(YubiKeyTransportChoice.allCases) { transport in
                Button {
                    selection = transport
                } label: {
                    transportOption(transport)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
        }
    }

    private func transportOption(_ transport: YubiKeyTransportChoice) -> some View {
        let isSelected = selection == transport

        return HStack(spacing: 8) {
            CosignGlyphView(
                glyph: transport.glyph,
                size: 15,
                color: isSelected ? CosignTheme.accentDeep : CosignTheme.inkFaint
            )
            Text(transport.label)
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(isSelected ? CosignTheme.ink : CosignTheme.inkDim)
                .lineLimit(1)
            Spacer(minLength: 0)
            if isSelected {
                CosignGlyphView(glyph: .check, size: 14, color: CosignTheme.accentDeep)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            isSelected ? CosignTheme.accentWash : CosignTheme.surface2,
            in: .rect(cornerRadius: CosignTheme.Radius.medium)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CosignTheme.Radius.medium)
                .stroke(isSelected ? CosignTheme.accent.opacity(0.65) : CosignTheme.line, lineWidth: 1)
        }
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private extension YubiKeyTransportChoice {
    var glyph: CosignGlyph {
        switch self {
        case .wired:
            .key
        case .nfc:
            .wave
        }
    }
}
