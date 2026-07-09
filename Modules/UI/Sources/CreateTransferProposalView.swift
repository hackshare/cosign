import Indexer
import Persistence
import Squads
import SwiftData
import SwiftUI

public struct CreateTransferProposalView: View {
    @Environment(Coordinator.self) var coordinator
    @Environment(\.cosignDemoMode) var demoMode
    @Environment(\.indexerEnvironment) var indexerEnvironment
    @Environment(\.squadsService) var squadsService
    @Query(sort: \RegisteredSigner.createdAt, order: .forward)
    var registeredSigners: [RegisteredSigner]

    let squadAddress: String
    let initialVaultIndex: UInt8?

    @State var detail: SquadDetail?
    @State var selectedSignerID: UUID?
    @State var selectedVaultIndex: UInt8?
    @State var selectedAssetID = ProposalCreationAsset.sol.id
    @State var recipient = ""
    @State var amountText = ""
    @State var memo = ""
    @State var recipientClassification: RecipientClassification?
    @State var recipientCheckFailed = false
    @State var isCheckingRecipientOwner = false
    @State var isLoading = false
    @State var isSubmitting = false
    @State var errorMessage: String?
    @State var deviceStatusMessage: String?
    @State var signingRequest: ProposalCreationSigningRequest?
    @State var submittedResult: ProposalCreationResult?
    @State var proposalCreationCompletion: ProposalCreationCompletion?
    @State var showsSignerSelector = false
    @State var showsVaultSelector = false
    @State var showsAssetSelector = false
    @State var builderStep = TransferProposalBuilderStep.vaultAsset
    @State private var builderFooterHeight = CosignLayout.estimatedStickyFooterHeight
    @FocusState var focusedInput: TransferProposalInputField?

    public init(squadAddress: String, initialVaultIndex: UInt8? = nil) {
        self.squadAddress = squadAddress
        self.initialVaultIndex = initialVaultIndex
    }

    public var body: some View {
        CosignScreen(bottomPadding: screenBottomPadding) {
            if let detail {
                builderHeader(detail)
                builderStepContent(detail)
            } else if isLoading {
                VStack(alignment: .leading, spacing: 8) {
                    CosignSectionTitle(title: CosignCopy.ProposalCreation.newProposalSection)
                    Text(CosignCopy.ProposalCreation.transferTitle)
                        .font(CosignTheme.FontStyle.display)
                        .foregroundStyle(CosignTheme.ink)
                }
                CosignLoadingCard()
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    CosignSectionTitle(title: CosignCopy.ProposalCreation.newProposalSection)
                    Text(CosignCopy.ProposalCreation.transferTitle)
                        .font(CosignTheme.FontStyle.display)
                        .foregroundStyle(CosignTheme.ink)
                }
                CosignEmptyState(
                    title: CosignCopy.ProposalCreation.unableToLoadSquadTitle,
                    systemImage: "exclamationmark.triangle",
                    message: errorMessage
                )
                Button {
                    Task {
                        await load()
                    }
                } label: {
                    Text(CosignCopy.ProposalCreation.retryButton)
                        .cosignSecondaryAction()
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(CosignCopy.ProposalCreation.createTransferNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await load(forceRefresh: true)
        }
        .task(id: squadAddress) {
            await load()
        }
        .sheet(item: $signingRequest) { request in
            ProposalCreationReviewSheet(
                request: request,
                isSubmitting: isSubmitting,
                errorMessage: errorMessage,
                deviceStatusMessage: deviceStatusMessage,
                onCancel: {
                    if !isSubmitting {
                        signingRequest = nil
                        errorMessage = nil
                        deviceStatusMessage = nil
                    }
                },
                onConfirm: {
                    Task {
                        await submit(request)
                    }
                }
            )
        }
        .sheet(item: $submittedResult, onDismiss: finishSubmittedProposalFlow) { result in
            ProposalCreationResultSheet(
                result: result,
                onDone: {
                    submittedResult = nil
                },
                onOpenProposal: {
                    proposalCreationCompletion = .openProposal(result.submission.transactionIndex)
                    submittedResult = nil
                },
                onInspectSignature: {
                    proposalCreationCompletion = .inspectTransaction(result.submission.signature)
                    submittedResult = nil
                }
            )
        }
        .sheet(isPresented: $showsSignerSelector, onDismiss: { dismissSelector(.signer) }, content: {
            signerSelectorSheet
        })
        .sheet(isPresented: $showsVaultSelector, onDismiss: { dismissSelector(.vault) }, content: {
            vaultSelectorSheet
        })
        .sheet(isPresented: $showsAssetSelector, onDismiss: { dismissSelector(.asset) }, content: {
            assetSelectorSheet
        })
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(CosignCopy.Common.done) {
                    focusedInput = nil
                }
                .accessibilityIdentifier("proposal-builder-keyboard-done")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if detail != nil {
                builderFooter
                    .cosignMeasureHeight($builderFooterHeight)
            }
        }
        .accessibilityIdentifier("screen.create-transfer-proposal")
    }

    private var screenBottomPadding: CGFloat {
        detail == nil ?
            CosignLayout.screenBottomPadding :
            CosignLayout.screenBottomPadding(stickyFooterHeight: builderFooterHeight)
    }
}

enum TransferProposalBuilderStep: Int, CaseIterable {
    case vaultAsset
    case recipient
    case amount
    case review

    var index: Int {
        rawValue + 1
    }

    var next: Self? {
        Self(rawValue: rawValue + 1)
    }

    var previous: Self? {
        Self(rawValue: rawValue - 1)
    }

    var headline: String {
        switch self {
        case .vaultAsset:
            CosignCopy.ProposalCreation.vaultAssetStepHeadline
        case .recipient:
            CosignCopy.ProposalCreation.recipientStepHeadline
        case .amount:
            CosignCopy.ProposalCreation.amountStepHeadline
        case .review:
            CosignCopy.ProposalCreation.reviewStepHeadline
        }
    }

    var subtitle: String {
        switch self {
        case .vaultAsset:
            CosignCopy.ProposalCreation.vaultAssetStepSubtitle
        case .recipient:
            CosignCopy.ProposalCreation.recipientStepSubtitle
        case .amount:
            CosignCopy.ProposalCreation.amountStepSubtitle
        case .review:
            CosignCopy.ProposalCreation.reviewStepSubtitle
        }
    }
}

enum TransferProposalSelector {
    case signer
    case vault
    case asset
}

enum TransferProposalInputField {
    case recipient
    case amount
    case memo
}
