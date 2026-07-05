import Indexer
import Squads
import SwiftUI

public struct SquadsListView: View {
    @Environment(Coordinator.self) private var coordinator
    @Environment(\.indexerEnvironment) private var indexerEnvironment
    @Environment(\.squadsService) private var squadsService

    private let memberAddress: String

    @State private var squads = [SquadSummary]()
    @State private var isLoading = false
    @State private var errorMessage: String?

    public init(memberAddress: String) {
        self.memberAddress = memberAddress
    }

    public var body: some View {
        CosignScreen {
            VStack(alignment: .leading, spacing: 8) {
                CosignSectionTitle(title: CosignCopy.Squads.memberSection)
                Text(CosignCopy.Squads.screenTitle)
                    .font(CosignTheme.FontStyle.displayL)
                    .foregroundStyle(CosignTheme.ink)
            }

            CosignCard {
                CosignAddressBlock(
                    title: CosignCopy.Squads.memberSection,
                    address: memberAddress,
                    accessibilityLabel: CosignCopy.Squads.copyMemberAddress
                )
            }

            if isLoading, squads.isEmpty {
                CosignLoadingCard()
            } else if let errorMessage {
                CosignEmptyState(
                    title: CosignCopy.Squads.unableToLoadSquadsTitle,
                    systemImage: "exclamationmark.triangle",
                    message: errorMessage
                )
            } else if squads.isEmpty {
                CosignEmptyState(
                    key: .emptySquads,
                    primaryActionTitle: CosignCopy.CreateSquad.entryTitle,
                    primaryActionIdentifier: "squads-empty-create-cta",
                    secondaryActionTitle: CosignCopy.CreateSquad.copyAddress,
                    primaryAction: {
                        coordinator.go(to: .createSquad(memberAddress: memberAddress))
                    },
                    secondaryAction: {
                        copyToPasteboard(memberAddress)
                    }
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        CosignSectionTitle(title: CosignCopy.Squads.sectionTitle)
                        Spacer()
                        CosignIconButton(glyph: .plus) {
                            coordinator.go(to: .createSquad(memberAddress: memberAddress))
                        }
                        .accessibilityIdentifier("squads-create-cta")
                        .accessibilityLabel(CosignCopy.CreateSquad.entryTitle)
                    }
                    ForEach(squads) { squad in
                        CosignObjectRowButton {
                            coordinator.go(to: .squadDetail(squad.address))
                        } label: {
                            SquadSummaryRow(squad: squad)
                        }
                    }
                }
            }
        }
        .navigationTitle(CosignCopy.Squads.screenTitle)
        .cosignPage()
        .refreshable {
            await load(forceRefresh: true)
        }
        .task(id: memberAddress) {
            await load()
        }
        .pollingRefresh(
            id: "squads-\(memberAddress)",
            interval: ReadPollingInterval.list,
            enabled: !memberAddress.isEmpty
        ) {
            await load(forceRefresh: true, showsLoading: false)
        }
        .webSocketRefresh(
            id: "squads-\(memberAddress)",
            webSocketURL: indexerEnvironment.effectiveWebSocketURL,
            accounts: squads.map(\.address),
            enabled: !squads.isEmpty
        ) {
            await load(forceRefresh: true, showsLoading: false)
        }
    }

    @MainActor
    private func load(forceRefresh: Bool = false, showsLoading: Bool = true) async {
        guard !memberAddress.isEmpty else {
            errorMessage = CosignCopy.Squads.emptySignerAddressMessage
            squads = []
            return
        }

        if showsLoading {
            isLoading = true
        }
        if squads.isEmpty || showsLoading {
            errorMessage = nil
        }
        defer {
            if showsLoading {
                isLoading = false
            }
        }

        do {
            squads = if forceRefresh {
                try await squadsService.refreshSquads(forMember: memberAddress)
            } else {
                try await squadsService.squads(forMember: memberAddress)
            }
            errorMessage = nil
        } catch {
            if squads.isEmpty {
                errorMessage = String(describing: error)
            }
        }
    }
}

private struct SquadSummaryRow: View {
    let squad: SquadSummary

    var body: some View {
        CosignObjectRow(
            title: squad.displayName ?? shortAddress(squad.address),
            subtitle: CosignCopy.Squads.transactionSummary(
                transactionIndex: squad.transactionIndex,
                staleTransactionIndex: squad.staleTransactionIndex
            ),
            metadata: squad.address,
            copyValue: squad.address,
            copyAccessibilityLabel: CosignCopy.Squads.copySquadAddress,
            accessory: {
                Text(CosignCopy.Squads.threshold(squad.threshold, memberCount: squad.memberCount))
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.inkDim)
                    .monospacedDigit()
            }
        )
    }
}

private func shortAddress(_ address: String) -> String {
    guard address.count > 12 else {
        return address
    }
    return "\(address.prefix(4))...\(address.suffix(4))"
}
