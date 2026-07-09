import Core
import Squads
import SwiftUI

extension ProposalDetailView {
    @MainActor
    func submit(_ request: ProposalSigningRequest) async {
        guard let proposal else { return }
        // Broadcast-failure simulation bypasses the synthetic receipt so the
        // real broadcaster path runs with DemoBroadcastLegRunner, making the
        // error sheet appear. Default demo mode keeps the synthetic receipt.
        if demoMode?.disablesNetworkWrites == true, CosignDemoMode.broadcastFailureMode() == nil {
            signingRequest = nil
            actionErrorMessage = nil
            actionDeviceStatusMessage = nil
            submittedResult = demoSubmissionResult(for: request, proposal: proposal)
            return
        }

        isSubmittingAction = true
        actionErrorMessage = nil
        actionDeviceStatusMessage = nil
        defer { isSubmittingAction = false }

        do {
            let broadcaster = try await withResolvedProposalSigner(
                request.signer,
                deviceStatus: { actionDeviceStatusMessage = $0 },
                operation: { signer in
                    try await squadsService.makeBroadcaster(
                        request.action,
                        in: squadAddress,
                        transactionIndex: transactionIndex,
                        signer: signer,
                        displayedProposal: proposal
                    )
                }
            )
            actionBroadcaster = broadcaster
            pendingBroadcastRequest = request
            actionDeviceStatusMessage = nil

            let submission = try await broadcaster.run()
            signingRequest = nil
            submittedResult = submissionResult(for: request, submission: submission)
            SigningTally.increment(for: request.signer.address)
            actionBroadcaster = nil
            pendingBroadcastRequest = nil
            await load()
        } catch let ProposalActionError.broadcastFailed(failure) {
            broadcastFailure = failure
            signingRequest = nil
        } catch {
            actionBroadcaster = nil
            pendingBroadcastRequest = nil
            actionErrorMessage = error.localizedDescription
            if request.action == .approveAndExecute {
                await load(forceRefresh: true)
            } else if let actionError = error as? ProposalActionError, case .proposalChanged = actionError {
                await load()
            }
        }
    }

    /// Retries the in-flight broadcast without re-signing. The `isSubmittingAction` guard
    /// prevents concurrent invocations since the broadcaster has no internal reentrancy guard.
    @MainActor
    func runBroadcaster() async {
        guard let broadcaster = actionBroadcaster, !isSubmittingAction else { return }
        isSubmittingAction = true
        defer { isSubmittingAction = false }

        do {
            let submission = try await broadcaster.run()
            let request = pendingBroadcastRequest
            broadcastFailure = nil
            actionBroadcaster = nil
            pendingBroadcastRequest = nil
            if let request {
                submittedResult = submissionResult(for: request, submission: submission)
                SigningTally.increment(for: request.signer.address)
            }
            await load()
        } catch let ProposalActionError.broadcastFailed(failure) {
            broadcastFailure = failure
        } catch {
            clearBroadcastState()
            actionErrorMessage = error.localizedDescription
        }
    }

    func clearBroadcastState() {
        broadcastFailure = nil
        actionBroadcaster = nil
        pendingBroadcastRequest = nil
    }

    /// Handles broadcast-error sheet dismissal. When the approve leg of an
    /// approveAndExecute landed but execute never broadcast, shows a partial
    /// receipt so the user knows their approval counted and can finish later.
    /// In all other cases clears broadcast state as before.
    func handleBroadcastErrorDismiss() {
        guard
            pendingBroadcastRequest?.action == .approveAndExecute,
            broadcastFailure?.action == .execute,
            let approveTransaction = actionBroadcaster?.completedTransactions.first
        else {
            clearBroadcastState()
            return
        }
        let request = pendingBroadcastRequest!
        let partialResult = partialSubmissionResult(
            approveTransaction: approveTransaction,
            proposalIndex: proposal?.transactionIndex
        )
        clearBroadcastState()
        pendingExecuteSigner = request.signer
        submittedResult = partialResult
    }
}
