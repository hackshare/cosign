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
            timeLockSeconds = loaded.timeLockSeconds
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

    // MARK: - Time lock

    @MainActor
    func applyCustomTimeLock() {
        // numberPad prevents typing "." but a paste can include non-digit characters
        // (e.g. "1.5" parses as 15). That is a minor inaccuracy rather than data loss;
        // the out-of-range validation banner catches any result over the 90-day limit.
        let digits = timeLockCustomValue.filter(\.isNumber)
        // Clamp to a UInt32-overflow-safe bound rather than the 90-day limit, so an
        // over-limit entry still reaches `timeLockSeconds` and surfaces the range
        // banner. A paste too large to parse falls back to that bound instead of
        // silently resetting to Off.
        let maxForUnit = UInt64(UInt32.max) / UInt64(timeLockCustomUnit.seconds)
        let value = min(UInt64(digits) ?? maxForUnit, maxForUnit)
        timeLockSeconds = UInt32(value * UInt64(timeLockCustomUnit.seconds))
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
                        newTimeLockSeconds: timeLockSeconds,
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
        case .timeLockOutOfRange:
            CosignCopy.ManageSquad.timeLockOutOfRange
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
            || timeLockSeconds != detail.timeLockSeconds
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
        guard timeLockSeconds <= SquadsService.maxTimeLockSeconds else {
            return CosignCopy.ManageSquad.timeLockOutOfRange
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
