import Core
import Indexer
import Persistence
import Squads
import SwiftData
import SwiftUI

public struct ProposalDetailView: View {
    @Environment(Coordinator.self) var coordinator
    @Environment(\.cosignDemoMode) var demoMode
    @Environment(\.indexerEnvironment) var indexerEnvironment
    @Environment(\.openURL) var openURL
    @Environment(\.squadsService) var squadsService
    @Query(sort: \RegisteredSigner.createdAt, order: .forward)
    private var registeredSigners: [RegisteredSigner]

    let squadAddress: String
    let transactionIndex: UInt64
    let instructionDecoder = InstructionDecoder()
    @State var proposal: SquadProposalDetail?
    @State var squadDetail: SquadDetail?
    @State var squadMembers = [SquadMember]()
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State var selectedSignerID: UUID?
    @State var signingRequest: ProposalSigningRequest?
    @State var isSubmittingAction = false
    @State var actionErrorMessage: String?
    @State var actionDeviceStatusMessage: String?
    @State var actionBroadcaster: ProposalActionBroadcaster?
    @State var broadcastFailure: BroadcastFailure?
    @State var pendingBroadcastRequest: ProposalSigningRequest?
    @State var submittedResult: ProposalSubmissionResult?
    @State var pendingExecuteSigner: ProposalActionSigner?
    @State var executionSignature: String?
    @State var inspectionReport: ProposalInspectionReport?
    @State var executedInspectionReport: ExecutedTransactionInspectionReport?
    @State var ownVaultAccounts = Set<String>()
    @State var isLoadingInspection = false
    @State var inspectionErrorMessage: String?
    @State var stickyFooterHeight = CosignLayout.estimatedStickyFooterHeight

    public init(squadAddress: String, transactionIndex: UInt64) {
        self.squadAddress = squadAddress
        self.transactionIndex = transactionIndex
    }

