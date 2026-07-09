import Core
import CosignCore
import Indexer
import Persistence
import Squads
import SwiftData
import SwiftUI

public struct SignerHomeView: View {
    @Environment(Coordinator.self) var coordinator
    @Environment(\.cosignDemoMode) var demoMode
    @Environment(\.indexerEnvironment) var indexerEnvironment
    @Environment(\.squadsService) var squadsService
    @Environment(NetworkHealth.self) var networkHealth: NetworkHealth?
    @Query(sort: \RegisteredSigner.createdAt, order: .forward)
    private var signers: [RegisteredSigner]

    private let signerID: UUID

    @State var squadRows = [SignerHomeSquadRow]()
    @State var recentActivity = [SquadActivityItem]()
    @State var isLoading = true
    @State var errorMessage: String?

    public init(signerID: UUID) {
        self.signerID = signerID
    }

    public var body: some View {
        Group {
            if let signer {
                signerHome(signer)
            } else {
                CosignScreen {
                    CosignEmptyState(
                        title: CosignCopy.Signers.signerNotFoundTitle,
                        systemImage: "key.slash",
                        message: CosignCopy.Signers.signerNotFoundMessage
                    )
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .cosignPage()
    }

    private var signer: RegisteredSigner? {
        signers.first { $0.id == signerID }
    }

    private func signerHome(_ signer: RegisteredSigner) -> some View {
        let address = CosignCore.base58(signer.pubkey)

        return CosignScreen {
            navigationHeader(for: signer)
            identitySummary(for: signer, address: address)

            if openProposalCount > 0 {
                pendingStrip
            }

            squadsSection(memberAddress: address)
            recentActivitySection
            if !squadRows.isEmpty {
                networkFooter
            }
        }
        .refreshable {
            await load(memberAddress: address, forceRefresh: true)
        }
        .task(id: address) {
            await load(memberAddress: address)
        }
        .pollingRefresh(
            id: "signer-home-\(address)",
            interval: ReadPollingInterval.list,
            enabled: !address.isEmpty
        ) {
            await load(memberAddress: address, forceRefresh: true, showsLoading: false)
        }
        .webSocketRefresh(
            id: "signer-home-\(address)",
            webSocketURL: indexerEnvironment.effectiveWebSocketURL,
            accounts: squadRows.map(\.summary.address),
            enabled: !squadRows.isEmpty
        ) {
            await load(memberAddress: address, forceRefresh: true, showsLoading: false)
        }
        .accessibilityIdentifier("screen.signer-home")
    }

    private func navigationHeader(for signer: RegisteredSigner) -> some View {
        CosignCompactPageHeader(title: signer.label) {
            coordinator.pop()
        } accessory: {
            CosignPlainGlyphButton(
                glyph: .settings,
                accessibilityLabel: CosignCopy.Signers.signerSettingsAccessibilityLabel
            ) {
                coordinator.go(to: .signerDetail(signer.id))
            }
        }
    }

    private func identitySummary(for signer: RegisteredSigner, address: String) -> some View {
        let tallyCount = SigningTally.count(for: address)
        return HStack(alignment: .center, spacing: 12) {
            signerAvatar(for: signer.type)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(signer.label)
                        .font(CosignTheme.FontStyle.display)
                        .foregroundStyle(CosignTheme.ink)
                        .lineLimit(1)

                    Text(keyKind(for: signer.type))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(CosignTheme.inkDim)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 7)
                        .background(CosignTheme.surface2, in: .capsule)
                }

                CosignAddressText(
                    address: address,
                    displayAddress: cosignShortAddress(address),
                    size: 12,
                    color: CosignTheme.inkFaint
                )

                HStack(spacing: 6) {
                    Text(statusHint(for: signer.type))
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)

                    if tallyCount > 0 {
                        Text(CosignCopy.SignerHome.signedHere(tallyCount))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(CosignTheme.mint)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 7)
                            .background(CosignTheme.mintWash, in: .capsule)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pendingStrip: some View {
        let label = CosignCopy.Signers.openProposalsTitle(count: openProposalCount)

        return Button {
            if let first = squadRows.first(where: { $0.openProposalCount > 0 }) {
                coordinator.go(to: .proposals(
                    squad: first.summary.address,
                    latestIndex: first.summary.transactionIndex
                ))
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(CosignTheme.accent)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(CosignTheme.FontStyle.titleM)
                        .foregroundStyle(CosignTheme.ink)
                    Text(CosignCopy.Signers.pendingSquadsSubtitle)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                }

                Spacer()
                CosignGlyphView(glyph: .chevronRight, size: 15, color: CosignTheme.inkGhost)
            }
            .padding(14)
            .background(CosignTheme.accentWash, in: .rect(cornerRadius: CosignTheme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: CosignTheme.Radius.card)
                    .stroke(CosignTheme.accent.opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func squadsSection(memberAddress: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CosignSectionTitle(
                    title: CosignCopy.Signers.memberOfSquadsTitle(count: squadRows.count),
                    trailing: openProposalCount > 0 ? CosignCopy.Signers.pendingColumnTitle : nil
                )
                if !squadRows.isEmpty {
                    CosignIconButton(glyph: .plus) {
                        coordinator.go(to: .createSquad(memberAddress: memberAddress))
                    }
                    .accessibilityIdentifier("squads-create-cta")
                    .accessibilityLabel(CosignCopy.CreateSquad.entryTitle)
                }
            }

            if isLoading, squadRows.isEmpty {
                CosignLoadingCard()
            } else if let errorMessage, squadRows.isEmpty {
                CosignEmptyState(
                    title: CosignCopy.Signers.unableToLoadSquadsTitle,
                    systemImage: "exclamationmark.triangle",
                    message: errorMessage,
                    primaryActionTitle: CosignCopy.Common.selectorRetryAction,
                    primaryAction: {
                        Task { await load(memberAddress: memberAddress, forceRefresh: true) }
                    },
                    primaryActionKind: .secondary,
                    tone: .amber
                )
            } else if squadRows.isEmpty {
                emptySquadsState(memberAddress: memberAddress)
            } else {
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(squadRows.enumerated()), id: \.element.id) { index, row in
                            CosignObjectRowButton {
                                coordinator.go(to: .squadDetail(row.summary.address))
                            } label: {
                                SignerHomeSquadListRow(row: row)
                            }
                            .accessibilityIdentifier("signer-home-squad-row-\(index)")

                            if index < squadRows.count - 1 {
                                Divider()
                                    .overlay(CosignTheme.line)
                                    .padding(.leading, 14)
                            }
                        }
                    }
                }
            }
        }
    }

    private func emptySquadsState(memberAddress: String) -> some View {
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
    }

    private var openProposalCount: Int {
        squadRows.reduce(0) { $0 + $1.openProposalCount }
    }

    private var networkFooter: some View {
        CosignNetworkFooter(environment: footerEnvironment, status: footerStatus)
    }

    private var footerEnvironment: String {
        if demoMode?.usesMarketingNetworkFooter == true {
            return "mainnet"
        }
        let buildEnvironment = CosignBuildEnvironment.current().environmentName
        return buildEnvironment.isEmpty ? "network" : buildEnvironment
    }

    private var footerStatus: NetworkHealthStatus {
        if demoMode?.usesMarketingNetworkFooter == true {
            return .healthy
        }
        return networkHealth?.status ?? .healthy
    }
}

private extension SignerHomeView {
    var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.Signers.recentSectionTitle)

