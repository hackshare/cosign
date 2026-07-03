import Persistence
import SwiftUI

extension SignerDetailView {
    func backupSection(_ signer: RegisteredSigner) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: signer.importedWithoutPhrase
                ? CosignCopy.SignerDetail.keySourceSectionTitle
                : CosignCopy.SignerDetail.backupSectionTitle)
            CosignCard(padding: 0) {
                VStack(spacing: 0) {
                    if signer.importedWithoutPhrase {
                        importedKeyRow
                    } else {
                        backupStatusRow(signer)
                    }
                    if signer.keychainItemRef != nil {
                        Divider()
                            .overlay(CosignTheme.line)
                            .padding(.leading, 14)
                        if signer.importedWithoutPhrase {
                            revealSecretKeyRow
                        } else {
                            revealRow
                        }
                    }
                }
            }
        }
    }

    private var importedKeyRow: some View {
        HStack(spacing: 12) {
            iconSquare(background: CosignTheme.surface2) {
                CosignGlyphView(glyph: .key, size: 15, color: CosignTheme.inkDim)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(CosignCopy.SignerDetail.importedKeyRowTitle)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.ink)
                Text(CosignCopy.SignerDetail.importedKeyRowDetail)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }

    private var revealSecretKeyRow: some View {
        Button {
            showingReveal = true
        } label: {
            HStack(spacing: 12) {
                iconSquare(background: CosignTheme.surface2) {
                    CosignGlyphView(glyph: .lock, size: 15, color: CosignTheme.inkDim)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(CosignCopy.SignerDetail.revealSecretKeyRowTitle)
                        .font(CosignTheme.FontStyle.body)
                        .foregroundStyle(CosignTheme.ink)
                    Text(CosignCopy.SignerDetail.revealRowDetail)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkFaint)
                }
                Spacer(minLength: 0)
                CosignGlyphView(glyph: .chevronRight, size: 14, color: CosignTheme.inkFaint)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("signer-detail-reveal-secret-key")
    }

    private func backupStatusRow(_ signer: RegisteredSigner) -> some View {
        HStack(spacing: 12) {
            statusGlyph(backedUp: signer.backedUp)
            VStack(alignment: .leading, spacing: 1) {
                Text(signer.backedUp
                    ? CosignCopy.SignerDetail.backedUpRowTitle
                    : CosignCopy.SignerDetail.notBackedUpRowTitle)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.ink)
                Text(statusDetail(signer))
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }

    private var revealRow: some View {
        Button {
            showingReveal = true
        } label: {
            HStack(spacing: 12) {
                iconSquare(background: CosignTheme.surface2) {
                    CosignGlyphView(glyph: .lock, size: 15, color: CosignTheme.inkDim)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(CosignCopy.SignerDetail.revealRowTitle)
                        .font(CosignTheme.FontStyle.body)
                        .foregroundStyle(CosignTheme.ink)
                    Text(CosignCopy.SignerDetail.revealRowDetail)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkFaint)
                }
                Spacer(minLength: 0)
                CosignGlyphView(glyph: .chevronRight, size: 14, color: CosignTheme.inkFaint)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("signer-detail-reveal-phrase")
    }

    private func statusGlyph(backedUp: Bool) -> some View {
        iconSquare(background: backedUp ? CosignTheme.mintWash : CosignTheme.riskRed.opacity(0.10)) {
            CosignGlyphView(
                glyph: backedUp ? .check : .warning,
                size: 15,
                color: backedUp ? CosignTheme.mint : CosignTheme.riskRed
            )
        }
    }

    private func iconSquare(background: Color, @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: 32, height: 32)
            .background(background, in: .rect(cornerRadius: 9))
    }

    private func statusDetail(_ signer: RegisteredSigner) -> String {
        guard signer.backedUp else {
            return CosignCopy.SignerDetail.notBackedUpRowDetail
        }
        if let date = signer.backedUpAt {
            return CosignCopy.SignerDetail.backedUpRowDetail(date: date)
        }
        return CosignCopy.SignerDetail.backedUpRowDetailPlain
    }
}
