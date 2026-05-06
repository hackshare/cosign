import Indexer
import Persistence
import Signers
import SwiftData
import SwiftUI
import UI

struct ContentView: View {
    @State private var coordinator = Coordinator()
    @Environment(NetworkSettingsStore.self) private var networkSettings
    @Environment(\.cosignDemoMode) private var demoMode
    @Environment(\.modelContext) private var modelContext
    #if DEBUG
    @State private var pendingNetworkURLDraft: PendingNetworkURLDraft?
    @State private var deepLinkErrorMessage: String?
    #endif

    var body: some View {
        @Bindable var coordinator = coordinator

        NavigationStack(path: $coordinator.path) {
            SignersListView()
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            NetworkHealthBanner()
        }
        .animation(.snappy, value: networkSettings.networkHealth.status)
        .environment(coordinator)
        .task(id: demoMode?.profile) {
            seedDemoSignersIfNeeded()
        }
        .task {
            seedDevnetSignerIfRequested()
        }
        #if DEBUG
        .task {
                routeToBuildVerificationFixtureIfNeeded()
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .sheet(item: $pendingNetworkURLDraft) { draft in
                CosignPromptSheet(
                    title: draft.title,
                    message: draft.message,
                    primaryButtonTitle: CosignCopy.Network.reviewInSettingsButton,
                    secondaryButtonTitle: CosignCopy.Network.cancelButton,
                    onPrimary: { review(draft) },
                    onSecondary: { discard(draft) }
                )
            }
            .sheet(isPresented: deepLinkErrorBinding) {
                CosignPromptSheet(
                    title: CosignCopy.Network.unableToOpenLinkTitle,
                    message: deepLinkErrorMessage ?? "",
                    primaryButtonTitle: CosignCopy.Network.okButton,
                    onPrimary: { deepLinkErrorMessage = nil }
                )
            }
        #endif
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .settings:
            SettingsView()
        case .networkSettings:
            NetworkSettingsView()
        case .selfHostedRelay:
            SelfHostedRelayView()
        case .buildVerification:
            BuildVerificationView(injectedState: BuildVerificationFixture.injectedState())
        case .aboutCosign:
            AboutCosignView()
        case .signers:
            SignersListView()
        case let .signerHome(id):
            SignerHomeView(signerID: id)
        case let .signerDetail(id):
            SignerDetailView(signerID: id)
        case let .signerSquads(memberAddress):
            SquadsListView(memberAddress: memberAddress)
        default:
            squadDestination(for: route)
        }
    }

    @ViewBuilder
    private func squadDestination(for route: Route) -> some View {
        switch route {
        case let .squadDetail(squad):
            SquadDetailView(squadAddress: squad)
        case let .vaultDetail(squad, vaultIndex):
            VaultDetailView(squadAddress: squad, vaultIndex: vaultIndex)
        case let .vaultInspection(squad, vaultIndex):
            VaultInspectionView(squadAddress: squad, vaultIndex: vaultIndex)
        case let .createTransferProposal(squad, vaultIndex):
            CreateTransferProposalView(squadAddress: squad, initialVaultIndex: vaultIndex)
        case let .proposals(squad, latestIndex):
            ProposalsListView(squadAddress: squad, latestTransactionIndex: latestIndex)
        case let .proposalDetail(squad, txIndex):
            ProposalDetailView(squadAddress: squad, transactionIndex: txIndex)
        case let .activity(squad):
            ActivityListView(squadAddress: squad)
        case let .transactionInspection(signature):
            TransactionInspectionView(signature: signature)
        default:
            EmptyView()
        }
    }
}

private extension ContentView {
    func seedDemoSignersIfNeeded() {
        guard let demoMode else {
            return
        }

        do {
            let descriptor = FetchDescriptor<RegisteredSigner>()
            let existingSigners = try modelContext.fetch(descriptor)
            let shouldResetDemoData = CosignDemoMode.shouldResetPersistentData()
            if shouldResetDemoData {
                for signer in existingSigners {
                    modelContext.delete(signer)
                }
            }

            let existingRefs = shouldResetDemoData ? [] : Set(existingSigners.compactMap(\.keychainItemRef))
            let demoSeeds = CosignDemoSigners.seeds(for: demoMode.profile)
            for seed in demoSeeds where !existingRefs.contains(seed.keychainItemRef) {
                modelContext.insert(RegisteredSigner(
                    id: seed.id,
                    label: seed.label,
                    type: seed.type,
                    pubkey: seed.pubkey,
                    keychainItemRef: seed.keychainItemRef,
                    createdAt: seed.createdAt,
                    backedUp: true,
                    backedUpAt: seed.createdAt
                ))
            }
            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed demo signers: \(error)")
        }
    }

