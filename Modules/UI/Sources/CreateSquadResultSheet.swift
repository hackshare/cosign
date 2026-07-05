import Squads
import SwiftUI

struct CreateSquadResultSheet: View {
    let result: SquadCreationResult
    let threshold: Int
    let memberCount: Int
    let explorerURL: URL?
    let onOpenSquad: () -> Void

    var body: some View {
        CosignScreen {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(CosignCopy.CreateSquad.successTitle)
                        .font(CosignTheme.FontStyle.display)
                        .foregroundStyle(CosignTheme.ink)
                    Text(CosignCopy.CreateSquad.successBody)
                        .font(CosignTheme.FontStyle.body)
                        .foregroundStyle(CosignTheme.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                CosignCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(CosignCopy.CreateSquad.resultSquadLabel)
                                    .font(CosignTheme.FontStyle.titleM)
                                    .foregroundStyle(CosignTheme.ink)
                                Text(cosignShortAddress(result.multisigAddress))
                                    .font(CosignTheme.FontStyle.monoSmall)
                                    .foregroundStyle(CosignTheme.inkDim)
                            }
                            Spacer()
                            Text(CosignCopy.CreateSquad.resultThreshold(threshold, of: memberCount))
                                .font(CosignTheme.FontStyle.titleM)
                                .foregroundStyle(CosignTheme.mint)
                        }
                        Divider()
                            .overlay(CosignTheme.line)
                        HStack {
                            Text(CosignCopy.CreateSquad.resultMembersLabel)
                                .font(CosignTheme.FontStyle.body)
                                .foregroundStyle(CosignTheme.inkDim)
                            Spacer()
                            Text(CosignCopy.CreateSquad.resultMembersValue(memberCount))
                                .font(CosignTheme.FontStyle.body)
                                .foregroundStyle(CosignTheme.ink)
                        }
                    }
                }

                Button {
                    onOpenSquad()
                } label: {
                    Text(CosignCopy.CreateSquad.openSquad)
                }
                .buttonStyle(CosignButtonStyle(kind: .accent))

                if let explorerURL {
                    Link(CosignCopy.CreateSquad.viewOnExplorer, destination: explorerURL)
                        .font(CosignTheme.FontStyle.body)
                        .foregroundStyle(CosignTheme.accentDeep)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .cosignPage()
    }
}
