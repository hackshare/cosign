import SwiftUI

struct ProposalSigningFooter: View {
    let usesHoldConfirmation: Bool
    let holdButtonTitle: String
    let holdHelpText: String
    let signButtonTitle: String
    let signButtonKind: CosignButtonKind
    let isSubmitting: Bool
    let canConfirm: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if usesHoldConfirmation {
                CosignHoldActionButton(
                    title: holdButtonTitle,
                    glyph: .lock,
                    kind: signButtonKind,
                    isLoading: isSubmitting,
                    isDisabled: !canConfirm,
                    onCommit: onConfirm
                )
                .accessibilityIdentifier("proposal-signing-hold-button")
                Text(holdHelpText)
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            } else {
                Button {
                    onConfirm()
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(signButtonTitle)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(CosignButtonStyle(kind: signButtonKind))
                .disabled(!canConfirm)
                .opacity(canConfirm ? 1 : 0.5)
            }

            Button(CosignCopy.Common.cancel, action: onCancel)
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.inkFaint)
                .buttonStyle(.plain)
                .disabled(isSubmitting)
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 132, alignment: .top)
        .background(CosignTheme.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(CosignTheme.line)
                .frame(height: 1)
        }
    }
}