    /// Seed a hot-wallet signer from a launch argument so a devnet build can be
    /// driven against real fixture data without a manual import:
    /// `--cosign-seed-signer=<128 hex chars of a 64-byte keypair>`. Debug-only.
    func seedDevnetSignerIfRequested() {
        #if DEBUG
        let prefix = "--cosign-seed-signer="
        guard
            let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
            let keypair = Data(hexString: String(argument.dropFirst(prefix.count))),
            keypair.count == 64
        else {
            return
        }
        let pubkey = Data(keypair.suffix(32))
        do {
            let existing = try modelContext.fetch(FetchDescriptor<RegisteredSigner>())
            guard !existing.contains(where: { $0.pubkeyData == pubkey }) else {
                return
            }
            let signer = try HotWalletSigner.importKeypair(
                label: CosignCopy.Common.devnetSeedSignerLabel,
                keypair64: keypair
            )
            modelContext.insert(RegisteredSigner(
                label: signer.label,
                type: .hotWallet,
                pubkey: signer.pubkey,
                keychainItemRef: signer.keychainAccount
            ))
            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed devnet signer: \(error)")
        }
        #endif
    }
}

private extension Data {
    init?(hexString: String) {
        let chars = Array(hexString)
        guard chars.count % 2 == 0 else {
            return nil
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var index = chars.startIndex
        while index < chars.endIndex {
            guard let byte = UInt8(String(chars[index ... chars.index(after: index)]), radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = chars.index(index, offsetBy: 2)
        }
        self.init(bytes)
    }
}

#Preview {
    ContentView()
}

#if DEBUG
private enum PendingNetworkURLDraft: Identifiable {
    case rpc(PendingRPCURLDraft)

    var id: UUID {
        switch self {
        case let .rpc(draft):
            draft.id
        }
    }

    var title: String {
        switch self {
        case .rpc:
            CosignCopy.Network.updateEndpointPromptTitle
        }
    }

    var message: String {
        switch self {
        case let .rpc(draft):
            CosignCopy.Network.updateEndpointPromptMessage(for: draft)
        }
    }
}

private extension ContentView {
    var deepLinkErrorBinding: Binding<Bool> {
        Binding(
            get: { deepLinkErrorMessage != nil },
            set: { if !$0 { deepLinkErrorMessage = nil } }
        )
    }

    /// The Settings → Build verification screen has no production tap target yet,
    /// so the design walkthrough drives it by setting `COSIGN_BV_FIXTURE`. When
    /// present, land on that screen (with Settings in the back stack) at launch.
    func routeToBuildVerificationFixtureIfNeeded() {
        guard BuildVerificationFixture.injectedState() != nil, coordinator.path.isEmpty else {
            return
        }
        coordinator.go(to: .settings)
        coordinator.go(to: .buildVerification)
    }

    func handleDeepLink(_ url: URL) {
        do {
            switch url.path {
            case "/rpc", "/relay":
                try networkSettings.prepareRPCURLUpdate(from: url)
                if let draft = networkSettings.pendingRPCURLDraft {
                    pendingNetworkURLDraft = .rpc(draft)
                }
            default:
                throw NetworkSettingsError.unsupportedDeepLink
            }
        } catch {
            deepLinkErrorMessage = error.localizedDescription
        }
    }

    func review(_ draft: PendingNetworkURLDraft) {
        switch draft {
        case .rpc:
            pendingNetworkURLDraft = nil
            coordinator.go(to: .selfHostedRelay)
        }
    }

    func discard(_ draft: PendingNetworkURLDraft) {
        switch draft {
        case .rpc:
            pendingNetworkURLDraft = nil
            networkSettings.discardPendingRPCURLDraft()
        }
    }
}
#endif
