import Indexer
import SwiftUI

public struct NetworkSettingsView: View {
    @Environment(NetworkSettingsStore.self) private var networkSettings
    @Environment(Coordinator.self) private var coordinator

    public init() {}

    public var body: some View {
        CosignScreen {
            CosignCompactPageHeader(title: CosignCopy.Network.screenTitle) { coordinator.pop() }

            VStack(alignment: .leading, spacing: 8) {
                CosignSectionTitle(title: CosignCopy.Network.screenEyebrow)
                Text(CosignCopy.Network.screenTitle)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
            }

            RelayConnectionStatusBlock(status: status) {
                networkSettings.networkHealth.retry()
            }

            relayCard

            connectionStatesLegend

            advancedRow
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .cosignScreenIdentifier("screen.network-settings")
        .cosignPage()
    }

    private var status: NetworkHealthStatus {
        networkSettings.networkHealth.status
    }

    private var relayCard: some View {
        CosignCard {
            HStack(alignment: .firstTextBaseline) {
                Text(CosignCopy.Network.relayCardTitle)
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(CosignTheme.ink)
                Spacer(minLength: 8)
                CosignPinnedTag()
            }
            VStack(spacing: 0) {
                CosignKeyValueRow(
                    label: CosignCopy.Network.clusterLabel,
                    value: CosignCopy.Network.relayClusterName(environmentName)
                )
                CosignKeyValueRow(
                    label: CosignCopy.Network.hostLabel,
                    value: networkSettings.rpcURLInfo.host,
                    isLast: true
                )
            }
            .padding(.top, 6)
        }
    }

    private var connectionStatesLegend: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.Network.connectionStatesSection)
            CosignCard {
                VStack(alignment: .leading, spacing: 12) {
                    ConnectionStateLegendRow(
                        tone: CosignTheme.mint,
                        name: CosignCopy.Network.connectedStateName,
                        detail: CosignCopy.Network.connectedStateDetail
                    )
                    ConnectionStateLegendRow(
                        tone: CosignTheme.riskAmber,
                        name: CosignCopy.Network.pausedStateName,
                        detail: CosignCopy.Network.pausedStateDetail
                    )
                    ConnectionStateLegendRow(
                        tone: CosignTheme.riskRed,
                        name: CosignCopy.Network.offlineStateName,
                        detail: CosignCopy.Network.offlineStateDetail
                    )
                }
            }
        }
    }

    private var advancedRow: some View {
        CosignCard {
            CosignObjectNavigationLink(value: Route.selfHostedRelay) {
                CosignNavigationRow(
                    title: CosignCopy.Network.selfHostedRowTitle,
                    subtitle: CosignCopy.Network.selfHostedRowSubtitle,
                    systemImage: "network"
                )
            }
            .accessibilityIdentifier("network-self-hosted-row")
        }
    }

    private var environmentName: String {
        CosignBuildEnvironment.current().environmentName
    }
}

struct RelayConnectionStatusBlock: View {
    let status: NetworkHealthStatus
    let onRetry: () -> Void

    var body: some View {
        CosignCard {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(tone)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(CosignCopy.Network.statusTitle(for: status))
                        .font(CosignTheme.FontStyle.titleM)
                        .foregroundStyle(CosignTheme.ink)
                    Text(CosignCopy.Network.statusDetail(for: status))
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                }
                Spacer(minLength: 8)
                if status == .offline {
                    Button(CosignCopy.Network.retryButton, action: onRetry)
                        .buttonStyle(CosignButtonStyle(kind: .secondary, fillsWidth: false, height: 36))
                }
            }
        }
    }

    private var tone: Color {
        switch status {
        case .healthy:
            CosignTheme.mint
        case .webSocketDown:
            CosignTheme.riskAmber
        case .offline:
            CosignTheme.riskRed
        }
    }
}

struct CosignPinnedTag: View {
    var body: some View {
        Text(CosignCopy.Network.pinnedTag)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(CosignTheme.mint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(CosignTheme.mint.opacity(0.12), in: .capsule)
            .overlay {
                Capsule().stroke(CosignTheme.mint.opacity(0.24), lineWidth: 1)
            }
    }
}

struct ConnectionStateLegendRow: View {
    let tone: Color
    let name: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tone)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.ink)
                Text(detail)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkDim)
            }
            Spacer(minLength: 0)
        }
    }
}
