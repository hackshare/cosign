import Foundation
import Indexer
import Squads
import SwiftUI

extension CreateTransferProposalView {
    func signerSection(_ detail: SquadDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.ProposalCreation.signerSectionTitle)
            if actionSigners.isEmpty {
                CosignEmptyState(key: .noLocalSigner, primaryAction: {
                    coordinator.go(to: .signers)
                })
            } else if let selectedSigner {
                CosignSelectorField(
                    label: CosignCopy.ProposalCreation.signerLabel,
                    title: selectedSigner.label,
                    subtitle: selectedSigner.type.displayName,
                    detail: cosignShortAddress(selectedSigner.address),
                    accessibilityIdentifier: "selector-field-signer"
                ) {
                    presentSelector(.signer)
                }

                CosignCard {
                    CosignAddressBlock(
                        title: CosignCopy.ProposalCreation.signerAddressTitle,
                        address: selectedSigner.address,
                        accessibilityLabel: CosignCopy.ProposalCreation.copySignerAddressAccessibilityLabel()
                    )

                    if let message = signerMessage(for: selectedSigner, detail: detail) {
                        CosignInlineBanner(tone: .amber) {
                            Text(message)
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    var recipientInputGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recipientPlaceholder.uppercased())
                .font(CosignTheme.FontStyle.eyebrow)
                .foregroundStyle(CosignTheme.inkFaint)
            recipientField
                .cosignField()

            if let recipientValidationMessage {
                CosignInlineBanner(tone: .red) {
                    Text(recipientValidationMessage)
                }
            } else if let recipientWarningMessage {
                CosignInlineBanner(tone: .amber) {
                    Text(recipientWarningMessage)
                }
            } else if recipientClassification == .programOwned {
                RiskBanner(
                    title: CosignCopy.ProposalCreation.recipientProgramOwnedTitle,
                    message: CosignCopy.ProposalCreation.recipientProgramOwnedBody,
                    tone: .red
                )
            } else if recipientClassification == .squadsControlled {
                RiskBanner(
                    title: CosignCopy.ProposalCreation.recipientSquadsControlledTitle,
                    message: CosignCopy.ProposalCreation.recipientSquadsControlledBody,
                    tone: .neutral
                )
            } else if recipientCheckFailed {
                RiskBanner(
                    title: CosignCopy.ProposalCreation.recipientCheckUnavailableTitle,
                    message: CosignCopy.ProposalCreation.recipientCheckUnavailableBody,
                    tone: .neutral
                )
            } else if recipientConfirmationMessage != nil, recipientClassification == .wallet {
                RiskBanner(
                    title: CosignCopy.ProposalCreation.recipientVerifiedWalletTitle,
                    message: CosignCopy.ProposalCreation.recipientVerifiedWalletBody,
                    tone: .mint
                )
            }
        }
        .task(id: trimmedRecipient) {
            await checkRecipientOwner()
        }
    }

    @MainActor
    func checkRecipientOwner() async {
        let address = trimmedRecipient
        guard !address.isEmpty,
              recipientValidationMessage == nil,
              recipientWarningMessage == nil
        else {
            recipientClassification = nil
            recipientCheckFailed = false
            isCheckingRecipientOwner = false
            return
        }

        isCheckingRecipientOwner = true
        defer { isCheckingRecipientOwner = false }

        try? await Task.sleep(for: .milliseconds(400))
        if Task.isCancelled {
            return
        }

        do {
            recipientClassification = try await squadsService.classifyRecipient(address: address)
            recipientCheckFailed = false
        } catch {
            // Fail to uncertain, never silently open: withhold the green
            // confirmation and surface that we couldn't verify the recipient.
            recipientClassification = nil
            recipientCheckFailed = true
        }
    }

    var amountInputGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((selectedAsset?.amountLabel ?? CosignCopy.ProposalCreation.amountLabel).uppercased())
                .font(CosignTheme.FontStyle.eyebrow)
                .foregroundStyle(CosignTheme.inkFaint)
            amountField(selectedAsset)
                .cosignField()

            if let amountValidationMessage {
                CosignInlineBanner(tone: .red) {
                    Text(amountValidationMessage)
                }
            }
        }
    }

    var memoInputGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CosignCopy.ProposalCreation.memoLabel.uppercased())
                .font(CosignTheme.FontStyle.eyebrow)
                .foregroundStyle(CosignTheme.inkFaint)
            TextField(CosignCopy.ProposalCreation.optionalMemoPlaceholder, text: $memo)
                .textInputAutocapitalization(.sentences)
                .focused($focusedInput, equals: .memo)
                .cosignField()
        }
    }

    @MainActor
    func load(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedDetail = if forceRefresh {
                try await squadsService.refreshDetail(of: squadAddress)
            } else {
                try await squadsService.detail(of: squadAddress)
            }
            detail = loadedDetail
            selectedVaultIndex = preferredVaultIndex(in: loadedDetail)
        } catch {
            detail = nil
            errorMessage = String(describing: error)
        }
    }

    func startReview() {
        guard canReview else {
            return
        }

        do {
            signingRequest = try makeSigningRequest()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    @MainActor
    func submit(_ request: ProposalCreationSigningRequest) async {
        if demoMode?.disablesNetworkWrites == true {
            signingRequest = nil
            errorMessage = nil
            deviceStatusMessage = nil
            submittedResult = demoProposalCreationResult(for: request)
            proposalCreationCompletion = .popBuilder
            return
        }

        isSubmitting = true
        errorMessage = nil
        deviceStatusMessage = nil
        defer { isSubmitting = false }

        do {
            let submission = try await withResolvedProposalSigner(
                request.signer,
                deviceStatus: { deviceStatusMessage = $0 },
                operation: { signer in
                    try await squadsService.submitTransferProposal(
                        request.draft,
                        in: squadAddress,
                        signer: signer
                    )
                }
            )
            signingRequest = nil
            deviceStatusMessage = nil
            submittedResult = ProposalCreationResult(
                submission: submission,
                explorerURL: SolanaExplorer.transactionURL(
                    signature: submission.signature,
                    rpcURL: indexerEnvironment.effectiveExplorerRPCURL
                )
            )
            proposalCreationCompletion = .popBuilder
            await load(forceRefresh: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func demoProposalCreationResult(for request: ProposalCreationSigningRequest) -> ProposalCreationResult {
        let transactionIndex = (detail?.transactionIndex ?? 0) + 1
        let signature = CosignDemoSubmissionSignature.signature(
            kind: .propose,
            proposalIndex: transactionIndex,
            offset: 0
        )
        let submission = ProposalCreationSubmission(
            signature: signature,
            transactionIndex: transactionIndex,
            proposalAddress: demoAccountAddress(kind: .proposal, transactionIndex: transactionIndex),
            transactionAddress: demoAccountAddress(kind: .transaction, transactionIndex: transactionIndex),
            vaultAddress: request.vault.address,
            proposal: nil
        )
        return ProposalCreationResult(
            submission: submission,
            explorerURL: SolanaExplorer.transactionURL(
                signature: signature,
                rpcURL: indexerEnvironment.effectiveExplorerRPCURL
            )
        )
    }

    private func demoAccountAddress(
        kind: DemoProposalCreationAccountKind,
        transactionIndex: UInt64
    ) -> String {
        let prefix = switch kind {
        case .proposal:
            "9xZLr3K2tVwQp6YBncFa4GhJmS8dEuR1T"
        case .transaction:
            "6mN4bTx7QpYe3VaKrsC2GjD8HfUwZ5X"
        }
        return "\(prefix)\(transactionIndex)"
    }

    @MainActor
    func finishSubmittedProposalFlow() {
        guard let completion = proposalCreationCompletion else {
            return
        }

        proposalCreationCompletion = nil
        submittedResult = nil
        resetDraft()

        switch completion {
        case .popBuilder:
            coordinator.pop()
        case let .openProposal(transactionIndex):
            coordinator.replaceCurrent(with: .proposalDetail(
                squad: squadAddress,
                txIndex: transactionIndex
            ))
        case let .inspectTransaction(signature):
            coordinator.replaceCurrent(with: .transactionInspection(signature: signature, squad: squadAddress))
        }
    }

    func resetDraft() {
        selectedAssetID = ProposalCreationAsset.sol.id
        recipient = ""
        amountText = ""
        memo = ""
        errorMessage = nil
        deviceStatusMessage = nil
    }

    var actionSigners: [ProposalActionSigner] {
        registeredSigners.compactMap(makeProposalActionSigner)
    }

    var selectedSigner: ProposalActionSigner? {
        if let selectedSignerID, let signer = actionSigners.first(where: { $0.id == selectedSignerID }) {
            return signer
        }
        return actionSigners.first { signer in
            guard let detail else {
                return false
            }
            return member(for: signer, in: detail)?.canInitiate == true
        } ?? actionSigners.first
    }

    var selectedVault: VaultDetail? {
        guard let detail else {
            return nil
        }

        if let selectedVaultIndex, let vault = detail.vaults.first(where: { $0.ref.index == selectedVaultIndex }) {
            return vault
        }
        return detail.vaults.first
    }

    var trimmedMemo: String? {
        let value = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var parsedAmount: UInt64? {
        guard let selectedAsset else {
            return nil
        }
        return DisplayAmountParser.baseUnits(from: amountText, decimals: selectedAsset.decimals)
    }

    func preferredVaultIndex(in detail: SquadDetail) -> UInt8? {
        if let initialVaultIndex, detail.vaults.contains(where: { $0.ref.index == initialVaultIndex }) {
            return initialVaultIndex
        }
        if let selectedVaultIndex, detail.vaults.contains(where: { $0.ref.index == selectedVaultIndex }) {
            return selectedVaultIndex
        }
        return detail.vaults.first?.ref.index
    }

    func member(for signer: ProposalActionSigner, in detail: SquadDetail) -> SquadMember? {
        detail.members.first { $0.pubkey == signer.address }
    }

    func signerMessage(for signer: ProposalActionSigner, detail: SquadDetail) -> String? {
        guard let member = member(for: signer, in: detail) else {
            return CosignCopy.ProposalCreation.signerNotMemberMessage
        }
        guard member.canInitiate else {
            return CosignCopy.ProposalCreation.signerCannotInitiateMessage
        }
        return nil
    }
}

private enum DemoProposalCreationAccountKind {
    case proposal
    case transaction
}
