import SwiftUI

extension CreateSquadView {
    var wizardFooter: some View {
        CosignStickyFooter {
            HStack(spacing: 12) {
                if step.previous != nil {
                    Button {
                        withAnimation { step = step.previous! }
                    } label: {
                        HStack {
                            CosignGlyphView(glyph: .chevronLeft, size: 14, color: CosignTheme.ink)
                            Text(CosignCopy.Common.back)
                        }
                    }
                    .buttonStyle(CosignButtonStyle(kind: .secondary))
                }

                if let next = step.next {
                    Button {
                        withAnimation { step = next }
                    } label: {
                        HStack {
                            Text(CosignCopy.ProposalCreation.nextButton)
                            CosignGlyphView(
                                glyph: .chevronRight,
                                size: 14,
                                color: canAdvance ? CosignTheme.accentInk : CosignTheme.inkFaint
                            )
                        }
                    }
                    .disabled(!canAdvance)
                    .buttonStyle(CosignButtonStyle(kind: canAdvance ? .accent : .secondary))
                } else if demoMode?.disablesNetworkWrites == true {
                    Button {} label: {
                        HStack(spacing: 8) {
                            CosignGlyphView(glyph: .lock, size: 14, color: CosignTheme.inkFaint)
                            Text(CosignCopy.CreateSquad.unavailableInDemo)
                        }
                    }
                    .disabled(true)
                    .buttonStyle(CosignButtonStyle(kind: .secondary))
                } else {
                    Button {
                        Task { await create() }
                    } label: {
                        if isCreating {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(CosignTheme.accentInk)
                                Text(CosignCopy.CreateSquad.creating)
                            }
                        } else {
                            Text(CosignCopy.CreateSquad.createButton)
                        }
                    }
                    .disabled(isCreating)
                    .buttonStyle(CosignButtonStyle(kind: .accent))
                }
            }
        }
    }

    var canAdvance: Bool {
        switch step {
        case .funding:
            isFunded
        case .members, .threshold, .review:
            true
        }
    }
}