    public var body: some View {
        Group {
            if let proposal {
                proposalContent(proposal)
            } else if isLoading {
                CosignScreen {
                    proposalNavigationHeader()
                    CosignLoadingCard()
                }
            } else if let errorMessage {
                CosignScreen {
                    proposalNavigationHeader()
                    CosignEmptyState(
                        title: CosignCopy.ProposalDetail.unableToLoadTitle,
                        systemImage: "exclamationmark.triangle",
                        message: errorMessage
                    )
                    Button(CosignCopy.ProposalDetail.retryButtonTitle) {
                        Task {
                            await load()
                        }
                    }
                }
            } else {
                CosignScreen {
                    CosignLoadingCard()
                }
            }
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .cosignPage()
        .refreshable { await load(forceRefresh: true) }
        .task(id: "\(squadAddress)-\(transactionIndex)") { await load() }
        .task(id: inspectionTaskID) { await loadInspectionForCurrentProposal() }
        .pollingRefresh(
            id: "proposal-detail-\(squadAddress)-\(transactionIndex)",
            interval: ReadPollingInterval.proposal,
            enabled: !squadAddress.isEmpty
        ) { await load(forceRefresh: true, showsLoading: false) }
        .webSocketRefresh(
            id: "proposal-detail-\(squadAddress)-\(transactionIndex)",
            webSocketURL: indexerEnvironment.effectiveWebSocketURL,
            accounts: watchedAccounts,
            enabled: proposal != nil
        ) { await load(forceRefresh: true, showsLoading: false) }
        .sheet(item: $signingRequest) { request in
            ProposalSigningSheet(
                request: request,
                proposal: proposal,
                isSubmitting: isSubmittingAction,
                errorMessage: actionErrorMessage,
                deviceStatusMessage: actionDeviceStatusMessage,
                onCancel: {
                    if !isSubmittingAction {
                        signingRequest = nil
                        actionErrorMessage = nil
                        actionDeviceStatusMessage = nil
                    }
                },
                onConfirm: {
                    Task {
                        await submit(request)
                    }
                }
            )
        }
        .sheet(item: $submittedResult) { result in
            ProposalSubmissionSheet(
                result: result,
                squadAddress: squadAddress,
                onDone: {
                    submittedResult = nil
                    pendingExecuteSigner = nil
                    coordinator.replaceCurrent(with: .activity(squad: squadAddress))
                },
                onFinishExecution: result.kind == .partialApproveExecuted ? {
                    let signer = pendingExecuteSigner
                    submittedResult = nil
                    pendingExecuteSigner = nil
                    if let signer {
                        beginSigning(action: .execute, signer: signer)
                    }
                } : nil
            )
        }
        .sheet(
            isPresented: Binding(
                get: { broadcastFailure != nil },
                set: { presented in if !presented { handleBroadcastErrorDismiss() } }
            )
        ) {
            if let failure = broadcastFailure {
                BroadcastErrorSheet(
                    failure: failure,
                    isTerminal: failure.attempt >= CosignCopy.BroadcastError.maxAttempts,
                    isRetrying: isSubmittingAction,
                    onRetry: { Task { await runBroadcaster() } },
                    onDismiss: { handleBroadcastErrorDismiss() }
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let proposal {
                stickyActionFooter(proposal)
                    .cosignMeasureHeight($stickyFooterHeight)
            }
        }
        .accessibilityIdentifier("screen.proposal-detail")
    }

    var executionFailed: Bool {
        guard let status = executedInspectionReport?.status else { return false }
        return status.error != nil || status.status.lowercased() == "failed"
    }

    private var watchedAccounts: [String] {
        guard let proposal else {
            return []
        }

        return [proposal.transactionAddress, squadAddress].compactMap(\.self) + proposal.accountsReferenced
    }

    private var inspectionTaskID: String {
        guard let proposal else {
            return "none"
        }

        return [
            squadAddress,
            String(proposal.transactionIndex),
            proposal.status,
            String(proposal.votesYes),
            String(proposal.votesNo),
            String(proposal.votesCancelled),
            executionSignature ?? "",
            indexerEnvironment.effectiveRPCURL.absoluteString
        ].joined(separator: "|")
    }

    @MainActor
    func load(forceRefresh: Bool = false, showsLoading: Bool = true) async {
        if showsLoading {
            isLoading = true
        }
        if proposal == nil || showsLoading {
            errorMessage = nil
        }
        defer { if showsLoading { isLoading = false } }

        do {
            async let loadedProposal = squadsService.proposal(in: squadAddress, transactionIndex: transactionIndex)
            async let loadedDetail = if forceRefresh {
                squadsService.refreshDetail(of: squadAddress)
            } else {
                squadsService.detail(of: squadAddress)
            }
            let (newProposal, newDetail) = try await (loadedProposal, loadedDetail)
            async let newVaultAccounts = vaultAccountAddresses()
            let newExecutionSignature = await latestExecutionSignature(for: newProposal, forceRefresh: forceRefresh)
            proposal = newProposal
            squadDetail = newDetail
            squadMembers = newDetail.members
            ownVaultAccounts = await newVaultAccounts
            executionSignature = newExecutionSignature
            errorMessage = nil
        } catch {
            if proposal == nil {
                squadDetail = nil
                squadMembers = []
                executionSignature = nil
                clearInspection()
                errorMessage = String(describing: error)
            }
        }
    }

    private func vaultAccountAddresses() async -> Set<String> {
        await (try? squadsService.ownVaultAddresses(of: squadAddress)) ?? []
    }

    private func latestExecutionSignature(for proposal: SquadProposalDetail, forceRefresh: Bool) async -> String? {
        if let cachedSignature = squadsService.executionSignature(
            in: squadAddress,
            transactionIndex: proposal.transactionIndex
        ) {
            return cachedSignature
        }

        guard proposal.isExecuted, let transactionAddress = proposal.transactionAddress else {
            return nil
        }

        do {
            let activity = if forceRefresh {
                try await squadsService.refreshActivity(forAddress: transactionAddress, limit: 5)
            } else {
                try await squadsService.activity(forAddress: transactionAddress, limit: 5)
            }
            return activity
                .first { $0.error == nil }?
                .signature
        } catch {
            return nil
        }
    }
}

extension ProposalDetailView {
    @MainActor
    func loadInspectionForCurrentProposal() async {
        guard let proposal else {
            clearInspection()
            return
        }

        if proposal.isExecuted, let executionSignature {
            await loadExecutedInspection(signature: executionSignature)
            return
        }

        await loadProposalInspection(proposal)
    }

    @MainActor
    func clearInspection() {
        inspectionReport = nil
        executedInspectionReport = nil
        isLoadingInspection = false
        inspectionErrorMessage = nil
    }

    @MainActor
    private func loadExecutedInspection(signature: String) async {
        let request = ExecutedTransactionInspectionRequest(signature: signature)
        guard indexerEnvironment.relay.executedTransactionInspectionURL(for: request) != nil else {
            clearInspection()
            return
        }

        isLoadingInspection = true
        inspectionErrorMessage = nil
        defer { isLoadingInspection = false }

        do {
            inspectionReport = nil
            executedInspectionReport = try await indexerEnvironment.relay
                .executedTransactionInspectionReport(for: request)
        } catch {
            inspectionReport = nil
            executedInspectionReport = nil
            inspectionErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadProposalInspection(_ proposal: SquadProposalDetail) async {
        let request = ProposalInspectionRequest(
            squadAddress: squadAddress,
            transactionIndex: proposal.transactionIndex
        )
        guard indexerEnvironment.relay.proposalInspectionURL(for: request) != nil else {
            clearInspection()
            return
        }

        isLoadingInspection = true
        inspectionErrorMessage = nil
        defer { isLoadingInspection = false }

        do {
            executedInspectionReport = nil
            inspectionReport = try await indexerEnvironment.relay.proposalInspectionReport(for: request)
        } catch {
            inspectionReport = nil
            executedInspectionReport = nil
            inspectionErrorMessage = error.localizedDescription
        }
    }
}

extension ProposalDetailView {
    @ViewBuilder
    func actionsSection(_ proposal: SquadProposalDetail) -> some View {
        if shouldShowInlineActionsSection(for: proposal) {
            ProposalActionsSection(
                proposal: proposal,
                signers: actionSigners,
                selectedSignerID: $selectedSignerID,
                squadMembers: squadMembers,
                isSubmittingAction: isSubmittingAction,
                showsActionButtons: false,
                onConnectSigner: { coordinator.popToRoot() },
                onSelectAction: { action, signer in
                    beginSigning(action: action, signer: signer)
                }
            )
        }
    }

    func shouldShowInlineActionsSection(for proposal: SquadProposalDetail) -> Bool {
        guard !actionSigners.isEmpty else {
            return true
        }

        let actionableSigners = actionSigners.filter { signer in
            guard let member = squadMembers.first(where: { $0.pubkey == signer.address }) else {
                return false
            }
            return !availableProposalActions(for: proposal, member: member).isEmpty
        }
        return actionableSigners.isEmpty || actionableSigners.count > 1
    }

    func beginSigning(action: SquadProposalAction, signer: ProposalActionSigner) {
        actionErrorMessage = nil
        actionDeviceStatusMessage = nil
        signingRequest = ProposalSigningRequest(
            action: action,
            signer: signer,
            inspectionAction: inspectionReport?.action
        )
    }

    var actionSigners: [ProposalActionSigner] {
        registeredSigners.compactMap(makeProposalActionSigner)
    }
}
