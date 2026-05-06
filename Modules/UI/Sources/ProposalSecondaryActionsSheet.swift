import Squads
import SwiftUI

struct ProposalSecondaryActionsSheet: View {
    let actions: [SquadProposalAction]
    let isSubmittingAction: Bool
    let onCancel: () -> Void
    let onSelectAction: (SquadProposalAction) -> Void

    var body: some View {
        CosignScreen {
            header

            CosignCard {
                VStack(spacing: 10) {
                    ForEach(actions) { action in
                        Button {
                            onSelectAction(action)
                        } label: {
                            ProposalActionButtonLabel(action: action, showsFinalSignerNote: false)
                        }
                        .buttonStyle(CosignButtonStyle(kind: buttonKind(for: action)))
                        .disabled(isSubmittingAction)
                        .accessibilityIdentifier("proposal-secondary-action-\(action.rawValue)")
                    }
                }
            }
        }
        .presentationDetents([.height(sheetHeight), .medium])
        .presentationDragIndicator(.hidden)
        .cosignScreenIdentifier("screen.proposal-secondary-actions")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule()
                .fill(CosignTheme.inkGhost)
                .frame(width: 42, height: 4)
                .frame(maxWidth: .infinity)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(CosignCopy.ProposalActions.secondaryActionsTitle)
                        .font(CosignTheme.FontStyle.display)
                        .foregroundStyle(CosignTheme.ink)
                    Text(CosignCopy.ProposalActions.secondaryActionsSubtitle)
                        .font(CosignTheme.FontStyle.body)
                        .foregroundStyle(CosignTheme.inkDim)
                }
                Spacer(minLength: 12)
                CosignGlyphButton(glyph: .xmark, accessibilityLabel: CosignCopy.Common.cancel) {
                    onCancel()
                }
            }
        }
    }

    private var sheetHeight: CGFloat {
        CGFloat(190 + actions.count * 58)
    }

    private func buttonKind(for action: SquadProposalAction) -> CosignButtonKind {
        switch action {
        case .cancel:
            .destructive
        case .approve, .approveAndExecute, .execute, .reject:
            .secondary
        }
    }
}
