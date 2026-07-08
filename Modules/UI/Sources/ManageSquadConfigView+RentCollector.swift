import Squads
import SwiftUI

extension ManageSquadConfigView {
    // MARK: - Rent collector section

    func rentCollectorSection(_ detail: SquadDetail) -> some View {
        let isChanged = rentCollector != detail.rentCollector
        let currentDisplay = detail.rentCollector
            .map { cosignShortAddress($0, prefix: 4, suffix: 4) } ?? CosignCopy.SquadDetail.none
        return VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.ManageSquad.rentCollectorSection)
            CosignCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(CosignCopy.ManageSquad.rentCollectorSubtitle)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                    Text(CosignCopy.ManageSquad.rentCollectorCurrent(currentDisplay))
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)

                    if let collector = rentCollector {
                        rentCollectorCard(collector, isChanged: isChanged)
                    } else {
                        rentCollectorEditorRow
                    }

                    if isChanged {
                        let oldDisplay = currentDisplay
                        let newDisplay = rentCollector
                            .map { cosignShortAddress($0, prefix: 4, suffix: 4) } ?? CosignCopy.SquadDetail.none
                        Text(CosignCopy.ManageSquad.rentCollectorDiff(old: oldDisplay, new: newDisplay))
                            .font(CosignTheme.FontStyle.caption)
                            .foregroundStyle(CosignTheme.mint)
                            .accessibilityIdentifier("manage-squad-rent-diff")
                    }
                }
            }
        }
    }

    private func rentCollectorCard(_ collector: String, isChanged: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(cosignShortAddress(collector))
                        .font(CosignTheme.FontStyle.titleM)
                        .foregroundStyle(CosignTheme.ink)
                    if isChanged {
                        memberBadge(
                            CosignCopy.ManageSquad.changedBadge,
                            foreground: CosignTheme.mint,
                            background: CosignTheme.mintWash
                        )
                    }
                }
                Text(cosignShortAddress(collector, prefix: 6, suffix: 6))
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkDim)
            }
            Spacer()
            Button {
                clearRentCollector()
            } label: {
                CosignGlyphView(glyph: .xmark, size: 14, color: CosignTheme.inkDim)
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .disabled(isCreating)
            .accessibilityIdentifier("manage-squad-rent-clear")
        }
    }

    private var rentCollectorEditorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(CosignCopy.ManageSquad.rentCollectorPlaceholder, text: $rentCollectorInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { setRentCollector() }
                .cosignField()
                .accessibilityIdentifier("manage-squad-rent-field")
            if let err = rentCollectorError {
                CosignInlineBanner(tone: .red) {
                    Text(err)
                }
            }
            Button {
                setRentCollector()
            } label: {
                Text(CosignCopy.ManageSquad.rentCollectorSet)
            }
            .buttonStyle(CosignButtonStyle(kind: .secondary))
            .disabled(isCreating)
            .accessibilityIdentifier("manage-squad-rent-set")
            Text(CosignCopy.ManageSquad.rentCollectorHint)
                .font(CosignTheme.FontStyle.caption)
                .foregroundStyle(CosignTheme.inkFaint)
        }
    }
}
