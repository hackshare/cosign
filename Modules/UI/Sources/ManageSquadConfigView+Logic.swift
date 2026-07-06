import Core
import CosignCore
import Foundation
import Indexer
import Squads
import SwiftUI

extension ManageSquadConfigView {
    // MARK: - Load

    @MainActor
    func load() async {
        loadError = false
        do {
            let loaded = try await squadsService.detail(of: squadAddress)
            detail = loaded
            threshold = Int(loaded.threshold)
        } catch {
            loadError = true
        }
    }

    // MARK: - Member editing

    @MainActor
    func addMember() {
        let candidate = newMember.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CosignCore.isValidSolanaPubkey(candidate) else {
            memberError = CosignCopy.ManageSquad.invalidAddress
            return
        }
        let alreadyMember = detail?.members.contains(where: { $0.pubkey == candidate }) == true
        let alreadyStaged = stagedAdditions.contains(candidate)
        guard !alreadyMember, !alreadyStaged else {
            memberError = CosignCopy.ManageSquad.duplicateAddress
            return
        }
        stagedAdditions.append(candidate)
        newMember = ""
        memberError = nil
    }

    @MainActor
    func removeStagedAddition(_ address: String) {
        stagedAdditions.removeAll { $0 == address }
        clampThreshold()
    }

    @MainActor
    func toggleRemoval(_ pubkey: String) {
        if stagedRemovals.contains(pubkey) {
            stagedRemovals.remove(pubkey)
        } else {
            stagedRemovals.insert(pubkey)
        }
    }

    @MainActor
    func clampThreshold() {
        let max = max(1, projectedVoterCount)
        if threshold > max { threshold = max }
    }

    // MARK: - Create proposal

    @MainActor
    func create() async {
        if demoMode?.disablesNetworkWrites == true {
            createError = CosignCopy.ManageSquad.demoDisabled
            return
        }
        guard let detail else { return }
        let memberInitiators = detail.members.filter(\.canInitiate).map(\.pubkey)
        guard
            let registered = registeredSigners
            .first(where: { memberInitiators.contains(CosignCore.base58($0.pubkey)) }),
            let actionSigner = makeProposalActionSigner(from: registered)
        else {
            createError = CosignCopy.ManageSquad.noEligibleSigner
            return
        }
        isCreating = true
        createError = nil
        defer { isCreating = false }
        do {
            let submission = try await withResolvedProposalSigner(
                actionSigner,
                deviceStatus: { _ in },
                operation: { signer in
                    try await squadsService.submitConfigChangeProposal(
                        addedMembers: stagedAdditions,
                        removedMembers: Array(stagedRemovals),
                        newThreshold: UInt16(threshold),
                        in: squadAddress,
                        signer: signer
                    )
                }
            )
            coordinator.replaceCurrent(
                with: .proposalDetail(squad: squadAddress, txIndex: submission.transactionIndex)
            )
        } catch let error as ConfigChangeError {
            createError = configChangeErrorMessage(error)
        } catch {
            createError = CosignCopy.ManageSquad.createFailed(error.localizedDescription)
        }
    }

    private func configChangeErrorMessage(_ error: ConfigChangeError) -> String {
        switch error {
        case .notAutonomous:
            CosignCopy.ManageSquad.controlledNote
        case .signerNotMember:
            CosignCopy.ManageSquad.notAMemberError
        case .missingInitiatePermission:
            CosignCopy.ManageSquad.noEligibleSigner
        case .invalidMemberAddress:
            CosignCopy.ManageSquad.invalidAddress
        case .contradictoryEdit:
            CosignCopy.ManageSquad.contradictoryEditError
        case .noChanges:
            CosignCopy.ManageSquad.noChangesError
        case .thresholdOutOfRange:
            CosignCopy.ManageSquad.thresholdTooHigh
        }
    }

    // MARK: - Computed

    var projectedVoterCount: Int {
        guard let detail else { return 1 }
        let keptVoters = detail.members
            .count(where: { !stagedRemovals.contains($0.pubkey) && $0.canVote })

        return keptVoters + stagedAdditions.count
    }

    var hasChanges: Bool {
        guard let detail else { return false }
        return !stagedAdditions.isEmpty
            || !stagedRemovals.isEmpty
            || threshold != Int(detail.threshold)
    }

    var validationError: String? {
        guard projectedVoterCount >= 1 else {
            return CosignCopy.ManageSquad.noVotersRemain
        }
        guard threshold >= 1 else {
            return CosignCopy.ManageSquad.thresholdTooLow
        }
        guard threshold <= projectedVoterCount else {
            return CosignCopy.ManageSquad.thresholdTooHigh
        }
        if let detail {
            let keptProposers = detail.members.count(where: { !stagedRemovals.contains($0.pubkey) && $0.canInitiate })
            let keptExecutors = detail.members.count(where: { !stagedRemovals.contains($0.pubkey) && $0.canExecute })
            let projectedProposerCount = keptProposers + stagedAdditions.count
            let projectedExecutorCount = keptExecutors + stagedAdditions.count
            guard projectedProposerCount >= 1 else {
                return CosignCopy.ManageSquad.noProposersRemain
            }
            guard projectedExecutorCount >= 1 else {
                return CosignCopy.ManageSquad.noExecutorsRemain
            }
        }
        return nil
    }

    var canCreate: Bool {
        hasChanges && validationError == nil
    }

    var currentSignerAddresses: Set<String> {
        Set(registeredSigners.map { CosignCore.base58($0.pubkey) })
    }

    var hasSelfRemoval: Bool {
        !stagedRemovals.isDisjoint(with: currentSignerAddresses)
    }

    var stagedChangeDiff: String {
        CosignCopy.ManageSquad.diff(
            added: stagedAdditions.count,
            removed: stagedRemovals.count
        )
    }
}
