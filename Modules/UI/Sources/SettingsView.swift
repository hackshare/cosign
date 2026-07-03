import Indexer
import Provenance
import SwiftUI

public struct SettingsView: View {
    @Environment(Coordinator.self) private var coordinator
    @Environment(NetworkSettingsStore.self) private var networkSettings

    @State private var buildState: BuildProvenanceState?

    public init() {}

    public var body: some View {
        CosignScreen {
            CosignCompactPageHeader(title: CosignCopy.Settings.sectionTitle) { coordinator.pop() }

            VStack(alignment: .leading, spacing: 8) {
                CosignSectionTitle(title: CosignCopy.Settings.sectionTitle)
                Text(CosignCopy.Settings.screenTitle)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
            }

            section(CosignCopy.Settings.connectionSection) {
                navigationCard(value: Route.networkSettings, identifier: "settings-network-row") {
                    CosignNavigationRow(
                        title: CosignCopy.Settings.networkTitle,
                        subtitle: CosignCopy.Settings.networkSubtitle,
                        systemImage: "network"
                    ) {
                        StatusTrailing(text: networkStatusText, tone: networkStatusTone)
                    }
                }
                navigationCard(value: Route.buildVerification) {
                    CosignNavigationRow(
                        title: CosignCopy.Settings.buildVerificationTitle,
                        subtitle: CosignCopy.Settings.buildVerificationSubtitle,
                        systemImage: "checkmark.seal"
                    ) {
                        if let buildState {
                            StatusTrailing(
                                text: CosignCopy.Settings.buildStatus(for: buildState),
                                tone: buildStatusTone(for: buildState)
                            )
                        }
                    }
                }
            }

            section(CosignCopy.Settings.aboutSection) {
                navigationCard(value: Route.aboutCosign, identifier: "settings-about-row") {
                    CosignNavigationRow(
                        title: CosignCopy.Settings.aboutTitle,
                        subtitle: CosignCopy.Settings.aboutSubtitle,
                        systemImage: "doc.text"
                    )
                }
            }
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .cosignScreenIdentifier("screen.settings")
        .cosignPage()
        .task {
            buildState = BuildClaimVerifier.provenanceState()
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: title)
            content()
        }
    }

    private func navigationCard(
        value: Route,
        identifier: String? = nil,
        @ViewBuilder row: @escaping () -> some View
    ) -> some View {
        CosignCard {
            CosignObjectNavigationLink(value: value, content: row)
                .accessibilityIdentifier(identifier ?? "")
        }
    }

    private var networkStatusText: String {
        CosignCopy.Settings.networkStatus(for: networkSettings.networkHealth.status)
    }

    private var networkStatusTone: Color {
        switch networkSettings.networkHealth.status {
        case .healthy:
            CosignTheme.mint
        case .webSocketDown:
            CosignTheme.riskAmber
        case .offline:
            CosignTheme.riskRed
        }
    }

    private func buildStatusTone(for state: BuildProvenanceState) -> Color {
        switch state {
        case .verified:
            CosignTheme.mint
        case .developmentBuild:
            CosignTheme.inkFaint
        case .failed:
            CosignTheme.riskRed
        }
    }
}

private struct StatusTrailing: View {
    let text: String
    let tone: Color

    var body: some View {
        Text(text)
            .font(CosignTheme.FontStyle.caption)
            .foregroundStyle(tone)
    }
}