            if recentActivity.isEmpty {
                CosignEmptyState(key: .emptySignerActivity)
            } else {
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        let visibleActivity = Array(recentActivity.prefix(3))
                        ForEach(Array(visibleActivity.enumerated()), id: \.element.id) { index, item in
                            CosignObjectRowButton {
                                coordinator.go(to: .transactionInspection(signature: item.signature, squad: nil))
                            } label: {
                                SignerHomeRecentActivityRow(item: item)
                            }

                            if index < visibleActivity.count - 1 {
                                Divider()
                                    .overlay(CosignTheme.line)
                                    .padding(.leading, 14)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SignerHomeSquadRow: Identifiable {
    var id: String {
        summary.id
    }

    let summary: SquadSummary
    let openProposalCount: Int
}

private func signerAvatar(for type: SignerType) -> some View {
    RoundedRectangle(cornerRadius: 14)
        .fill(signerAvatarGradient(for: type))
        .frame(width: 48, height: 48)
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(.white.opacity(0.28))
                .frame(width: 30, height: 30)
                .offset(x: -7, y: -7)
        }
}

private func signerAvatarGradient(for type: SignerType) -> LinearGradient {
    switch type {
    case .hotWallet:
        LinearGradient(
            colors: [CosignTheme.accent, Color(hex: 0x241808)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private func statusHint(for type: SignerType) -> String {
    switch type {
    case .hotWallet:
        CosignCopy.Signers.statusHint(for: .hotWallet)
    }
}

private func keyKind(for type: SignerType) -> String {
    switch type {
    case .hotWallet:
        CosignCopy.Signers.keyKind(for: .hotWallet)
    }
}
