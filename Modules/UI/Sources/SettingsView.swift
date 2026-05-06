import SwiftUI

public struct SettingsView: View {
    public init() {}

    public var body: some View {
        CosignScreen {
            VStack(alignment: .leading, spacing: 8) {
                CosignSectionTitle(title: CosignCopy.Settings.sectionTitle)
                Text(CosignCopy.Settings.screenTitle)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
            }

            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.Settings.accountSection)
                CosignCard {
                    CosignObjectNavigationLink(value: Route.signers) {
                        CosignNavigationRow(
                            title: CosignCopy.Settings.signersTitle,
                            subtitle: CosignCopy.Settings.signersSubtitle,
                            systemImage: "key.horizontal"
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.Settings.networkSection)
                CosignCard {
                    CosignObjectNavigationLink(value: Route.networkSettings) {
                        CosignNavigationRow(
                            title: CosignCopy.Settings.rpcEndpointTitle,
                            subtitle: CosignCopy.Settings.rpcEndpointSubtitle,
                            systemImage: "network"
                        )
                    }
                }
            }
        }
        .navigationTitle(CosignCopy.Settings.sectionTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
