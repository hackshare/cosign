import Core
import CosignCore
import Indexer
import Persistence
import Signers
import Squads
import SwiftData
import SwiftUI

public struct SignersListView: View {
    @Environment(Coordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Environment(\.cosignDemoMode) private var demoMode
    @Environment(\.squadsService) private var squadsService
    @Query(sort: \RegisteredSigner.createdAt, order: .forward)
    private var signers: [RegisteredSigner]

    @State private var showAddSignerChooser = false
    @State private var addSignerSheet: AddSignerSheet?
    @State private var pendingAddSignerSheet: AddSignerSheet?
    @State private var pendingDelete: RegisteredSigner?
    @State private var signerSummaries = [UUID: SignerListMembershipSummary]()
    @State private var searchText = ""
    @State private var isSearchVisible = false

    public init() {}

    public var body: some View {
        CosignAnchoredFooterScreen {
            HStack {
                CosignWordmark()
                if let env = envBadge {
                    EnvBadge(label: env.label, tone: env.tone)
                }
                Spacer()
                HStack(spacing: 2) {
                    CosignIconButton(glyph: .search) {
                        withAnimation(.snappy(duration: 0.18)) {
                            isSearchVisible.toggle()
                            if !isSearchVisible {
                                searchText = ""
                            }
                        }
                    }
                    .accessibilityLabel(CosignCopy.Signers.searchAccessibilityLabel)

                    CosignIconButton(glyph: .settings) {
                        coordinator.go(to: .settings)
                    }
                    .accessibilityLabel(CosignCopy.Signers.settingsAccessibilityLabel)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                CosignSectionTitle(title: homeSubtitle)
                Text(CosignCopy.Signers.title)
                    .font(CosignTheme.FontStyle.displayL)
                    .foregroundStyle(CosignTheme.ink)
            }

            if isSearchVisible || !searchText.isEmpty {
                CosignSearchField(placeholder: CosignCopy.Signers.searchPlaceholder, text: $searchText)
            }

            if signers.isEmpty {
                CosignEmptyState(
                    key: .noSigners,
                    primaryAction: {
                        showAddSignerChooser = true
                    }
                )
            } else {
                if let pendingOverview {
                    PendingApprovalsBanner(
                        title: CosignCopy.Signers.proposalsAwaitingTitle(count: pendingOverview.count),
                        subtitle: CosignCopy.Signers.proposalsAwaitingSubtitle(
                            signerLabels: pendingOverview.signerLabels
                        )
                    ) {
                        coordinator.go(to: .signerHome(pendingOverview.signerID))
                    }
                }

                VStack(spacing: 10) {
                    ForEach(Array(filteredSigners.enumerated()), id: \.element.id) { index, signer in
                        CosignObjectNavigationLink(value: Route.signerHome(signer.id)) {
                            SignerListCard(
                                signer: signer,
                                membershipSummary: signerSummaries[signer.id]
                            )
                        }
                        .accessibilityIdentifier("signer-row-\(index)")
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDelete = signer
                            } label: {
                                HStack(spacing: 8) {
                                    CosignGlyphView(glyph: .xmark, size: 14, color: CosignTheme.riskRed)
                                    Text(CosignCopy.Signers.removeSignerMenuTitle)
                                }
                            }
                        }
                    }
                }
            }

            if !signers.isEmpty {
                Button {
                    showAddSignerChooser = true
                } label: {
                    HStack(spacing: 8) {
                        CosignGlyphView(glyph: .plus, size: 14, color: CosignTheme.inkDim)
                        Text(CosignCopy.Signers.connectOrCreateTitle)
                    }
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.inkDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.clear, in: .rect(cornerRadius: CosignTheme.Radius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: CosignTheme.Radius.card)
                            .stroke(CosignTheme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("signer-add-cta")
            }
        } footer: {
            if !signers.isEmpty {
                networkFooter
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.signers")
        .toolbar(.hidden, for: .navigationBar)
        .task(id: signers.map(\.id)) {
            await loadMembershipSummaries()
        }
        .refreshable {
            await loadMembershipSummaries(forceRefresh: true)
        }
        .sheet(item: $addSignerSheet) { sheet in
            switch sheet {
            case .hotWallet:
                AddHotWalletView()
            case .ledger:
                AddLedgerView()
            case .yubikey:
                AddYubiKeyView()
            }
        }
        .sheet(
            isPresented: $showAddSignerChooser,
            onDismiss: {
                if let pendingAddSignerSheet {
                    addSignerSheet = pendingAddSignerSheet
                    self.pendingAddSignerSheet = nil
                }
            },
            content: {
                AddSignerChooserSheet { sheet in
                    pendingAddSignerSheet = sheet
                    showAddSignerChooser = false
                }
            }
        )
        .sheet(item: $pendingDelete) { signer in
            CosignDestructiveConfirmationSheet(
                title: CosignCopy.Signers.removeSignerTitle,
                message: removeMessage(for: signer),
                confirmTitle: CosignCopy.Signers.removeConfirmTitle(label: signer.label)
            ) {
                pendingDelete = nil
            } onConfirm: {
                remove(signer)
            }
        }
    }

    private func remove(_ signer: RegisteredSigner) {
        if signer.type == .hotWallet, let account = signer.keychainItemRef {
            try? HotWalletSigner.eraseFromKeychain(account: account)
        }
        context.delete(signer)
        try? context.save()
        pendingDelete = nil
    }

    private var filteredSigners: [RegisteredSigner] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return signers
        }
        return signers.filter { signer in
            signer.label.lowercased().contains(query) ||
                signer.type.displayName.lowercased().contains(query) ||
                CosignCore.base58(signer.pubkey).lowercased().contains(query)
        }
    }

    private func removeMessage(for signer: RegisteredSigner) -> String {
        CosignCopy.Signers.removeMessage(for: signer.type)
    }

    @MainActor
    private func loadMembershipSummaries(forceRefresh: Bool = false) async {
        guard !signers.isEmpty else {
            signerSummaries = [:]
            return
        }

        var next = signerSummaries
        for signer in signers {
            let address = CosignCore.base58(signer.pubkey)
            do {
                let squads = if forceRefresh {
                    try await squadsService.refreshSquads(forMember: address)
                } else {
                    try await squadsService.squads(forMember: address)
                }
                next[signer.id] = await SignerListMembershipSummary(
                    squadCount: squads.count,
                    openProposalCount: openProposalCount(for: squads, forceRefresh: forceRefresh),
                    didFail: false
                )
            } catch {
                next[signer.id] = SignerListMembershipSummary(
                    squadCount: nil,
                    openProposalCount: 0,
                    didFail: true
                )
            }
        }

        signerSummaries = next.filter { id, _ in
            signers.contains { $0.id == id }
        }
    }

    private func openProposalCount(for squads: [SquadSummary], forceRefresh: Bool) async -> Int {
        var count = 0
        for squad in squads {
            guard let range = ProposalRange.recent(through: squad.transactionIndex, limit: 12) else {
                continue
            }
            let proposals: [SquadProposalSummary]
            do {
                proposals = if forceRefresh {
                    try await squadsService.refreshProposals(in: squad.address, range: range)
                } else {
                    try await squadsService.proposals(in: squad.address, range: range)
                }
            } catch {
                proposals = []
            }
            count += proposals.filter(\.isOpenForSignerList).count
        }
        return count
    }
}

private extension SignersListView {
    var homeSubtitle: String {
        CosignCopy.Signers.homeSubtitle(signerCount: signers.count, squadCount: aggregateSquadCount)
    }

    var aggregateSquadCount: Int? {
        guard !signers.isEmpty else {
            return 0
        }
        let summaries = signers.compactMap { signerSummaries[$0.id] }
        guard summaries.count == signers.count else {
            return nil
        }
        return summaries.reduce(0) { $0 + ($1.squadCount ?? 0) }
    }

    var pendingOverview: PendingApprovalsOverview? {
        let rows = signers.compactMap { signer -> (RegisteredSigner, SignerListMembershipSummary)? in
            guard let summary = signerSummaries[signer.id], summary.openProposalCount > 0 else {
                return nil
            }
            return (signer, summary)
        }
        guard let first = rows.first else {
            return nil
        }
        return PendingApprovalsOverview(
            signerID: first.0.id,
            count: rows.reduce(0) { $0 + $1.1.openProposalCount },
            signerLabels: rows.map(\.0.label)
        )
    }

    var networkFooter: some View {
        CosignNetworkFooter(text: networkFooterText)
    }

    var networkFooterText: String {
        if demoMode?.usesMarketingNetworkFooter == true {
            return CosignCopy.Network.demoEnhancedFooter
        }
        let buildEnvironment = CosignBuildEnvironment.current().environmentName
        return CosignCopy.Network.pinnedFooter(buildEnvironment.isEmpty ? "relay" : buildEnvironment)
    }

    var envBadge: (label: String, tone: EnvBadgeTone)? {
        if let demoMode {
            return demoMode.usesMarketingNetworkFooter ? nil : ("DEMO", .demo)
        }
        let environment = CosignBuildEnvironment.current().environmentName.lowercased()
        switch environment {
        case "", "mainnet", "mainnet-beta":
            return nil
        default:
            return (environment.uppercased(), .neutral)
        }
    }
}

private extension SquadProposalSummary {
    var isOpenForSignerList: Bool {
        switch status.lowercased() {
        case "active", "approved":
            true
        default:
            false
        }
    }
}
